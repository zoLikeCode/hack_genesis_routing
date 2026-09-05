# frozen_string_literal: true

module Routing
  class Policy
    class AmountBands
      ALLOWED_KEYS = %w[max providers].freeze

      attr_reader :entries

      def initialize(raw)
        input!(raw.is_a?(Array) && !raw.empty?, "amount_bands must be a non-empty list")
        @entries = normalize(raw).freeze
      end

      def score(provider_name, amount)
        band = entries.find { |entry| entry.fetch("max").nil? || amount <= entry.fetch("max") }
        Routing.assert(!band.nil?, "amount bands must cover every amount")
        order = band.fetch("providers")
        index = order.index(provider_name)
        return 0.0 if index.nil?
        return 1.0 if order.one?

        1.0 - (index.to_f / (order.size - 1))
      end

      private

      def normalize(raw)
        previous = nil
        raw.each_with_index.map do |entry, index|
          normalized = normalize_entry(entry, index)
          validate_entry!(normalized, previous, index, raw.size)
          previous = normalized.fetch("max") unless normalized.fetch("max").nil?
          normalized.freeze
        end
      end

      def normalize_entry(entry, index)
        input!(entry.respond_to?(:to_h), "amount_bands[#{index}] must be a mapping")
        data = entry.to_h.transform_keys(&:to_s)
        unknown = data.keys - ALLOWED_KEYS
        input!(unknown.empty?, "amount_bands[#{index}] has unknown keys: #{unknown.join(', ')}")
        providers = data["providers"]
        data.merge("providers" => providers.is_a?(Array) ? providers.dup.freeze : providers)
      end

      def validate_entry!(entry, previous, index, size)
        maximum = entry["max"]
        providers = entry.fetch("providers")
        valid_maximum!(maximum, previous, index, size)
        valid_providers!(providers, index)
      end

      def valid_maximum!(maximum, previous, index, size)
        input!(maximum.nil? || (maximum.is_a?(Numeric) && maximum.positive?),
               "amount_bands[#{index}].max must be a positive number or null")
        input!(!(maximum.nil? && index != size - 1), "only the final amount band may have max: null")
        input!(!(index == size - 1 && !maximum.nil?), "final amount band must have max: null")
        return if maximum.nil? || previous.nil?

        input!(maximum > previous, "amount_bands maxima must be strictly increasing")
      end

      def valid_providers!(providers, index)
        valid = providers.is_a?(Array) && !providers.empty? &&
                providers.all? { |name| name.is_a?(String) && !name.empty? }
        input!(valid, "amount_bands[#{index}].providers must be a non-empty list of names")
        input!(providers.uniq.size == providers.size,
               "amount_bands[#{index}].providers must not contain duplicates")
      end

      def input!(condition, message)
        raise InvalidInputError, message unless condition
      end
    end
  end
end
