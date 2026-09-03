# frozen_string_literal: true

module Routing
  module HardConstraints
    class Margin
      def self.call(provider, _operation)
        return Result.ok if provider.allow_negative_agreement
        return Result.ok if provider.provider_margin_pct <= provider.merchant_margin_pct

        Result.skip(
          Reasons::NEGATIVE_MARGIN,
          "#{provider.provider_margin_pct} > merchant_margin_pct #{provider.merchant_margin_pct}"
        )
      end
    end
  end
end
