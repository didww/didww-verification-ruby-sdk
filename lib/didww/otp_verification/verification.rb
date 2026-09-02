require "time"
require "bigdecimal"

module DIDWW
  module OTPVerification
    # Thin value object wrapping the +data+ envelope returned by every
    # verification endpoint. Statuses and error codes are an open set, so the
    # predicates below are conveniences, not an exhaustive enum.
    #
    # +error_code+/+error_detail+ say why a verification ended badly; both are
    # nil while pending and when verified. They are unrelated to the errors on
    # an APIError, which is raised instead of returning a Verification.
    class Verification
      attr_reader :id, :destination, :delivery_method, :fee, :status,
        :error_code, :error_detail, :expires_at, :sms, :callout, :raw

      def initialize(data)
        data ||= {}
        @raw = data
        @id = data["id"]
        @destination = data["destination"]
        @delivery_method = data["delivery_method"]
        @fee = data["fee"] ? BigDecimal(data["fee"]) : nil
        @status = data["status"]
        @error_code = data["error_code"]
        @error_detail = data["error_detail"]
        @expires_at = data["expires_at"] ? Time.parse(data["expires_at"]) : nil
        @sms = data["sms"]
        @callout = data["callout"]
      end

      # @return [Hash] the raw +data+ envelope this object was built from.
      def to_h
        @raw
      end

      # @return [String, nil] SMS template, only present for the +sms+ method.
      def sms_template
        @sms && @sms["template"]
      end

      # The tag the server chose for the message: the first requested language
      # it had a template for, or the +en-US+ fallback. It is a choice, never an
      # echo, so comparing it against what was asked for is how a fallback is
      # detected rather than guessed at.
      #
      # @return [String, nil] BCP 47 tag, only present for the +sms+ method.
      def sms_language
        @sms && @sms["language"]
      end

      # @return [Integer, nil] seconds to keep an SMS listener armed. Not a
      #   deadline: manual entry stays live until +expires_at+.
      def sms_interception_timeout
        @sms && @sms["interception_timeout"]
      end

      # @return [String, nil] SMS Retriever hash, echoed back only when one was
      #   stored on this verification.
      def sms_app_hash
        @sms && @sms["app_hash"]
      end

      # The tag the announcement is played in: the first requested language the
      # server had a recording for, or the +en-US+ fallback. The recordings are
      # a different catalogue from the SMS templates, so a tag honoured on +sms+
      # can still fall back here.
      #
      # @return [String, nil] BCP 47 tag, only present for the +callout+ method.
      def callout_language
        @callout && @callout["language"]
      end

      def pending? = status == "pending"
      def verified? = status == "verified"
      def failed? = status == "failed"
      def expired? = status == "expired"
      def denied? = status == "denied"

      # @return [Boolean] true once the verification reached a terminal status
      #   (successfully or not) — stop polling.
      def finished? = verified? || failed? || expired? || denied?
    end
  end
end
