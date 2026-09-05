# frozen_string_literal: true

module Routing
  module Metrics
    # Sequential forecast check over observed attempts. The provider KPI is a
    # fixed published prior; without timestamped KPI snapshots this is not a
    # counterfactual routing experiment.
    class Backtest
      def self.call(history:, providers:, config:)
        return {} if history.nil?

        providers.to_h do |provider|
          rows = ordered(history.observations_for(provider.name).select { |row| Metrics.compatible?(provider, row) })
          [provider.name, evaluate(rows, provider, config)]
        end
      end

      def self.evaluate(rows, provider, config)
        seen = []
        model_errors = []
        prior_errors = []
        rows.each do |row|
          actual = row.initial_status == "approved" ? 1.0 : 0.0
          prior = provider.conversion_24h || config.default_conversion_prior
          model_errors << squared_error(prediction(seen, row, provider, config), actual)
          prior_errors << squared_error(prior.to_f.clamp(0.0, 1.0), actual)
          seen << row
        end
        result(rows, model_errors, prior_errors)
      end
      private_class_method :evaluate

      def self.prediction(seen, row, provider, config)
        operation = Operation.new(
          "operation_id" => row.operation_id, "amount" => row.amount,
          "bank" => row.bank, "created_at" => row.created_at
        )
        Catalog.call(observations: seen, provider: provider, operation: operation, config: config).score
      end
      private_class_method :prediction

      def self.squared_error(prediction, actual)
        (prediction - actual)**2
      end
      private_class_method :squared_error

      def self.result(rows, model_errors, prior_errors)
        {
          "sample_size" => rows.size,
          "model_brier" => mean(model_errors),
          "published_prior_brier" => mean(prior_errors),
          "interpretation" => "sequential observed-attempt forecast with a fixed published prior"
        }
      end
      private_class_method :result

      def self.ordered(rows)
        rows.each_with_index.sort_by { |row, index| [row.created_at, index] }.map(&:first)
      end
      private_class_method :ordered

      def self.mean(values)
        return if values.empty?

        (values.sum / values.size).round(6)
      end
      private_class_method :mean
    end
  end
end
