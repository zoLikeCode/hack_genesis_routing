# frozen_string_literal: true

require "yaml"

module Routing
  class Policy
    def self.load(path)
      new(parse(path))
    end

    def initialize(data)
      Routing.assert(data.respond_to?(:to_h), "policy must be a Hash")
      @data = stringify_keys(data.to_h)
      @strategies = stringify_strategies(@data.fetch("strategies", {}))
    end

    def weight_for(key)
      entry = @strategies[key.to_s]
      return 0 if entry.nil?
      return 0 unless entry["enabled"]

      weight = entry.fetch("weight", 0)
      Routing.assert(weight.is_a?(Numeric), "strategy weight must be numeric")
      weight
    end

    def enabled?(key)
      !weight_for(key).zero?
    end

    def fallback_provider
      name = @data.fetch("fallback_provider", "spacepayments")
      Routing.assert(name.is_a?(String) && !name.empty?, "fallback_provider required")
      name
    end

    def self.parse(path)
      data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
      raise InvalidInputError, "#{path}: policy must be a mapping" unless data.is_a?(Hash)

      data
    rescue Psych::SyntaxError, Errno::ENOENT => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end
    private_class_method :parse

    private

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end

    def stringify_strategies(raw)
      Routing.assert(raw.respond_to?(:to_h), "strategies must be a Hash")
      stringify_keys(raw.to_h).transform_values { |entry| stringify_keys(entry.to_h) }
    end
  end
end
