# frozen_string_literal: true

require "time"

module Routing
  class Operation
    attr_reader :id, :amount, :bank, :created_at, :card_brand, :payout_requisite

    def initialize(attrs)
      attrs = stringify_keys(attrs)
      @id = attrs["operation_id"]
      Routing.input!(@id.is_a?(String) && !@id.empty?, "operation_id is required")

      @amount = attrs["amount"]
      Routing.input!(@amount.is_a?(Numeric), "amount must be numeric")
      Routing.input!(@amount >= 0, "amount must be non-negative")

      @bank = attrs["bank"]
      @card_brand = attrs["card_brand"]
      @payout_requisite = attrs["payout_requisite"]
      @created_at = parse_time(attrs["created_at"])
    end

    def self.load_queue(path)
      payload = JsonFile.read(path)
      Routing.input!(payload.is_a?(Array), "operations queue must be an array")
      payload.map { |row| new(row) }
    end

    private

    def stringify_keys(attrs)
      Routing.input!(attrs.respond_to?(:to_h), "operation attrs must be a Hash")
      attrs.to_h.transform_keys(&:to_s)
    end

    def parse_time(value)
      return value if value.is_a?(Time)
      return if value.nil?

      Time.iso8601(value)
    rescue ArgumentError => e
      raise InvalidInputError, "invalid created_at: #{e.message}"
    end
  end
end
