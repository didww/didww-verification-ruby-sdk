# Standalone helper for the Rails integration suite. Kept out of the main
# spec/ tree so the core gem specs never load Rails — Rails is only a dev
# dependency here, never a runtime dependency of the gem.
require "didww/otp_verification"
require "didww/otp_verification/rails"

require "action_controller/railtie"
require "rack/test"

# The URL-safe base64 signing key shared by the signer and the verifier.
CALLBACK_SECRET = "tEsT_secret_urlsafe_base64_value_AA"

# Minimal Rails application: just enough to route a POST to a real controller
# and run the full middleware/params stack, so the verifier is exercised
# against a genuine ActionDispatch::Request.
class TestApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "test-secret-key-base"
  config.hosts.clear
  config.logger = Logger.new(IO::NULL)
  config.active_support.to_time_preserves_timezone = :zone if config.active_support.respond_to?(:to_time_preserves_timezone=)

  routes.append do
    post "/callbacks/didww", to: "didww_callbacks#create"
  end
end
TestApplication.initialize!

# Mirrors the controller documented in the README: signature is enforced in a
# before_action, and #create decides allow/deny from the callback params.
class DidwwCallbacksController < ActionController::API
  before_action :verify_didww_signature

  def create
    allow = params.dig(:data, :destination) == "+4915112345678"
    render json: {action: allow ? "allow" : "deny"}
  end

  private

  def verify_didww_signature
    verifier = DIDWW::OTPVerification::RailsCallbackVerifier.new(secret: CALLBACK_SECRET)
    head(:unauthorized) unless verifier.valid?(request)
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
end
