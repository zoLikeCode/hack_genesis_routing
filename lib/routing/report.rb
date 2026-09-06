# frozen_string_literal: true

module Routing
  class Report
    SHARE_GAP = 15
    UTILIZATION_WARN = 80

    def self.call(decisions:, operations:, providers:, policy:, **options)
      new(decisions, operations, providers, policy, options).call
    end

    def initialize(decisions, operations, providers, policy, options)
      assign_inputs(decisions, operations, providers, policy)
      assign_options(options)
      validate_inputs!
    end

    def assign_inputs(decisions, operations, providers, policy)
      @decisions = decisions
      @operations = operations
      @providers = providers
      @policy = policy
    end

    def assign_options(options)
      @history = options[:history]
      @runtime_state = options[:runtime_state]
      @status_checker = options[:status_checker]
      @circuit_breaker = options[:circuit_breaker] || @status_checker&.circuit_breaker
    end

    def validate_inputs!
      Routing.assert(@decisions.is_a?(Array) && @decisions.all?(Decision), "decisions must be Decision objects")
      Routing.assert(@operations.respond_to?(:each), "operations must be enumerable")
      Routing.assert(@providers.is_a?(ProviderPool), "providers must be a ProviderPool")
      Routing.assert(@policy.is_a?(Policy), "policy must be Routing::Policy")
      Routing.assert(@history.nil? || @history.is_a?(History), "history must be Routing::History")
      Routing.assert(@runtime_state.nil? || @runtime_state.is_a?(RuntimeState), "runtime_state must be RuntimeState")
      Routing.assert(@status_checker.nil? || @status_checker.is_a?(StatusChecker),
                     "status_checker must be StatusChecker")
      Routing.assert(@circuit_breaker.nil? || @circuit_breaker.is_a?(CircuitBreaker),
                     "circuit_breaker must be CircuitBreaker")
    end

    def call
      {
        "period" => period,
        "total_operations" => @decisions.size,
        "distribution" => distribution,
        "outcomes" => outcomes,
        "history_baseline" => history_baseline,
        "provider_metrics" => provider_metrics,
        "conversion_backtest" => conversion_backtest,
        "routing_profiles" => routing_profiles,
        "unassigned_operations" => 0,
        "rejected_operations" => rejected_decisions.size,
        "skip_reasons" => skip_reasons,
        "projected_daily_utilization" => projected_daily_utilization,
        "status_checks" => status_check_summary,
        "circuit_breakers" => circuit_breaker_summary,
        "recommendations" => recommendations
      }
    end

    private

    def period
      first = @operations.find { |operation| !operation.created_at.nil? }
      return "unknown" if first.nil?

      first.created_at.utc.to_date.iso8601
    end

    def distribution
      selected = accepted_decisions.map(&:selected_provider)
      distribution_names.to_h { |name| [name, dist_entry(name, selected)] }
    end

    def distribution_names
      names = @providers.select { |provider| provider.primary?(fallback: @policy.fallback_provider) }.map(&:name)
      names | @decisions.filter_map do |decision|
        decision.selected_provider if decision.selected_provider == @policy.fallback_provider
      end
    end

    def dist_entry(name, selected)
      count = selected.count(name)
      {
        "count" => count,
        "share_pct" => share_pct(count),
        "target_pct" => @providers.fetch(name).traffic_percentage,
        "deviation_pct" => (share_pct(count) - @providers.fetch(name).traffic_percentage).round(1)
      }
    end

    def share_pct(count)
      total = accepted_decisions.size
      return 0 if total.zero?

      (100.0 * count / total).round
    end

    def skip_reasons
      tally = Hash.new(0)
      @decisions.each do |decision|
        decision.attempts.each do |attempt|
          tally[attempt.reason] += 1 if attempt.decision == "skipped"
        end
      end
      tally
    end

    def accepted_decisions
      @decisions.reject { |decision| effective_result(decision) == "rejected" }
    end

    def rejected_decisions
      @decisions.select { |decision| effective_result(decision) == "rejected" }
    end

    def outcomes
      distribution_names.to_h do |name|
        [name, outcome_entry(name)]
      end
    end

    def outcome_entry(name)
      OutcomeStats.call(
        decisions: @decisions, provider_name: name,
        effective_result: method(:effective_result)
      )
    end

    def history_baseline
      return {} if @history.nil?

      @history.names.to_h { |name| [name, @history[name]] }
    end

    def routing_profiles
      @providers.filter_map do |provider|
        next unless provider.primary?(fallback: @policy.fallback_provider)

        [provider.name, @policy.profile_for(provider.name) || "individual"]
      end.to_h
    end

    def projected_daily_utilization
      @providers.each_with_object({}) do |provider, hash|
        limit = provider.daily_amount_limit
        next if limit.nil?

        used = provider.daily_approved_amount
        hash[provider.name] = {
          "used" => used,
          "limit" => limit,
          "utilization_pct" => limit.zero? ? 0 : (100.0 * used / limit).round(1)
        }
      end
    end

    def recommendations
      utilization_recs + share_recs + skip_recs + timeout_recs
    end

    def utilization_recs
      projected_daily_utilization.filter_map do |name, row|
        pct = row.fetch("utilization_pct")
        next unless pct >= UTILIZATION_WARN

        "#{name} utilization is #{pct}% - reduce traffic_percentage"
      end
    end

    def share_recs
      distribution.filter_map do |name, row|
        gap = (row.fetch("share_pct") - row.fetch("target_pct")).abs
        next unless gap >= SHARE_GAP

        "#{name} share_pct is #{row.fetch('share_pct')} vs target_pct #{row.fetch('target_pct')} - " \
          "adjust traffic_percentage"
      end
    end

    def skip_recs
      return [] if skip_reasons.empty?

      reason, count = skip_reasons.max_by { |_, total| total }
      return [] unless reason == "bank_not_in_list"

      ["dominant skip reason is bank_not_in_list (#{count}) - expand banks"]
    end

    def timeout_recs
      total = @decisions.count { |decision| effective_result(decision) == "expired" }
      return [] if total.zero?

      ["#{total} operations await status-check - keep reservations and do not start fallback"]
    end

    def effective_result(decision)
      return decision.simulated_result unless decision.simulated_result == "expired" && !@runtime_state.nil?

      reservation = @runtime_state.reservation_for(
        operation_id: decision.operation_id,
        provider_name: decision.selected_provider
      )
      return decision.simulated_result if reservation.nil? || reservation.timed_out?

      reservation.status
    end

    def status_check_summary
      if @status_checker.nil?
        return {
          "scheduled" => 0, "checking" => 0, "resolved" => 0,
          "reconciliation_pending" => 0, "tasks" => []
        }
      end

      @status_checker.summary
    end

    def circuit_breaker_summary
      @circuit_breaker.nil? ? {} : @circuit_breaker.summary
    end

    def provider_metrics
      ProviderStats.call(
        runtime_state: @runtime_state,
        providers: @providers,
        policy: @policy,
        names: distribution_names,
        as_of: report_as_of
      )
    end

    def conversion_backtest
      Metrics::Backtest.call(history: @history, providers: @providers, config: @policy.metrics)
    end

    def report_as_of
      @operations.filter_map(&:created_at).max
    end
  end
end
