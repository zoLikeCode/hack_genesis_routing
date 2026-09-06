# frozen_string_literal: true

require "json"

module Routing
  module Concurrency
    class PersistQueue
      def initialize(store:, debounce_ms:, event_log: false)
        Routing.assert(store.nil? || store.is_a?(RuntimeStore), "persist queue requires RuntimeStore")
        Routing.assert(debounce_ms.is_a?(Integer) && debounce_ms >= 0, "debounce_ms must be non-negative")
        @store = store
        @debounce = debounce_ms / 1000.0
        @event_log = event_log
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @pending = nil
        @running = true
        @thread = Thread.new { writer_loop } unless store.nil?
      end

      def enqueue(state:, status_checker:)
        return if @store.nil?

        @mutex.synchronize do
          @pending = [state, status_checker]
          @condition.signal
        end
      end

      def flush
        snapshot = @mutex.synchronize { @pending }
        write(snapshot) unless snapshot.nil?
      end

      def shutdown
        return if @thread.nil?

        @mutex.synchronize do
          @running = false
          @condition.signal
        end
        @thread.join
        flush
      end

      private

      def writer_loop
        while wait_for_work
          sleep(@debounce) if @debounce.positive?
          snapshot = @mutex.synchronize { take_pending }
          write(snapshot) unless snapshot.nil?
        end
      end

      def wait_for_work
        @mutex.synchronize do
          @condition.wait(@mutex) while @running && @pending.nil?
          @running || !@pending.nil?
        end
      end

      def take_pending
        pending = @pending
        @pending = nil
        pending
      end

      def write(snapshot)
        state, checker = snapshot
        payload = @store.save(state: state, status_checker: checker)
        append_event(payload)
      end

      def append_event(payload)
        return unless @event_log

        File.open("#{@store.path}.jsonl", "a") { |file| file.puts(JSON.generate("saved_at" => payload["saved_at"])) }
      end
    end
  end
end
