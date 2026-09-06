# frozen_string_literal: true

module Routing
  module Concurrency
    class StatusWorker
      def initialize(checker:, events:)
        @checker = checker
        @events = events
      end

      def perform(task, now)
        totals = @checker.run_task(task, now)
        totals.fetch("settlements", []).each do |payload|
          @events.push(StatusEvent.new(payload))
        end
      end
    end
  end
end
