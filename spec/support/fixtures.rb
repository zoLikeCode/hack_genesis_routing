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

    def build_policy(strategies = nil)
      Routing::Policy.new(
        "fallback_provider" => "spacepayments",
        "strategies" => strategies || default_strategy_weights
      )
    end

    def empty_snapshot(**overrides)
      Routing::SoftGoals::Snapshot.new(**overrides)
    end

    def build_observation(**overrides)
      Routing::History::Observation.new(
        operation_id: overrides.fetch(:operation_id, "op_hist"),
        provider_name: overrides.fetch(:provider_name, "vipay"),
        created_at: overrides.fetch(:created_at, Time.iso8601("2026-07-30T08:00:00+03:00")),
        amount: overrides.fetch(:amount, 15_000),
        bank: overrides.fetch(:bank, "sberbank"),
        initial_status: overrides.fetch(:initial_status, overrides.fetch(:status, "approved")),
        status: overrides.fetch(:status, "approved"),
        latency_sec: overrides.fetch(:latency_sec, 30),
        attempted_at: overrides.fetch(:attempted_at, overrides.fetch(:created_at, default_observation_time)),
        admission_sequence: overrides[:admission_sequence],
        completed_at: overrides.fetch(:completed_at, nil)
      )
    end

    def default_observation_time
      Time.iso8601("2026-07-30T08:00:00+03:00")
    end

    def default_strategy_weights
      {
        "cascade_priority" => { "enabled" => true, "weight" => 1.0 }
      }
    end

    def default_provider_attrs
      default_identity_attrs
        .merge(default_goal_attrs)
        .merge(default_limit_attrs)
        .merge(default_commercial_attrs)
    end

    def default_identity_attrs
      {
        "payment_system" => "vipay",
        "status" => "active",
        "traffic_percentage" => 40
      }
    end

    def default_goal_attrs
      {
        "priority" => 1,
        "conversion_24h" => 0.87,
        "volume_share_pct" => 50,
        "daily_turnover_min" => 3_000_000,
        "daily_turnover_max" => 4_500_000
      }
    end

    def default_limit_attrs
      {
        "limit_amount_min" => 1_000,
        "limit_amount_max" => 100_000,
        "daily_amount_limit" => 5_000_000,
        "daily_approved_amount" => 0,
        "in_progress_count_limit" => 10,
        "in_progress_count" => 0,
        "in_progress_amount_limit" => 1_000_000,
        "in_progress_amount" => 0,
        "available_requisites" => 12
      }
    end

    def default_commercial_attrs
      {
        "banks" => %w[sberbank tinkoff vtb],
        "exclude_banks" => false,
        "provider_margin_pct" => 1.2,
        "merchant_margin_pct" => 1.5,
        "allow_negative_agreement" => false
      }
    end
  end
end
