require "openssl"
require "digest"
require "base64"

require_relative "errors"
require_relative "util"

module DIDWW
  module OTPVerification
    # HMAC-SHA256 request signer for the +application+ auth mode.
    #
    # The signing key is the application +secret+ decoded from URL-safe base64.
    # The string to sign is 5 lines joined by "\n":
    #
    #   <HTTP-METHOD>
    #   <CONTENT-MD5>            # Base64(MD5(body)), empty string when no body
    #   <CONTENT-TYPE>
    #   x-timestamp:<TIMESTAMP>
    #   <PATH>
    #
    # The signature is Base64(HMAC-SHA256(key, string_to_sign)).
    class Signer
      def initialize(secret)
        raise ConfigurationError, "secret is required for signing" if Util.blank?(secret)

        @key = Base64.urlsafe_decode64(secret)
      end

      # @return [String] the base64-encoded signature.
      def sign(method:, path:, content_type:, body:, timestamp:)
        digest = OpenSSL::HMAC.digest(
          "SHA256",
          @key,
          string_to_sign(method:, path:, content_type:, body:, timestamp:)
        )
        Base64.strict_encode64(digest)
      end

      # @return [String] the canonical string that gets signed. Exposed for
      #   debugging / cross-checking against the server implementation.
      def string_to_sign(method:, path:, content_type:, body:, timestamp:)
        content_md5 =
          if body.nil? || body.empty?
            ""
          else
            Base64.strict_encode64(Digest::MD5.digest(body))
          end

        [
          method.to_s.upcase,
          content_md5,
          content_type.to_s,
          "x-timestamp:#{timestamp}",
          path
        ].join("\n")
      end
    end
  end
end
