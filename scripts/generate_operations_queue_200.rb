# frozen_string_literal: true

require "json"
require "time"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "data", "operations_queue_200_test.json")
STARTED_AT = Time.iso8601("2026-07-30T09:10:00+03:00")

# Each batch is a short burst. This exercises request-rate limits while the
# 120-second distance between batches also demonstrates recovery of the window.
AMOUNTS = [
  0, 499, 500, 999, 1_000,
  1_500, 7_000, 12_000, 25_000, 49_999,
  50_000, 50_001, 75_000, 99_999, 100_000,
  100_001, 150_000, 199_999, 200_000, 200_001
].freeze

BANKS = [
  "sberbank", "alfa", "tinkoff", "vtb", "raiffeisen",
  "gazprombank", "otkritie", "sovcombank", "unknown_bank", nil
].freeze

CARD_BRANDS = [nil, "visa", "mastercard", "mir"].freeze

def requisite(index, bank)
  if index.even?
    {
      "sbp" => {
        "phone" => format("7903%07d", index + 1),
        "bank_name" => bank || "Не указан"
      }
    }
  else
    {
      "card" => {
        "pan" => format("22022000%08d", index + 1)
      }
    }
  end
end

burst = Array.new(60) do |index|
  bank = "sberbank"
  {
    "operation_id" => format("demo_200_%03d", index + 1),
    "created_at" => (STARTED_AT + index).iso8601,
    "amount" => 5_000,
    "bank" => bank,
    "card_brand" => CARD_BRANDS[index % CARD_BRANDS.size],
    "payout_requisite" => requisite(index, bank)
  }
end

matrix = 7.times.flat_map do |batch|
  AMOUNTS.each_with_index.map do |amount, position|
    index = burst.size + (batch * AMOUNTS.size) + position
    bank = BANKS[(position + (batch * 3)) % BANKS.size]
    created_at = STARTED_AT + 120 + (batch * 120) + (position * 2)

    {
      "operation_id" => format("demo_200_%03d", index + 1),
      "created_at" => created_at.iso8601,
      "amount" => amount,
      "bank" => bank,
      "card_brand" => CARD_BRANDS[index % CARD_BRANDS.size],
      "payout_requisite" => requisite(index, bank)
    }
  end
end

operations = burst + matrix

raise "expected exactly 200 operations" unless operations.size == 200

File.write(OUTPUT, "#{JSON.pretty_generate(operations)}\n")
puts "Wrote #{operations.size} operations to #{OUTPUT}"
