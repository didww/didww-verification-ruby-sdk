require "faraday"

require_relative "otp_verification/version"
require_relative "otp_verification/errors"
require_relative "otp_verification/util"
require_relative "otp_verification/configuration"
require_relative "otp_verification/signer"
require_relative "otp_verification/middleware/signature"
require_relative "otp_verification/verification"
require_relative "otp_verification/callback_verifier"
require_relative "otp_verification/client"

module DIDWW
  module OTPVerification
    AUTH_MODES = %i[basic public application].freeze

    class << self
      # Global configuration singleton. Used as defaults by Client.
      def configuration
        @configuration ||= Configuration.new
      end

      #   DIDWW::OTPVerification.configure do |c|
      #     c.env = :sandbox
      #     c.key = ENV["DIDWW_OTP_KEY"]
      #     c.secret = ENV["DIDWW_OTP_SECRET"]
      #   end
      def configure
        yield configuration
        configuration
      end

      # Mainly for tests.
      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
