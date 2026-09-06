# frozen_string_literal: true

require "async"
require "json"
require "socket"

RSpec.describe Routing::Adapters::AsyncHttpClient do
  it "performs call and status on one fiber", :aggregate_failures do
    server, port = json_http_server
    result = Async do
      client = described_class.new(base_url: "http://127.0.0.1:#{port}")
      call = client.call(build_provider, operation: build_operation, idempotency_key: "op_test:vipay")
      status = client.status(build_provider, operation_id: "op_test", idempotency_key: "op_test:vipay")
      client.close
      [call, status]
    end.wait

    expect(result.first).to include(result: "approved", latency_sec: 1)
    expect(result.last).to include(result: "approved")
  ensure
    server&.close
  end

  it "applies the timeout while reading the response body", :aggregate_failures do
    response = Struct.new(:closed) do
      def success? = true
      def status = 200

      def read
        Async::Task.current.sleep(0.05)
        JSON.generate("result" => "approved")
      end

      def close = self.closed = true
    end.new(false)
    internet = instance_double(Async::HTTP::Internet, post: response)
    client = described_class.new(base_url: "http://example.test", timeout_sec: 0.01, internet: internet)

    error = Async do
      client.call(build_provider, operation: build_operation, idempotency_key: "key")
    rescue StandardError => e
      e
    end.wait

    expect(error).to be_a(Async::TimeoutError)
    expect(response.closed).to be(true)
  end

  it "reports non-successful HTTP responses as transport errors" do
    response = Struct.new(:status) do
      def success? = false
      def close = nil
    end.new(500)
    internet = instance_double(Async::HTTP::Internet, post: response)
    client = described_class.new(base_url: "http://example.test", internet: internet)

    error = Async do
      client.call(build_provider, operation: build_operation, idempotency_key: "key")
    rescue StandardError => e
      e
    end.wait

    expect(error).to be_a(IOError).and have_attributes(message: include("failed with 500"))
  end

  def json_http_server
    server = TCPServer.new("127.0.0.1", 0)
    Thread.new { serve_json(server) }
    [server, server.addr[1]]
  end

  def serve_json(server)
    loop do
      client = server.accept
      read_http_request(client)
      body = JSON.generate("result" => "approved", "latency_sec" => 1)
      client.write(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
        "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      )
      client.close
    rescue IOError
      break
    end
  end

  def read_http_request(client)
    request = +""
    request << client.readpartial(4096) until request.include?("\r\n\r\n")
    headers, body = request.split("\r\n\r\n", 2)
    length = headers[/Content-Length: (\d+)/i, 1].to_i
    body ||= +""
    body << client.readpartial(4096) while body.bytesize < length
  end
end
