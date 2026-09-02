require_relative "callback_verifier"

module DIDWW
  module OTPVerification
    # Rails glue for verifying inbound callback signatures straight from an
    # ActionDispatch request.
    #
    # NOT auto-required by "didww/otp_verification" on purpose: Rails is an
    # optional runtime dependency, so services that don't run Rails pay nothing.
    # Require it explicitly where you need it:
    #
    #   require "didww/otp_verification/rails"
    #
    #   class DidwwCallbacksController < ActionController::API
    #     before_action :verify_didww_signature
    #
    #     def create
    #       # signature already verified; decide allow/deny from params
    #       render json: { action: allowed?(params) ? "allow" : "deny" }
    #     end
    #
    #     private
    #
    #     def verify_didww_signature
    #       verifier = DIDWW::OTPVerification::RailsCallbackVerifier.new(secret: app_secret)
    #       head(:unauthorized) unless verifier.valid?(request)
    #     end
    #   end
    class RailsCallbackVerifier
      # Same options as CallbackVerifier.
      def initialize(secret:, tolerance: 300, clock: -> { Time.now.to_i })
        @verifier = CallbackVerifier.new(secret: secret, tolerance: tolerance, clock: clock)
      end

      # Pulls every signed field off the ActionDispatch::Request and verifies it.
      # Uses request.raw_post so the exact received bytes are signed — never
      # re-serialize the parsed params.
      #
      # @param request [ActionDispatch::Request]
      # @return [Boolean]
      def valid?(request)
        _key, signature = CallbackVerifier.parse_authorization(request.headers["Authorization"])

        @verifier.valid?(
          method: request.request_method,
          path: request.path,
          content_type: request.content_type,
          body: request.raw_post,
          timestamp: request.headers["x-timestamp"],
          signature: signature
        )
      end
    end
  end
end
