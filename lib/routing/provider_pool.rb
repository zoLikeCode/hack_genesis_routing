# frozen_string_literal: true

module Routing
  class ProviderPool
    include Enumerable

    def self.load(path)
      from_json(JsonFile.read(path))
    end

    def self.from_json(data)
      Routing.assert(data.is_a?(Hash), "providers payload must be a Hash")
      list = data["providers"]
      Routing.assert(list.is_a?(Array), "providers must be an array")
      new(list.map { |row| Provider.new(row) })
    end

    def initialize(providers)
      Routing.assert(providers.all?(Provider), "pool requires Provider objects")
      @providers = providers.dup
      @by_name = @providers.to_h { |provider| [provider.name, provider] }
    end

    def each(&)
      @providers.each(&)
    end

    def fetch(name)
      found = @by_name[name]
      Routing.assert(!found.nil?, "unknown provider #{name}")
      found
    end

    def reserve!(provider, operation)
      resolve(provider).reserve!(operation.amount, at: operation.created_at)
    end

    def commit_approved!(provider, amount)
      resolve(provider).commit_approved!(amount)
    end

    def release!(provider, amount)
      resolve(provider).release!(amount)
    end

    def apply_default_requests_per_minute_limit!(limit)
      @providers.each { |provider| provider.apply_default_requests_per_minute_limit!(limit) }
      self
    end

    private

    def resolve(provider)
      name = provider.is_a?(Provider) ? provider.name : provider
      fetch(name)
    end
  end
end
