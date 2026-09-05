# frozen_string_literal: true

module Routing
  module Metrics
    class Window
      attr_reader :max_observations

      def initialize(max_observations: nil, observations: [])
        Routing.assert(max_observations.nil? || (max_observations.is_a?(Integer) && max_observations.positive?),
                       "window max_observations must be nil or a positive integer")
        Routing.assert(observations.is_a?(Array) && observations.all?(History::Observation),
                       "window observations must be Observation objects")
        @max_observations = max_observations
        @observations = []
        @index = {}
        @readonly = false
        observations.each { |observation| record(observation) }
      end

      def record(observation)
        ensure_mutable!
        Routing.assert(observation.is_a?(History::Observation), "window record requires Observation")
        Routing.assert(observation.operation_id.is_a?(String) && !observation.operation_id.empty?,
                       "window observation requires operation_id")
        existing = @index[observation.operation_id]
        existing.nil? ? append(observation) : replace(existing, observation)
        self
      end

      def rewrite_status(operation_id:, status:)
        ensure_mutable!
        Routing.assert(operation_id.is_a?(String) && !operation_id.empty?, "operation_id required")
        Routing.assert(History::STATUSES.include?(status), "unknown metric status #{status}")
        found = @index[operation_id]
        return if found.nil?

        replace(found, found.with(status: status))
        @index[operation_id]
      end

      def observations
        @observations.dup.freeze
      end

      def recent(limit)
        Routing.assert(limit.is_a?(Integer) && limit >= 0, "recent limit must be a non-negative integer")
        @observations.last(limit)
      end

      def freeze_copy
        copy = self.class.new(max_observations: @max_observations, observations: @observations)
        copy.send(:make_readonly!)
        copy
      end

      private

      def append(observation)
        @observations << observation
        @index[observation.operation_id] = observation
        trim!
      end

      def replace(existing, updated)
        position = @observations.index(existing)
        Routing.assert(!position.nil?, "window index is inconsistent")
        @observations[position] = updated
        @index[updated.operation_id] = updated
      end

      def trim!
        return if @max_observations.nil?

        while @observations.size > @max_observations
          dropped = @observations.shift
          @index.delete(dropped.operation_id)
        end
      end

      def ensure_mutable!
        Routing.assert(!@readonly, "cannot mutate a frozen metrics window")
      end

      def make_readonly!
        @readonly = true
        @observations.freeze
        @index.freeze
      end
    end
  end
end
