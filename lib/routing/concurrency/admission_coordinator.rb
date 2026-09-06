# frozen_string_literal: true

module Routing
  module Concurrency
    class AdmissionCoordinator
      def initialize(engine:, inbound:, slots:, events:, progress:, clock:, payouts:) # rubocop:disable Metrics/ParameterLists
        @engine = engine
        @inbound = inbound
        @slots = slots
        @events = events
        @progress = progress
        @clock = clock
        @payouts = payouts
        @worker = PayoutWorker.new(engine: engine, events: events)
      end

      def admit(item) # rubocop:disable Metrics/AbcSize
        loop do
          now = @clock.monotonic
          selection, snapshot = @engine.admission.pick(item.operation, item.context, at: now)
          return handle_unroutable(item, selection, snapshot, now) unless selection.routable?

          unless @slots.try_submit(selection.provider.name)
            skip_slot(item, selection)
            next
          end

          reserved = @engine.admission.reserve(selection, item.operation, snapshot, at: now)
          next @engine.admission.handle_stale(item.context) if reserved.stale?
          next @engine.admission.handle_ineligible(selection, reserved, item.context) unless reserved.reserved?

          return dispatch(item, selection, reserved.reservation)
        end
      end

      private

      def skip_slot(item, selection)
        name = selection.provider.name
        item.context.add_attempt!(
          HardConstraints::Attempt.new(
            provider: name,
            decision: "skipped",
            reason: HardConstraints::Reasons::NO_DISPATCH_SLOT,
            details: "no free payout worker for #{name}"
          )
        )
        item.context.exclude_temporarily!(name)
        nil
      end

      def handle_unroutable(item, selection, snapshot, now)
        return retry_item(item) unless @engine.state.current_revision?(snapshot.revision)

        remaining = @engine.providers.reject { |provider| item.context.attempted.include?(provider.name) }
        return park(item) if remaining.any? { |provider| waitable?(provider, item.operation, now) }

        item.context.merge_skips!(selection.evaluation.skipped)
        raise InvalidInputError,
              "operation #{item.operation.id} cannot be routed without violating hard constraints"
      end

      def waitable?(provider, operation, now)
        return true unless @slots.try_submit(provider.name)

        result = HardConstraints.evaluate(provider, operation, at: now)
        return false unless result.skipped?
        return true if result.reason == HardConstraints::Reasons::RATE_LIMIT_EXCEEDED

        HardConstraints::Reasons.waitable?(result.reason) &&
          capacity_change_pending?(provider.name)
      end

      def capacity_change_pending?(provider_name)
        @engine.state.reservations.any? do |reservation|
          next false unless reservation.provider_name == provider_name && reservation.active?

          !reservation.timed_out? || @engine.status_checker.active_task?(reservation.idempotency_key)
        end
      end

      def park(item)
        item.context.clear_temporarily_excluded!
        @inbound.unshift(item)
        :parked
      end

      def retry_item(item)
        item.context.clear_temporarily_excluded!
        @inbound.unshift(item)
        :retry
      end

      def dispatch(item, selection, reservation)
        item.context.merge_skips!(selection.evaluation.skipped)
        @engine.state.mark_dispatching!(reservation, at: @clock.dispatch_time(item.operation))
        item.context.mark_attempted!(selection.provider.name)
        @payouts.call(1)
        @slots.submit(selection.provider.name) do
          @worker.perform(item, selection, reservation)
        ensure
          @payouts.call(-1)
          @progress.signal
        end
        :dispatched
      end
    end
  end
end
