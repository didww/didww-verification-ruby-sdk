require_relative "lib/didww/otp_verification/version"

Gem::Specification.new do |spec|
  spec.name = "didww-otp_verification"
  spec.version = DIDWW::OTPVerification::VERSION
  spec.authors = ["DIDWW"]
  spec.summary = "Ruby SDK for the DIDWW OTP Verification API"
  spec.description = "Client for the DIDWW OTP verification API with basic, " \
                     "public and HMAC-signed (application) auth, plus inbound " \
                     "callback signature verification."
  spec.homepage = "https://github.com/didww/didww-verification-ruby-sdk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  # No homepage_uri: it would restate spec.homepage, and RubyGems warns on
  # metadata URIs that share a value.
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "bigdecimal", "~> 3.1"
  spec.add_dependency "faraday", "~> 2.0"
end
