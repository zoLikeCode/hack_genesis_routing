# frozen_string_literal: true

require "csv"
require "time"

module Routing
  class History
    Observation = Data.define(
      :operation_id, :provider_name, :created_at, :amount, :bank,
      :initial_status, :status, :latency_sec
    )

    STATUSES = %w[approved rejected expired].freeze

    attr_reader :observations

    def self.load(path)
      observations = parse(read(path))
      new(aggregate(observations), observations: observations)
    end

    def initialize(by_provider, observations: [])
      Routing.assert(by_provider.is_a?(Hash), "history must be a Hash")
      Routing.assert(observations.is_a?(Array) && observations.all?(Observation),
                     "history observations must be Observation objects")
      @by_provider = by_provider.transform_values(&:freeze).freeze
      @observations = observations.dup.freeze
      @by_name = @observations.group_by(&:provider_name).transform_values(&:freeze).freeze
    end

    def [](name)
      @by_provider[name]
    end

    def names
      @by_provider.keys
    end

    def observations_for(name)
      @by_name.fetch(name, []).freeze
    end

    def conversion_estimate(provider:, operation:, config: nil)
      Metrics::Catalog.call(
        observations: observations_for(provider.name),
        provider: provider,
        operation: operation,
        config: config
      )
    end

    alias quality conversion_estimate

    def self.read(path)
      CSV.read(path, headers: true)
    rescue Errno::ENOENT, CSV::MalformedCSVError => e
      raise InvalidInputError, "#{path}: #{e.message}"
    end
    private_class_method :read

    def self.parse(table)
      table.map { |row| observation_from(row) }
    end
    private_class_method :parse

    def self.observation_from(row)
      name = row["payment_system"]
      input_error!("payment_system is required") if name.nil? || name.empty?
      status = row["status"]
      input_error!("unknown history status #{status}") unless STATUSES.include?(status)
      Observation.new(
        operation_id: required_text(row["operation_id"], "operation_id"),
        provider_name: name,
        created_at: timestamp(row["created_at"]),
        amount: number(row["amount"], "amount"),
        bank: row["bank"],
        initial_status: status,
        status: status,
        latency_sec: optional_number(row["latency_sec"], "latency_sec")
      )
    end
    private_class_method :observation_from

    def self.required_text(value, field)
      input_error!("#{field} is required") if value.nil? || value.empty?
      value
    end
    private_class_method :required_text

    def self.aggregate(observations)
      totals = Hash.new { |hash, name| hash[name] = empty_totals }
      observations.each { |observation| record(totals[observation.provider_name], observation) }
      totals.to_h { |name, row| [name, finalize(row)] }
    end
    private_class_method :aggregate

    def self.empty_totals
      { "count" => 0, "approved_count" => 0, "attempted_volume" => 0, "approved_volume" => 0,
        "latency_sum" => 0, "latency_count" => 0 }
    end
    private_class_method :empty_totals

    def self.record(totals, observation)
      totals["count"] += 1
      totals["attempted_volume"] += observation.amount
      record_latency(totals, observation.latency_sec)
      return unless observation.initial_status == "approved"

      totals["approved_count"] += 1
      totals["approved_volume"] += observation.amount
    end
    private_class_method :record

    def self.finalize(totals)
      count = totals.fetch("count")
      {
        "count" => count,
        "approved_count" => totals.fetch("approved_count"),
        "volume" => totals.fetch("approved_volume"),
        "attempted_volume" => totals.fetch("attempted_volume"),
        "conversion" => count.zero? ? 0.0 : totals.fetch("approved_count").to_f / count,
        "avg_latency_sec" => average_latency(totals)
      }
    end
    private_class_method :finalize

    def self.timestamp(value)
      input_error!("created_at is required") if value.nil? || value.empty?
      Time.iso8601(value)
    rescue ArgumentError => e
      raise InvalidInputError, "invalid created_at: #{e.message}"
    end
    private_class_method :timestamp

    def self.number(value, field)
      input_error!("#{field} is required") if value.nil? || value.empty?
      Float(value)
    rescue ArgumentError
      raise InvalidInputError, "invalid #{field}: #{value}"
    end
    private_class_method :number

    def self.optional_number(value, field)
      return if value.nil? || value.empty?

      number(value, field)
    end
    private_class_method :optional_number

    def self.record_latency(totals, latency)
      return if latency.nil?

      totals["latency_sum"] += latency
      totals["latency_count"] += 1
    end
    private_class_method :record_latency

    def self.average_latency(totals)
      count = totals.fetch("latency_count")
      return if count.zero?

      totals.fetch("latency_sum").to_f / count
    end
    private_class_method :average_latency

    def self.input_error!(message)
      raise InvalidInputError, message
    end
    private_class_method :input_error!
  end
end
