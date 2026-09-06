# frozen_string_literal: true

module Routing
  module Concurrency
    PayoutEvent = Data.define(:item, :selection, :reservation, :outcome)
  end
end
