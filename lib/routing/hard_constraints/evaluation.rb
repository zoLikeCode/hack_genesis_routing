# frozen_string_literal: true

module Routing
  module HardConstraints
    Evaluation = Data.define(:eligible, :skipped, :fallback)
  end
end
