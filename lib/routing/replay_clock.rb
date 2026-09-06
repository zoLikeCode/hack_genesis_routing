# frozen_string_literal: true

module Routing
  class ReplayClock < Concurrency::Clock
    def initialize(start_at:, speed:)
      super()
      @start_at = start_at
      @speed = speed
      @origin = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def monotonic
      @start_at.to_f + ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @origin) * @speed)
    end

    def wall
      Time.at(monotonic).getlocal(@start_at.utc_offset)
    end

    def real_delay(seconds)
      seconds / @speed
    end

    def timeout_time(_operation, _context)
      wall
    end
  end
end
