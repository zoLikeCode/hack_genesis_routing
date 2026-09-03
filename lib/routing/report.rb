# frozen_string_literal: true

module Routing
  class Report
    SHARE_GAP = 15
    UTILIZATION_WARN = 80

    def self.call(decisions:, operations:, providers:, policy:)
      new(decisions, operations, providers, policy).call
    end

    def initialize(decisions, operations, providers, policy)
      Routing.assert(decisions.is_a?(Array) && decisions.all?(Decision), "decisions must be Decision objects")
      Routing.assert(operations.respond_to?(:each), "operations must be enumerable")
      Routing.assert(providers.is_a?(ProviderPool), "providers must be a ProviderPool")
      Routing.assert(policy.is_a?(Policy), "policy must be Routing::Policy")
      @decisions = decisions
      @operations = operations
      @providers = providers
      @policy = policy
    end

    def call
      {
        "period" => period,
        "total_operations" => @decisions.size,
        "distribution" => distribution,
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
      selected = @decisions.map(&:selected_provider)
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
        "target_pct" => @providers.fetch(name).traffic_percentage
      }
    end

    def share_pct(count)
      return 0 if @decisions.empty?

      (100.0 * count / @decisions.size).round
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
      utilization_recs + share_recs + skip_recs
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
  end
end
