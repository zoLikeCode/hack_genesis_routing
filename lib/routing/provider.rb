# frozen_string_literal: true

module Routing
  class Provider
    WINDOW_SEC = 60

    attr_reader :name, :status, :traffic_percentage, :priority,
                :limit_amount_min, :limit_amount_max,
                :daily_amount_limit, :daily_approved_amount,
                :in_progress_count_limit, :in_progress_count,
                :in_progress_amount_limit, :in_progress_amount,
                :available_requisites, :banks, :exclude_banks,
                :provider_margin_pct, :merchant_margin_pct,
                :allow_negative_agreement, :requests_per_minute_limit,
                :conversion_24h, :volume_share_pct,
                :daily_turnover_min, :daily_turnover_max

    def initialize(attrs)
      attrs = stringify_keys(attrs)
      assign_identity(attrs)
      assign_limits(attrs)
      assign_load(attrs)
      assign_commercial(attrs)
      assign_goals(attrs)
      @request_times = []
    end

    def primary?(fallback:)
      name != fallback && traffic_percentage.positive?
    end

    def reserve!(amount, at:)
      Routing.assert(amount.is_a?(Numeric) && amount >= 0, "reserve amount must be non-negative")
      @in_progress_count += 1
      @in_progress_amount += amount
      record_request!(at) unless at.nil?
    end

    def commit_approved!(amount)
      Routing.assert(amount.is_a?(Numeric) && amount >= 0, "commit amount must be non-negative")
      @daily_approved_amount += amount
    end

    def release!(amount)
      Routing.assert(amount.is_a?(Numeric) && amount >= 0, "release amount must be non-negative")
      Routing.assert(@in_progress_count.positive?, "release without matching reserve")
      Routing.assert(@in_progress_amount >= amount, "release amount exceeds in-progress")
      @in_progress_count -= 1
      @in_progress_amount -= amount
    end

    def record_request!(at)
      Routing.assert(at.is_a?(Time), "request time must be Time")
      @request_times << at
      prune_requests!(at)
    end

    def request_count_at(at)
      Routing.assert(at.is_a?(Time), "request time must be Time")
      prune_requests!(at)
      @request_times.size
    end

    private

    def stringify_keys(attrs)
      Routing.assert(attrs.respond_to?(:to_h), "provider attrs must be a Hash")
      attrs.to_h.transform_keys(&:to_s)
    end

    def assign_identity(attrs)
      @name = attrs["payment_system"]
      Routing.assert(@name.is_a?(String) && !@name.empty?, "payment_system is required")
      @status = attrs["status"]
      Routing.assert(@status.is_a?(String) && !@status.empty?, "status is required")
      @traffic_percentage = attrs.fetch("traffic_percentage", 0)
      Routing.assert(@traffic_percentage.is_a?(Numeric), "traffic_percentage must be numeric")
    end

    def assign_limits(attrs)
      @limit_amount_min = optional_number(attrs["limit_amount_min"], "limit_amount_min")
      @limit_amount_max = optional_number(attrs["limit_amount_max"], "limit_amount_max")
      @daily_amount_limit = optional_number(attrs["daily_amount_limit"], "daily_amount_limit")
      @requests_per_minute_limit = optional_integer(attrs["requests_per_minute_limit"], "requests_per_minute_limit")
    end

    def assign_load(attrs)
      @daily_approved_amount = required_number(attrs.fetch("daily_approved_amount", 0), "daily_approved_amount")
      @in_progress_count_limit = optional_integer(attrs["in_progress_count_limit"], "in_progress_count_limit")
      @in_progress_count = required_integer(attrs.fetch("in_progress_count", 0), "in_progress_count")
      @in_progress_amount_limit = optional_number(attrs["in_progress_amount_limit"], "in_progress_amount_limit")
      @in_progress_amount = required_number(attrs.fetch("in_progress_amount", 0), "in_progress_amount")
      @available_requisites = required_integer(attrs.fetch("available_requisites", 0), "available_requisites")
    end

    def assign_commercial(attrs)
      @banks = Array(attrs["banks"])
      @exclude_banks = attrs["exclude_banks"] ? true : false
      @provider_margin_pct = required_number(attrs.fetch("provider_margin_pct", 0), "provider_margin_pct")
      @merchant_margin_pct = required_number(attrs.fetch("merchant_margin_pct", 0), "merchant_margin_pct")
      @allow_negative_agreement = attrs["allow_negative_agreement"] ? true : false
    end

    def assign_goals(attrs)
      @priority = optional_positive_integer(attrs["priority"], "priority")
      @conversion_24h = optional_number(attrs["conversion_24h"], "conversion_24h")
      @volume_share_pct = optional_number(attrs["volume_share_pct"], "volume_share_pct")
      @daily_turnover_min = optional_number(attrs["daily_turnover_min"], "daily_turnover_min")
      @daily_turnover_max = optional_number(attrs["daily_turnover_max"], "daily_turnover_max")
    end

    def optional_number(value, field)
      return if value.nil?

      required_number(value, field)
    end

    def optional_integer(value, field)
      return if value.nil?

      required_integer(value, field)
    end

    def optional_positive_integer(value, field)
      return if value.nil?

      Routing.assert(value.is_a?(Integer) && value.positive?, "#{field} must be a positive integer")
      value
    end

    def required_number(value, field)
      Routing.assert(value.is_a?(Numeric), "#{field} must be numeric")
      value
    end

    def required_integer(value, field)
      Routing.assert(value.is_a?(Integer) && value >= 0, "#{field} must be a non-negative integer")
      value
    end

    def prune_requests!(at)
      cutoff = at - WINDOW_SEC
      @request_times.shift while @request_times.any? && @request_times.first < cutoff
    end
  end
end
