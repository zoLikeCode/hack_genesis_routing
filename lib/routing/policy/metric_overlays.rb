# frozen_string_literal: true

module Routing
  class Policy
    module MetricOverlays
      def metrics_for(provider = nil)
        profile = provider.nil? ? active_profile : profile_for(provider)
        overlay = profile.nil? ? nil : @profile_metrics[profile]
        Metrics::Config.combine(@metrics, overlay)
      end

      def assign_profile_metrics!(name, raw)
        return if raw.nil?

        @profile_metrics[name] = Metrics::Config.normalize_overlay(raw, "profiles.#{name}.metrics")
      end
    end
  end
end
