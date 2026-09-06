# frozen_string_literal: true

module Routing
  class StatusCheckRunner
    TOTAL_KEYS = %w[checked resolved rescheduled reconciliation_pending].freeze

    attr_reader :checker

    def initialize(checker:, clock: nil)
      Routing.assert(checker.is_a?(StatusChecker), "status-check runner requires StatusChecker")
      @checker = checker
      @clock = clock || -> { Time.now }
      Routing.assert(@clock.respond_to?(:call), "status-check runner clock must be callable")
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @running = false
      @thread = nil
    end

    def schedule(reservation, timed_out_at:)
      task = checker.schedule(reservation, timed_out_at: timed_out_at)
      wake_up unless task.nil?
      task
    end

    def run_due(now:)
      checker.run_due(now: now)
    end

    def start
      @mutex.synchronize do
        return self if @running

        @running = true
        @thread = Thread.new { run_loop }
      end
      self
    end

    def stop
      thread = @mutex.synchronize do
        @running = false
        @condition.broadcast
        @thread
      end
      thread&.join
      self
    end

    def running?
      @mutex.synchronize { @running }
    end

    def drain
      totals = TOTAL_KEYS.to_h { |key| [key, 0] }.merge("settlements" => [])
      while (next_check_at = checker.next_check_at)
        current = run_due(now: next_check_at)
        yield current if block_given?
        merge!(totals, current)
      end
      totals.freeze
    end

    private

    def run_loop
      while (deadline = wait_for_deadline)
        run_due(now: [current_time, deadline].max)
      end
    end

    def wait_for_deadline
      @mutex.synchronize do
        loop do
          return unless @running

          deadline = checker.next_check_at
          return deadline if due?(deadline)

          @condition.wait(@mutex, wait_seconds(deadline))
        end
      end
    end

    def due?(deadline)
      !deadline.nil? && deadline <= current_time
    end

    def wait_seconds(deadline)
      return if deadline.nil?

      [deadline - current_time, 0].max
    end

    def current_time
      value = @clock.call
      Routing.assert(value.is_a?(Time), "status-check runner clock must return Time")
      value
    end

    def wake_up
      @mutex.synchronize { @condition.signal }
    end

    def merge!(totals, current)
      TOTAL_KEYS.each { |key| totals[key] += current.fetch(key) }
      totals["settlements"].concat(current.fetch("settlements", []))
    end
  end
end
