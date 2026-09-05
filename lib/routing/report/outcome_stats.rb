# frozen_string_literal: true

module Routing
  class Report
    class OutcomeStats
      def self.call(decisions:, provider_name:, effective_result:)
        new(decisions, provider_name, effective_result).call
      end

      def initialize(decisions, provider_name, effective_result)
        @decisions = decisions
        @provider_name = provider_name
        @effective_result = effective_result
      end

      def call
        final = @decisions.select { |decision| decision.selected_provider == @provider_name }
        final_counts = final.map(&@effective_result).tally
        initial_counts = final.map(&:simulated_result).tally
        rejected = initial_counts.fetch("rejected", 0) + simulated_skips(Simulator::REJECTED)
        timeouts = initial_counts.fetch("expired", 0) + simulated_skips(Simulator::EXPIRED)
        approved = initial_counts.fetch("approved", 0)
        initial = { approved: approved, rejected: rejected, timeouts: timeouts }
        build_result(final, final_counts, initial)
      end

      private

      def build_result(final, counts, initial)
        approved = initial.fetch(:approved)
        rejected = initial.fetch(:rejected)
        timeouts = initial.fetch(:timeouts)
        attempted = initial.values.sum
        final_rejected = counts.fetch("rejected", 0) + simulated_skips(Simulator::REJECTED)
        final_unresolved = counts.fetch("expired", 0) + simulated_skips(Simulator::EXPIRED)
        {
          "attempted" => attempted, "approved" => counts.fetch("approved", 0),
          "rejected" => final_rejected, "expired" => final_unresolved,
          "approval_pct" => percentage(counts.fetch("approved", 0), attempted),
          "initial_approved" => approved, "initial_rejected" => rejected, "initial_timeouts" => timeouts,
          "initial_conversion_pct" => percentage(approved, attempted),
          "initial_answer_success_pct" => percentage(approved, approved + rejected),
          "final_approved" => counts.fetch("approved", 0), "final_rejected" => final_rejected,
          "final_unresolved" => final_unresolved, "avg_final_latency_sec" => average(final.map(&:latency_sec))
        }
      end

      def simulated_skips(reason)
        @decisions.sum do |decision|
          decision.attempts.count do |attempt|
            attempt.provider == @provider_name && attempt.decision == "skipped" && attempt.reason == reason
          end
        end
      end

      def percentage(part, total)
        total.zero? ? 0.0 : (100.0 * part / total).round(1)
      end

      def average(values)
        values.empty? ? 0.0 : (values.sum.to_f / values.size).round(1)
      end
    end
  end
end
