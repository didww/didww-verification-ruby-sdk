require "faraday"
require "base64"
require "erb"

module DIDWW
  module OTPVerification
    # The API client. All three verification endpoints hang off an instance.
    #
    #   client = DIDWW::OTPVerification::Client.new(
    #     key: "app-uuid", secret: "app-secret", env: :sandbox
    #   )
    #   verification = client.start_verification(
    #     destination: "+4915112345678", delivery_method: "sms"
    #   )
    #   client.report_verification(verification.id, delivery_method: "sms", code: "1234")
    #   client.get_verification(verification.id)
    #
    # The +*_by_number+ variants address the latest verification for a phone
    # number instead of an id.
    #
    # Unspecified arguments fall back to DIDWW::OTPVerification.configuration.
    class Client
      API_PREFIX = "/api/v1".freeze
      USER_AGENT = "didww-verification-ruby/#{VERSION}".freeze

      attr_reader :key, :auth_mode, :base_url

      # @param base_url [String, nil] explicit base URL; wins over +env+.
      # @param env [Symbol, nil] a registered environment name.
      # @param auth_mode [Symbol] :basic (default), :public, or :application.
      # @param adapter [Symbol, Array, nil] a Faraday adapter override.
      # @yield [conn] optional per-client Faraday customization.
      def initialize(key: nil, secret: nil, env: nil, base_url: nil,
        auth_mode: nil, adapter: nil, &faraday_block)
        config = OTPVerification.configuration
        @key = key || config.key
        @secret = secret || config.secret
        @auth_mode = (auth_mode || config.auth_mode).to_sym
        @base_url = base_url || config.base_url_for(env || config.env)
        @adapter = adapter || config.adapter
        @faraday_block = faraday_block || config.faraday
        validate!
      end

      # POST /api/v1/verifications
      #
      # Options specific to one delivery method go in a keyword named after it,
      # e.g. <tt>sms: { languages: ["en-US"] }</tt> or
      # <tt>callout: { languages: ["de-DE"] }</tt>, and travel verbatim. The API
      # reads only the block matching +delivery_method+ and ignores the others.
      # An unrecognized option is ignored rather than rejected, so a typo there
      # fails silently. Methods with no options of their own take no keyword.
      #
      # The +sms+ key +app_hash+ is deprecated: it is sent as
      # <tt>autofill: {type: "app_hash", value: ...}</tt> with a deprecation
      # warning. Passing it together with +autofill+ raises ArgumentError,
      # because the API rejects that combination.
      def start_verification(destination:, delivery_method:, sms: nil, callout: nil)
        data = {destination:, delivery_method:}
        data[:sms] = sms unless sms.nil?
        data[:callout] = callout unless callout.nil?
        data[:sms] = migrate_app_hash(data[:sms]) if data[:sms].is_a?(Hash)
        request(:post, "#{API_PREFIX}/verifications", data)
      end

      # PATCH /api/v1/verifications/:id. Reports the +code+ the user entered;
      # every delivery method is reported the same way. NB: reporting counts as
      # an attempt (max 3), so never auto-retry this call.
      def report_verification(id, delivery_method:, code:)
        request(:patch, "#{API_PREFIX}/verifications/#{id}", {delivery_method:, code:})
      end

      # GET /api/v1/verifications/:id
      def get_verification(id)
        handle(connection.get("#{API_PREFIX}/verifications/#{id}"))
      end

      # PATCH /api/v1/verifications/by_number/:number. Reports against the latest
      # verification for +number+ (E.164, leading + optional). Same attempt
      # caveat as #report_verification: never auto-retry.
      def report_verification_by_number(number, delivery_method:, code:)
        request(:patch, "#{API_PREFIX}/verifications/by_number/#{encode(number)}",
          {delivery_method:, code:})
      end

      # GET /api/v1/verifications/by_number/:number. +number+ is E.164 with an
      # optional leading +.
      def get_verification_by_number(number)
        handle(connection.get("#{API_PREFIX}/verifications/by_number/#{encode(number)}"))
      end

      private

      # Maps the deprecated sms +app_hash+ onto +autofill+ on a copy, so the
      # caller's hash is left alone.
      def migrate_app_hash(sms)
        keys = [:app_hash, "app_hash"].select { |k| sms.key?(k) }
        return sms if keys.empty?

        # A nil hash counts as absent, as the API always treated it.
        key = keys.find { |k| !sms[k].nil? }
        return sms.except(*keys) unless key
        # A nil autofill counts as absent too, as the API treats it.
        autofill_keys = [:autofill, "autofill"].select { |k| sms.key?(k) }
        if autofill_keys.any? { |k| !sms[k].nil? }
          raise ArgumentError, "sms: pass either autofill or the deprecated app_hash, not both"
        end

        warn "DIDWW::OTPVerification: sms app_hash is deprecated; " \
          "use sms: {autofill: {type: \"app_hash\", value: ...}}", category: :deprecated, uplevel: 2
        sms.except(*keys, *autofill_keys).merge(autofill: {type: "app_hash", value: sms[key]})
      end

      # Percent-encode a value for use as a single URL path segment. Notably
      # turns a leading "+" into "%2B" so it survives proxies that would
      # otherwise decode "+" to a space in the path.
      def encode(segment)
        ERB::Util.url_encode(segment.to_s)
      end

      def request(method, path, data)
        handle(connection.public_send(method, path, {data: data}))
      end

      def handle(response)
        body = response.body

        if response.success?
          unless body.is_a?(Hash)
            raise APIError.new(
              "unexpected response body",
              status: response.status,
              response: response
            )
          end
          return Verification.new(body["data"])
        end

        errors = parse_errors(body)
        klass = error_class(response.status)
        extra = (klass == RateLimitedError) ? {retry_after: parse_retry_after(response)} : {}
        raise klass.new(status: response.status, errors: errors, response: response, **extra)
      end

      # Map the {"errors": [{"code", "detail"}]} envelope to ErrorItem objects.
      # Tolerates a plain-string element by exposing it as the +detail+.
      def parse_errors(body)
        return [] unless body.is_a?(Hash)

        Array(body["errors"]).map do |item|
          if item.is_a?(Hash)
            ErrorItem.new(item["code"], item["detail"])
          else
            ErrorItem.new(nil, item.to_s)
          end
        end
      end

      # @return [Integer, nil] the Retry-After header in seconds, nil if
      #   missing or not a plain non-negative integer (e.g. an HTTP-date).
      def parse_retry_after(response)
        value = response.headers["Retry-After"].to_s
        Integer(value, 10) if value.match?(/\A\d+\z/)
      end

      def error_class(status)
        case status
        when 401 then UnauthorizedError
        when 402 then BalanceInsufficientError
        when 404 then NotFoundError
        when 400, 422 then ValidationError
        when 429 then RateLimitedError
        when 500..599 then ServerError
        else APIError
        end
      end

      def connection
        @connection ||= Faraday.new(url: @base_url) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          @faraday_block&.call(conn)
          # After the caller's block, so the block cannot replace it.
          conn.headers["User-Agent"] = USER_AGENT
          # Auth (signing) must be installed last so it sees the final request
          # bytes/headers/path, after any user middleware from @faraday_block.
          apply_auth(conn)
          conn.adapter(*Array(@adapter || Faraday.default_adapter))
        end
      end

      def apply_auth(conn)
        case @auth_mode
        when :basic
          conn.request :authorization, :basic, @key, @secret
        when :public
          conn.headers["Authorization"] = "Application #{@key}"
        when :application
          conn.use Middleware::Signature, key: @key, secret: @secret
        end
      end

      def validate!
        unless AUTH_MODES.include?(@auth_mode)
          raise ConfigurationError,
            "unknown auth_mode #{@auth_mode.inspect}; expected one of #{AUTH_MODES.inspect}"
        end
        raise ConfigurationError, "key is required" if Util.blank?(@key)
        if secret_required? && Util.blank?(@secret)
          raise ConfigurationError, "secret is required for #{@auth_mode} auth mode"
        end

        validate_signing_secret! if @auth_mode == :application
      end

      def secret_required?
        @auth_mode == :basic || @auth_mode == :application
      end

      # The application secret is the URL-safe base64 signing key; decode it now
      # so a malformed secret fails fast here instead of raising an untyped
      # ArgumentError from Signer on the first request.
      def validate_signing_secret!
        Base64.urlsafe_decode64(@secret)
      rescue ArgumentError
        raise ConfigurationError,
          "secret is not valid URL-safe base64 for #{@auth_mode} auth mode"
      end
    end
  end
end
