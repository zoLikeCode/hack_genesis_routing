# frozen_string_literal: true

require "async"
require "async/http"
require "json"

module Routing
  module Adapters
    class AsyncHttpClient
      def initialize(base_url:, timeout_sec: 30, internet: nil)
        Routing.assert(base_url.is_a?(String) && !base_url.empty?, "async http client requires base_url")
        Routing.assert(timeout_sec.is_a?(Numeric) && timeout_sec.positive?, "timeout_sec must be positive")
        @base_url = base_url.chomp("/")
        @timeout_sec = timeout_sec
        @internet = internet
      end

      def call(_provider, operation:, idempotency_key:)
        request("/payouts", operation_id: operation.id, idempotency_key: idempotency_key)
      end

      def status(_provider, operation_id:, idempotency_key:)
        payload = request("/status", operation_id: operation_id, idempotency_key: idempotency_key)
        { result: payload.fetch(:result) }
      end

      def close
        internet.close
      end

      private

      def request(path, **payload)
        body = JSON.generate(payload)
        response = nil
        with_timeout do
          response = internet.post("#{@base_url}#{path}", headers, body)
          parse(response)
        ensure
          response.close if response.respond_to?(:close)
        end
      end

      def with_timeout(&)
        Async::Task.current.with_timeout(@timeout_sec, &)
      end

      def internet
        @internet ||= Async::HTTP::Internet.new
      end

      def headers
        [["accept", "application/json"], ["content-type", "application/json"]]
      end

      def parse(response)
        raise IOError, "async http request failed with #{response.status}" unless response.success?

        data = JSON.parse(response.read)
        raise IOError, "async http body must be a JSON object" unless data.is_a?(Hash)

        {
          result: data["result"] || data[:result],
          latency_sec: data.fetch("latency_sec", data[:latency_sec] || 0)
        }
      end
    end
  end
end
