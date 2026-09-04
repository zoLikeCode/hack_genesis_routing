# frozen_string_literal: true

module Routing
  class Report
    SHARE_GAP = 15
    UTILIZATION_WARN = 80

    def self.call(decisions:, operations:, providers:, policy:, history: nil)
      new(decisions, operations, providers, policy, history).call
    end

    def initialize(decisions, operations, providers, policy, history)
      Routing.assert(decisions.is_a?(Array) && decisions.all?(Decision), "decisions must be Decision objects")
      Routing.assert(operations.respond_to?(:each), "operations must be enumerable")
      Routing.assert(providers.is_a?(ProviderPool), "providers must be a ProviderPool")
      Routing.assert(policy.is_a?(Policy), "policy must be Routing::Policy")
      Routing.assert(history.nil? || history.is_a?(History), "history must be Routing::History")
      @decisions = decisions
      @operations = operations
      @providers = providers
      @policy = policy
      @history = history
    end

    def call
      {
        "period" => period,
        "total_operations" => @decisions.size,
        "distribution" => distribution,
        "outcomes" => outcomes,
        "history_baseline" => history_baseline,
        "routing_profiles" => routing_profiles,
        "unassigned_operations" => 0,
        "rejected_operations" => rejected_decisions.size,
        "skip_reasons" => skip_reasons,
        "projected_daily_utilization" => projected_daily_utilization,
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
      @decisions.reject { |decision| decision.simulated_result == "rejected" }
    end

    def rejected_decisions
      @decisions.select { |decision| decision.simulated_result == "rejected" }
    end

    def outcomes
      distribution_names.to_h do |name|
        [name, outcome_entry(name)]
      end
    end

    def outcome_entry(name)
      final = @decisions.select { |decision| decision.selected_provider == name }
      counts = final.map(&:simulated_result).tally
      cascade_rejections = simulated_skips(name, Simulator::REJECTED)
      cascade_expirations = simulated_skips(name, Simulator::EXPIRED)
      attempted = final.size + cascade_rejections + cascade_expirations
      {
        "attempted" => attempted,
        "approved" => counts.fetch("approved", 0),
        "rejected" => counts.fetch("rejected", 0) + cascade_rejections,
        "expired" => counts.fetch("expired", 0) + cascade_expirations,
        "approval_pct" => percentage(counts.fetch("approved", 0), attempted),
        "avg_final_latency_sec" => average(final.map(&:latency_sec))
      }
    end

    def simulated_skips(name, reason)
      @decisions.sum do |decision|
        decision.attempts.count do |attempt|
          attempt.provider == name && attempt.decision == "skipped" && attempt.reason == reason
        end
      end
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
      utilization_recs + share_recs + skip_recs + timeout_recs + conversion_recs
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
      total = @decisions.count { |decision| decision.simulated_result == "expired" }
      return [] if total.zero?

      ["#{total} operations ended on timeout at the last provider - review fallback conversion or add capacity"]
    end

    def conversion_recs
      return [] if @history.nil?

      outcomes.filter_map do |name, current|
        baseline = @history[name]
        next if baseline.nil? || current.fetch("attempted").zero?

        historical = baseline.fetch("conversion") * 100
        current_pct = current.fetch("approval_pct")
        next unless historical - current_pct >= SHARE_GAP

        "#{name} approval_pct is #{current_pct}% vs historical #{historical.round(1)}% - review its profile weights"
      end
    end

    def percentage(part, total)
      return 0.0 if total.zero?

      (100.0 * part / total).round(1)
    end

    def average(values)
      return 0.0 if values.empty?

      (values.sum.to_f / values.size).round(1)
    end
  end
end
