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
