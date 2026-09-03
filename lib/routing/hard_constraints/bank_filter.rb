# frozen_string_literal: true

module Routing
  module HardConstraints
    class BankFilter
      def self.call(provider, operation)
        banks = provider.banks
        return Result.ok if banks.empty?

        bank = operation.bank
        if provider.exclude_banks
          exclude_result(bank, banks)
        else
          allowlist_result(bank, banks)
        end
      end

      def self.exclude_result(bank, banks)
        return Result.ok unless banks.include?(bank)

        Result.skip(Reasons::BANK_EXCLUDED, "#{bank} in exclude list #{banks}")
      end
      private_class_method :exclude_result

      def self.allowlist_result(bank, banks)
        return Result.ok if banks.include?(bank)

        Result.skip(Reasons::BANK_NOT_IN_LIST, "#{bank} not in #{banks}")
      end
      private_class_method :allowlist_result
    end
  end
end
