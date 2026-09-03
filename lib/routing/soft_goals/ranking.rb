# frozen_string_literal: true

module Routing
  module SoftGoals
    Ranking = Data.define(:ordered, :scores, :conflicts, :notes) do
      def preferred
        ordered.first
      end
    end
  end
end
