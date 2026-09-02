require "faraday"

module DIDWW
  module OTPVerification
    module Middleware
      # Faraday request middleware that signs the outgoing request using the
      # +application+ auth scheme. It MUST run after the request body has been
      # serialized (i.e. after +conn.request :json+) so that CONTENT-MD5 is
      # computed over the exact bytes that go on the wire.
      #
      # Injects:
      #   Authorization: Application <key>:<signature>
      #   x-timestamp:   <unix-seconds>
      class Signature < Faraday::Middleware
        def initialize(app, key:, secret:, clock: -> { Time.now.to_i })
          super(app)
          @key = key
          @signer = Signer.new(secret)
          @clock = clock
        end

        def on_request(env)
          timestamp = @clock.call.to_s
          signature = @signer.sign(
            method: env.method,
            path: env.url.path,
            content_type: env.request_headers["Content-Type"].to_s,
            body: env.body.to_s,
            timestamp: timestamp
          )
          env.request_headers["Authorization"] = "Application #{@key}:#{signature}"
          env.request_headers["x-timestamp"] = timestamp
        end
      end
    end
  end
end
