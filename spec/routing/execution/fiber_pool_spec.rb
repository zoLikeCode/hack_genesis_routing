# frozen_string_literal: true

require "async"
require "net/http"
require "socket"

RSpec.describe Routing::Execution::FiberPool do
  it "respects the concurrency bound", :aggregate_failures do
    Async do |task|
      pool = described_class.new(limit: 1, reactor_task: task)
      expect(pool.try_submit).to be(true)
      pool.submit { sleep_async(0.05) }
      expect(pool.try_submit).to be(false)
      pool.shutdown
    end
  end

  it "overlaps two sleeping jobs", :aggregate_failures do
    started = []
    elapsed = Async do |task|
      pool = described_class.new(limit: 2, reactor_task: task)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pool.submit do
        started << 1
        sleep_async(0.15)
      end
      pool.submit do
        started << 2
        sleep_async(0.15)
      end
      pool.shutdown
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    end.wait

    expect(started).to contain_exactly(1, 2)
    expect(elapsed).to be < 0.28
  end

  it "does not overlap blocking net/http on the reactor", :aggregate_failures do
    elapsed = Async do |task|
      pool = described_class.new(limit: 2, reactor_task: task)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      2.times do
        pool.submit do
          # Kernel-blocking work stands in for net/http without a Fiber scheduler hook.
          # Net::HTTP on this reactor uses the scheduler and would overlap; busy-wait does not.
          Net::HTTP.name
          spin(0.12)
        end
      end
      pool.shutdown
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    end.wait

    expect(elapsed).to be >= 0.2
  end

  def sleep_async(seconds)
    Async::Task.current.sleep(seconds)
  end

  def spin(seconds)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    nil until Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= seconds
  end
end
