# frozen_string_literal: true

module Routing
  class Replay
    attr_reader :groups, :clock

    def initialize(operations, speed: 100.0, max_gap: 30.0)
      Routing.input!(speed.finite? && speed.positive?, "replay speed must be finite and positive")
      Routing.input!(max_gap.finite? && max_gap.positive?, "replay gap must be finite and positive")
      Routing.input!(operations.all?(&:created_at), "replay requires created_at for every operation")
      Routing.input!(operations.each_cons(2).all? { |a, b| a.created_at <= b.created_at },
                     "replay requires operations ordered by created_at")
      @groups = build_groups(operations, max_gap)
      @clock = ReplayClock.new(start_at: operations.first&.created_at || Time.now, speed: speed)
    end

    def feed(task, &)
      origin = clock.monotonic
      groups.each do |offset, operations|
        delay = clock.real_delay(origin + offset - clock.monotonic)
        task.sleep(delay) if delay.positive?
        operations.each(&)
      end
    end

    private

    def build_groups(operations, max_gap)
      offset = 0.0
      previous = operations.first&.created_at
      operations.chunk(&:created_at).map do |created_at, group|
        offset += [created_at - previous, max_gap].min
        previous = created_at
        [offset, group]
      end
    end
  end
end
