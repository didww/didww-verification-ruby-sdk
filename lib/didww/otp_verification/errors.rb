module DIDWW
  module OTPVerification
    # Base class for every error raised by this SDK.
    class Error < StandardError; end

    # Raised when the client is misconfigured (missing key/secret, unknown env, etc).
    class ConfigurationError < Error; end

    # A single coded error from the API's error envelope
    # +{ "errors": [ { "code", "detail" } ] }+. +code+ is a stable,
    # machine-readable slug (switch on it); +detail+ is its fixed human text.
    ErrorItem = Struct.new(:code, :detail) do
      def to_s = detail || code || ""
    end

    # Raised when the API responds with a non-2xx status. Subclasses map to
    # specific HTTP statuses. Every documented status carries the coded error
    # envelope; +errors+ is empty only when a response has no (or a non-JSON)
    # body, e.g. an error produced by a proxy in front of the API.
    class APIError < Error
      # @return [Array<ErrorItem>] coded errors from the response body.
      attr_reader :status, :errors, :response

      def initialize(message = nil, status:, errors: [], response: nil)
        @status = status
        @errors = errors
        @response = response
        details = errors.map(&:detail).compact
        super(message || (details.empty? ? "HTTP #{status}" : details.join(", ")))
      end

      # @return [String, nil] machine-readable code of the first error.
      def code = errors.first&.code

      # @return [Array<String>] machine-readable codes of every error.
      def codes = errors.map(&:code)
    end

    # 401 Unauthorized (+unauthorized+ code).
    class UnauthorizedError < APIError; end

    # 402 Payment Required (+balance_insufficient+ code).
    class BalanceInsufficientError < APIError; end

    # 404 Not Found.
    class NotFoundError < APIError; end

    # 400 Bad Request / 422 Unprocessable Content (validation errors in +errors+).
    class ValidationError < APIError; end

    # 5xx Server Error (+internal_error+ code).
    class ServerError < APIError; end
  end
end
