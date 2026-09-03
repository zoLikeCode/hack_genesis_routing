# frozen_string_literal: true

module RoutingSpec
  module Fixtures
    def build_operation(**overrides)
      attrs = {
        "operation_id" => "op_test",
        "amount" => 15_000,
        "bank" => "sberbank",
        "created_at" => "2026-07-30T09:05:00+03:00"
      }
      overrides.each { |key, value| attrs[key.to_s] = value }
      Routing::Operation.new(attrs)
    end

    def build_provider(**overrides)
      attrs = default_provider_attrs
      overrides.each { |key, value| attrs[key.to_s] = value }
      Routing::Provider.new(attrs)
    end

    def default_provider_attrs
      {
        "payment_system" => "vipay",
        "status" => "active",
        "traffic_percentage" => 40,
        "limit_amount_min" => 1_000,
        "limit_amount_max" => 100_000,
        "daily_amount_limit" => 5_000_000,
        "daily_approved_amount" => 0,
        "in_progress_count_limit" => 10,
        "in_progress_count" => 0,
        "in_progress_amount_limit" => 1_000_000,
        "in_progress_amount" => 0,
        "available_requisites" => 12,
        "banks" => %w[sberbank tinkoff vtb],
        "exclude_banks" => false,
        "provider_margin_pct" => 1.2,
        "merchant_margin_pct" => 1.5,
        "allow_negative_agreement" => false
      }
    end
  end
end
