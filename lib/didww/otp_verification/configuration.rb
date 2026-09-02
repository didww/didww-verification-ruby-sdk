require_relative "errors"

module DIDWW
  module OTPVerification
    # Global defaults for Client. Every field can be overridden per-Client at
    # construction time.
    class Configuration
      # The environments the API publishes. Add more with #register_env.
      DEFAULT_ENVS = {
        production: "https://verification.didww.com",
        sandbox: "https://verification-sandbox.didww.com"
      }.freeze

      attr_accessor :key, :secret, :env, :auth_mode, :adapter

      def initialize
        @envs = DEFAULT_ENVS.dup
        @env = :production
        @auth_mode = :basic
        @key = nil
        @secret = nil
        @adapter = nil
        @faraday_block = nil
      end

      # Register a named environment, e.g. a local dev server:
      #   config.register_env(:local, "http://localhost:3000")
      def register_env(name, base_url)
        @envs[name.to_sym] = base_url
      end

      # @return [String] base URL for a registered environment.
      # @raise [ConfigurationError] if the environment is unknown.
      def base_url_for(env)
        @envs.fetch(env.to_sym) do
          raise ConfigurationError,
            "unknown env #{env.inspect}; registered: #{@envs.keys.inspect}"
        end
      end

      # Register a block to customize every Faraday connection (proxy, logging,
      # timeouts, custom adapter, etc). Runs after the built-in request/response
      # middleware but before auth signing, so application-mode signatures are
      # always computed over the final request bytes.
      #   config.faraday { |conn| conn.response :logger }
      def faraday(&block)
        @faraday_block = block if block
        @faraday_block
      end
    end
  end
end
