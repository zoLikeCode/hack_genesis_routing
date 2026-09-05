# frozen_string_literal: true

module Routing
  class RuntimeState
    Snapshot = Data.define(:revision, :providers, :soft_goals)

    class ReserveResult
      STATUSES = %w[reserved stale ineligible].freeze

      attr_reader :reservation, :reason, :details

      def self.reserved(reservation)
        new("reserved", reservation: reservation)
      end

      def self.stale
        new("stale")
      end

      def self.ineligible(result)
        new("ineligible", reason: result.reason, details: result.details)
      end

      def initialize(status, reservation: nil, reason: nil, details: nil)
        Routing.assert(STATUSES.include?(status), "unknown reserve result #{status}")
        @status = status
        @reservation = reservation
        @reason = reason
        @details = details
      end

      def reserved?
        @status == "reserved"
      end

      def stale?
        @status == "stale"
      end
    end

    attr_reader :providers, :history, :metrics

    def initialize(providers, history: nil, metrics_config: nil, policy: nil)
      Routing.assert(providers.is_a?(ProviderPool), "providers must be a ProviderPool")
      Routing.assert(history.nil? || history.is_a?(History), "runtime history must be Routing::History")
      Routing.assert(policy.nil? || policy.is_a?(Policy), "runtime policy must be Routing::Policy")
      @providers = providers
      @history = history
      @metrics = Metrics::Store.seed(
        history: history,
        providers: providers,
        config: metrics_config || policy&.metrics
      )
      @committed_counts = Hash.new(0)
      @pending_counts = Hash.new(0)
      @reservations = {}
      @revision = 0
      @mutex = Mutex.new
    end

    def snapshot
      @mutex.synchronize do
        provider_views = @providers.map(&:snapshot_copy).freeze
        counts = effective_counts
        soft_goals = SoftGoals::Snapshot.from_providers(
          provider_views,
          counts: counts,
          history: history,
          metrics: metrics.snapshot,
          version: @revision,
          readonly: true
        )
        Snapshot.new(revision: @revision, providers: provider_views, soft_goals: soft_goals)
      end
    end

    def current_revision?(revision)
      Routing.assert(revision.is_a?(Integer) && revision >= 0, "revision must be non-negative")
      @mutex.synchronize { @revision == revision }
    end

    def try_reserve!(provider, operation, expected_revision:)
      Routing.assert(provider.is_a?(Provider), "provider must be Routing::Provider")
      Routing.assert(operation.is_a?(Operation), "operation must be Routing::Operation")
      Routing.assert(expected_revision.is_a?(Integer) && expected_revision >= 0, "revision must be non-negative")
      @mutex.synchronize do
        return ReserveResult.stale unless @revision == expected_revision

        live = @providers.fetch(provider.name)
        result = HardConstraints.evaluate(live, operation)
        return ReserveResult.ineligible(result) if result.skipped?

        reservation = create_reservation(operation, live)
        live.reserve!(operation.amount, at: operation.created_at)
        @pending_counts[live.name] += 1
        @reservations[reservation.idempotency_key] = reservation
        bump_revision!
        ReserveResult.reserved(reservation)
      end
    end

    def approve!(reservation)
      settle!(reservation, "approved")
    end

    def reject!(reservation)
      settle!(reservation, "rejected")
    end

    def mark_timeout!(reservation)
      @mutex.synchronize do
        stored = active_reservation!(reservation)
        stored.mark_timed_out!
        bump_revision!
        stored
      end
    end

    def resolve_timeout!(operation_id:, provider_name:, result:)
      Routing.assert(operation_id.is_a?(String) && !operation_id.empty?, "operation id required")
      Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
      settlement = timeout_settlement(result)
      key = "#{operation_id}:#{provider_name}"
      @mutex.synchronize do
        found = @reservations[key]
        Routing.assert(!found.nil?, "unknown reservation #{key}")
        return found unless found.active?

        Routing.assert(found.timed_out?, "reservation #{key} is not timed out")
        settle_active!(found, settlement)
        rewrite_metric!(operation_id: operation_id, provider_name: provider_name, status: settlement)
        found
      end
    end

    def record_outcome!(reservation:, operation:, status:, latency_sec:)
      validate_metric!(operation, reservation.provider_name, status, latency_sec)
      @mutex.synchronize do
        stored = active_reservation!(reservation)
        @metrics.record(metric_observation(operation, stored.provider_name, status, latency_sec))
        if status == "expired"
          stored.mark_timed_out!
          bump_revision!
        else
          settle_active!(stored, status)
        end
        stored
      end
    end

    def reservations
      @mutex.synchronize { @reservations.values.dup.freeze }
    end

    def record_metric!(operation:, provider_name:, status:, latency_sec:)
      validate_metric!(operation, provider_name, status, latency_sec)
      @mutex.synchronize do
        @metrics.record(metric_observation(operation, provider_name, status, latency_sec))
        bump_revision!
      end
    end

    def reservation_for(operation_id:, provider_name:)
      key = "#{operation_id}:#{provider_name}"
      @mutex.synchronize { @reservations[key] }
    end

    private

    def rewrite_metric!(operation_id:, provider_name:, status:)
      mapped = status == "approved" ? "approved" : "rejected"
      @metrics.update_status(
        operation_id: operation_id,
        provider_name: provider_name,
        status: mapped
      )
    end

    def validate_metric!(operation, provider_name, status, latency_sec)
      Routing.assert(operation.is_a?(Operation), "metric record requires Operation")
      Routing.assert(provider_name.is_a?(String) && !provider_name.empty?, "provider name required")
      Routing.assert(History::STATUSES.include?(status), "unknown metric status #{status}")
      Routing.assert(latency_sec.nil? || (latency_sec.is_a?(Numeric) && latency_sec >= 0),
                     "latency_sec must be nil or non-negative")
    end

    def metric_observation(operation, provider_name, status, latency_sec)
      Routing.assert(latency_sec.nil? || (latency_sec.is_a?(Numeric) && latency_sec >= 0),
                     "latency_sec must be nil or non-negative")
      History::Observation.new(
        operation_id: operation.id,
        provider_name: provider_name,
        created_at: operation.created_at || Time.at(0),
        amount: operation.amount,
        bank: operation.bank,
        initial_status: status,
        status: status,
        latency_sec: latency_sec
      )
    end

    def create_reservation(operation, provider)
      reservation = Reservation.new(operation: operation, provider_name: provider.name)
      duplicate = @reservations[reservation.idempotency_key]
      Routing.assert(duplicate.nil?, "duplicate reservation #{reservation.idempotency_key}")
      reservation
    end

    def settle!(reservation, result)
      Routing.assert(%w[approved rejected].include?(result), "unsupported settlement #{result}")
      @mutex.synchronize do
        stored = active_reservation!(reservation)
        settle_active!(stored, result)
      end
    end

    def settle_active!(stored, result)
      provider = @providers.fetch(stored.provider_name)
      provider.release!(stored.amount)
      @pending_counts[provider.name] -= 1
      Routing.assert(@pending_counts[provider.name] >= 0, "pending selection count became negative")

      if result == "approved"
        provider.commit_approved!(stored.amount)
        @committed_counts[provider.name] += 1
        stored.approve!
      else
        stored.reject!
      end
      bump_revision!
      stored
    end

    def timeout_settlement(result)
      return "approved" if result == "approved"
      return "rejected" if %w[rejected cancelled].include?(result)

      Routing.assert(false, "unsupported timeout resolution #{result}")
    end

    def active_reservation!(reservation)
      Routing.assert(reservation.is_a?(Reservation), "reservation must be Routing::Reservation")
      stored = @reservations[reservation.idempotency_key]
      Routing.assert(stored.equal?(reservation), "reservation does not belong to this runtime state")
      Routing.assert(stored.active?, "reservation #{stored.idempotency_key} is already settled")
      stored
    end

    def effective_counts
      names = @providers.map(&:name) | @committed_counts.keys | @pending_counts.keys
      names.to_h { |name| [name, @committed_counts[name] + @pending_counts[name]] }
    end

    def bump_revision!
      @revision += 1
    end
  end
end
