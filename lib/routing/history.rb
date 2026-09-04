# frozen_string_literal: true

require "csv"

module Routing
  class History
    def self.load(path)
      new(aggregate(read(path)))
    end

    def initialize(by_provider)
      Routing.assert(by_provider.is_a?(Hash), "history must be a Hash")
      @by_provider = by_provider.transform_values(&:freeze).freeze
    end

    def [](name)
      @by_provider[name]
    end

    def names
      @by_provider.keys
    end

    def self.read(path)
      CSV.read(path, headers: true)
    rescue Errno::ENOENT, CSV::MalformedCSVError => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end
    private_class_method :read

    def self.aggregate(table)
      Routing.assert(table.respond_to?(:each), "history table must be enumerable")
      totals = Hash.new { |hash, name| hash[name] = empty_totals }

      table.each do |row|
        name = row["payment_system"]
        input_error!("payment_system is required") if name.nil? || name.empty?
        record_row(totals[name], row)
      end

      totals.to_h { |name, row| [name, finalize(row)] }
    end
    private_class_method :aggregate

    def self.empty_totals
      { "count" => 0, "approved_count" => 0, "attempted_volume" => 0, "approved_volume" => 0, "latency_sum" => 0 }
    end
    private_class_method :empty_totals

    def self.record_row(totals, row)
      totals["count"] += 1
      amount = number(row["amount"], "amount")
      totals["attempted_volume"] += amount
      totals["latency_sum"] += number(row["latency_sec"], "latency_sec")
      return unless row["status"] == "approved"

      totals["approved_count"] += 1
      totals["approved_volume"] += amount
    end
    private_class_method :record_row

    def self.finalize(totals)
      count = totals.fetch("count")
      {
        "count" => count,
        "approved_count" => totals.fetch("approved_count"),
        "volume" => totals.fetch("approved_volume"),
        "attempted_volume" => totals.fetch("attempted_volume"),
        "conversion" => count.zero? ? 0.0 : totals.fetch("approved_count").to_f / count,
        "avg_latency_sec" => count.zero? ? 0.0 : totals.fetch("latency_sum").to_f / count
      }
    end
    private_class_method :finalize

    def self.number(value, field)
      return 0.0 if value.nil? || value.empty?

      Float(value)
    rescue ArgumentError
      raise InvalidInputError, "invalid #{field}: #{value}"
    end
    private_class_method :number

    def self.input_error!(message)
      raise InvalidInputError, message
    end
    private_class_method :input_error!
  end
end
