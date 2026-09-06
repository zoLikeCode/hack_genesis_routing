# frozen_string_literal: true

module Routing
  class RuntimeState
    module Serialization
      def to_h
        @mutex.synchronize do
          {
            "revision" => @revision,
            "providers" => @providers.to_h { |provider| [provider.name, provider.runtime_to_h] },
            "committed_counts" => @committed_counts.to_h,
            "pending_counts" => @pending_counts.to_h,
            "reservations" => @reservations.values.map(&:to_h),
            "metrics" => serialized_metrics
          }
        end
      end

      private

      def serialized_metrics
        @metrics.names.to_h do |name|
          [name, @metrics.observations_for(name).map { |observation| serialize_observation(observation) }]
        end
      end

      def serialize_observation(observation)
        {
          "operation_id" => observation.operation_id,
          "provider" => observation.provider_name,
          "created_at" => observation.created_at.iso8601,
          "amount" => observation.amount,
          "bank" => observation.bank,
          "initial_status" => observation.initial_status,
          "status" => observation.status,
          "latency_sec" => observation.latency_sec,
          "attempted_at" => serialize_time(observation.attempted_at),
          "admission_sequence" => observation.admission_sequence,
          "completed_at" => serialize_time(observation.completed_at)
        }
      end

      def serialize_time(value)
        return if value.nil?

        value.is_a?(Time) ? value.iso8601 : value
      end
    end
  end
end
