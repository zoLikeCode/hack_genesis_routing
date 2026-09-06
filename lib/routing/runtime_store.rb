# frozen_string_literal: true

require "time"

module Routing
  class RuntimeStore
    SCHEMA_VERSION = 1

    attr_reader :path

    def initialize(path)
      Routing.input!(path.is_a?(String) && !path.empty?, "runtime state path is required")
      @path = path
      @mutex = Mutex.new
    end

    def save(state:, status_checker:)
      Routing.assert(state.is_a?(RuntimeState), "runtime store requires RuntimeState")
      Routing.assert(status_checker.is_a?(StatusChecker), "runtime store requires StatusChecker")
      payload = {
        "schema_version" => SCHEMA_VERSION,
        "saved_at" => Time.now.utc.iso8601,
        "runtime_state" => state.to_h,
        "status_checks" => status_checker.summary,
        "circuit_breakers" => status_checker.circuit_breaker.summary
      }
      @mutex.synchronize { JsonFile.write(path, payload) }
      payload
    end
  end
end
