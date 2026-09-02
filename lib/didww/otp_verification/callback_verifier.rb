require "time"
require "openssl"

# Required directly by callback-only services; cannot assume the entry point.
require_relative "util"
require_relative "signer"

module DIDWW
  module OTPVerification
    # Verifies the signature of an inbound verification-request callback that
    # DIDWW sends to your server. Uses the same HMAC scheme as outbound signing,
    # where PATH is the path of *your* callback URL.
    #
    # Has no Faraday dependency on purpose: a service that only receives
    # callbacks should not need the HTTP client.
    #
    #   verifier = DIDWW::OTPVerification::CallbackVerifier.new(secret: app_secret)
    #   key, signature = DIDWW::OTPVerification::CallbackVerifier.parse_authorization(auth_header)
    #   verifier.valid?(
    #     method: "POST", path: "/callbacks/didww",
    #     content_type: "application/json", body: raw_body,
    #     timestamp: request.headers["x-timestamp"], signature: signature
    #   )
    class CallbackVerifier
      # @param tolerance [Integer] max allowed clock skew, in seconds (server uses 5 minutes).
      def initialize(secret:, tolerance: 300, clock: -> { Time.now.to_i })
        @signer = Signer.new(secret)
        @tolerance = tolerance
        @clock = clock
      end

      # Splits an "Application <key>:<signature>" header into [key, signature].
      # Returns [nil, nil] if the header is missing or not in that form.
      def self.parse_authorization(header)
        return [nil, nil] if header.nil?

        scheme, credentials = header.split(" ", 2)
        return [nil, nil] unless scheme == "Application" && credentials

        key, signature = credentials.split(":", 2)
        [key, signature]
      end

      # @return [Boolean] true when both the timestamp is fresh and the
      #   signature matches (constant-time comparison).
      def valid?(method:, path:, content_type:, body:, timestamp:, signature:)
        return false if Util.blank?(signature)
        return false unless fresh?(timestamp)

        expected = @signer.sign(
          method:, path:, content_type:, body:, timestamp: timestamp
        )
        secure_compare(expected, signature)
      end

      private

      def fresh?(timestamp)
        return false if Util.blank?(timestamp)

        (@clock.call - timestamp.to_i).abs <= @tolerance
      end

      # Constant-time string comparison via the audited stdlib implementation.
      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        OpenSSL.fixed_length_secure_compare(a, b)
      end
    end
  end
end
