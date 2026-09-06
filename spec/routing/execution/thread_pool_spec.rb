# frozen_string_literal: true

RSpec.describe Routing::Execution::ThreadPool do
  it "respects the concurrency bound" do
    pool = described_class.new(limit: 2)
    running = 0
    peak = 0
    mutex = Mutex.new
    jobs = Array.new(4) do
      lambda do
        mutex.synchronize do
          running += 1
          peak = [peak, running].max
        end
        sleep(0.05)
        mutex.synchronize { running -= 1 }
      end
    end

    jobs.each do |job|
      sleep(0.001) until pool.try_submit
      pool.submit(&job)
    end
    pool.shutdown

    expect(peak).to eq(2)
  end

  it "overlaps two sleeping jobs" do
    pool = described_class.new(limit: 2)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    2.times { pool.submit { sleep(0.15) } }
    pool.shutdown

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).to be < 0.28
  end
end
