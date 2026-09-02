require "json"

RSpec.describe DIDWW::OTPVerification::Client do
  let(:key) { "app-uuid" }
  let(:secret) { "tEsT_secret_urlsafe_base64_value_AA" }
  let(:base) { "https://verification-sandbox.didww.com" }

  def build(**opts)
    described_class.new(key: key, secret: secret, env: :sandbox, **opts)
  end

  def verification_body(overrides = {})
    {"data" => {
      "id" => "0f9c8b7a-1", "destination" => "4915112345678",
      "delivery_method" => "sms", "fee" => "0.06", "status" => "pending",
      "error_code" => nil, "error_detail" => nil,
      "expires_at" => "2026-07-15T10:02:00.000Z",
      "sms" => {"template" => "Your code is {{CODE}}"}
    }.merge(overrides)}
  end

  describe "configuration resolution" do
    it "raises when key is missing" do
      expect { described_class.new(secret: secret, env: :sandbox) }
        .to raise_error(DIDWW::OTPVerification::ConfigurationError, /key is required/)
    end

    it "raises when secret is missing in basic mode" do
      expect { described_class.new(key: key, env: :sandbox) }
        .to raise_error(DIDWW::OTPVerification::ConfigurationError, /secret is required/)
    end

    it "does not require a secret in public mode" do
      expect { described_class.new(key: key, env: :sandbox, auth_mode: :public) }
        .not_to raise_error
    end

    it "rejects an unknown auth mode" do
      expect { build(auth_mode: :nope) }
        .to raise_error(DIDWW::OTPVerification::ConfigurationError, /unknown auth_mode/)
    end

    it "rejects a malformed base64 secret in application mode at construction" do
      expect { build(secret: "not valid base64 !!!", auth_mode: :application) }
        .to raise_error(DIDWW::OTPVerification::ConfigurationError, /valid URL-safe base64/)
    end

    it "does not base64-validate the secret in basic mode" do
      expect { build(secret: "not valid base64 !!!") }.not_to raise_error
    end

    it "rejects an unknown env" do
      expect { described_class.new(key: key, secret: secret, env: :mars) }
        .to raise_error(DIDWW::OTPVerification::ConfigurationError, /unknown env/)
    end

    it "prefers an explicit base_url over env" do
      client = described_class.new(key: key, secret: secret, base_url: "https://example.test")
      expect(client.base_url).to eq("https://example.test")
    end

    it "falls back to global configuration" do
      DIDWW::OTPVerification.configure do |c|
        c.key = key
        c.secret = secret
        c.env = :sandbox
      end
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#start_verification" do
    it "POSTs the data envelope and returns a Verification" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(
          body: {data: {destination: "+4915112345678", delivery_method: "sms",
                        sms: {languages: ["en-US"]}}},
          headers: {"Content-Type" => "application/json"}
        )
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      v = build.start_verification(destination: "+4915112345678", delivery_method: "sms",
        sms: {languages: ["en-US"]})

      expect(stub).to have_been_requested
      expect(v).to be_a(DIDWW::OTPVerification::Verification)
      expect(v.id).to eq("0f9c8b7a-1")
      expect(v.fee).to eq(BigDecimal("0.06"))
      expect(v).to be_pending
      expect(v).not_to be_finished
      expect(v.sms_template).to eq("Your code is {{CODE}}")
    end

    # A top-level languages key is silently dropped by the API, so the old flat
    # shape returns 201 with the wrong language rather than an error.
    it "never sends a top-level languages key" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with { |req| !JSON.parse(req.body)["data"].key?("languages") }
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "sms", sms: {languages: ["de-DE"]})
      expect(stub).to have_been_requested
    end

    it "omits the sms object when no sms options are given" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(body: {data: {destination: "+49", delivery_method: "sms"}})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "sms")
      expect(stub).to have_been_requested
    end

    it "passes the sms object through verbatim" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(body: {data: {destination: "+49", delivery_method: "sms",
                            sms: {languages: ["de-DE"], future_option: "x"}}})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "sms",
        sms: {languages: ["de-DE"], future_option: "x"})
      expect(stub).to have_been_requested
    end

    it "passes the callout object through verbatim" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(body: {data: {destination: "+49", delivery_method: "callout",
                            callout: {languages: ["de-DE"], future_option: "x"}}})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "callout",
        callout: {languages: ["de-DE"], future_option: "x"})
      expect(stub).to have_been_requested
    end

    it "sends languages inside the callout object" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(body: {data: {destination: "+49", delivery_method: "callout",
                            callout: {languages: ["de-DE", "en-US"]}}})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "callout",
        callout: {languages: ["de-DE", "en-US"]})
      expect(stub).to have_been_requested
    end

    # The API reads only the block named after delivery_method, so a top-level
    # languages key would be dropped and the call would succeed in the wrong
    # language rather than fail.
    it "never sends a top-level languages key for callout" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with { |req| !JSON.parse(req.body)["data"].key?("languages") }
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "callout", callout: {languages: ["de-DE"]})
      expect(stub).to have_been_requested
    end

    it "omits the callout object when no callout options are given" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(body: {data: {destination: "+49", delivery_method: "callout"}})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "callout")
      expect(stub).to have_been_requested
    end

    # Each channel keyword is independent, so neither leaks into the other's block.
    it "sends only the blocks it was given" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with { |req|
          data = JSON.parse(req.body)["data"]
          !data.key?("callout") && data["sms"] == {"languages" => ["en-US"]}
        }
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "sms", sms: {languages: ["en-US"]})
      expect(stub).to have_been_requested
    end

    it "sends languages and app_hash inside the sms object" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(body: {data: {destination: "+49", delivery_method: "sms",
                            sms: {languages: ["en-US"], app_hash: "A1b2C3d4E5f"}}})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "sms",
        sms: {languages: ["en-US"], app_hash: "A1b2C3d4E5f"})
      expect(stub).to have_been_requested
    end

    it "sends a Basic auth header by default" do
      stub = stub_request(:post, "#{base}/api/v1/verifications")
        .with(headers: {"Authorization" => "Basic #{Base64.strict_encode64("#{key}:#{secret}")}"})
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.start_verification(destination: "+49", delivery_method: "sms")
      expect(stub).to have_been_requested
    end
  end

  describe "#report_verification" do
    it "PATCHes code for sms" do
      stub = stub_request(:patch, "#{base}/api/v1/verifications/abc")
        .with(body: {data: {delivery_method: "sms", code: "1234"}})
        .to_return(status: 200, body: verification_body("status" => "verified").to_json,
          headers: {"Content-Type" => "application/json"})

      v = build.report_verification("abc", delivery_method: "sms", code: "1234")
      expect(stub).to have_been_requested
      expect(v).to be_verified
    end

    it "PATCHes code for callout" do
      stub = stub_request(:patch, "#{base}/api/v1/verifications/abc")
        .with(body: {data: {delivery_method: "callout", code: "1234"}})
        .to_return(status: 200, body: verification_body("delivery_method" => "callout", "status" => "verified").to_json,
          headers: {"Content-Type" => "application/json"})

      v = build.report_verification("abc", delivery_method: "callout", code: "1234")
      expect(stub).to have_been_requested
      expect(v).to be_verified
    end

    # Every delivery method is reported with the code the user entered, so a
    # report without one is a caller bug rather than a 422 round-trip.
    it "requires a code" do
      expect { build.report_verification("abc", delivery_method: "sms") }
        .to raise_error(ArgumentError, /code/)
      expect { build.report_verification_by_number("+49", delivery_method: "sms") }
        .to raise_error(ArgumentError, /code/)
    end
  end

  describe "#get_verification" do
    it "GETs by id" do
      stub = stub_request(:get, "#{base}/api/v1/verifications/abc")
        .to_return(status: 200, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      build.get_verification("abc")
      expect(stub).to have_been_requested
    end
  end

  describe "application (signed) auth mode" do
    it "adds Authorization: Application key:signature and x-timestamp headers" do
      client = build(auth_mode: :application)
      captured = {}
      stub_request(:post, "#{base}/api/v1/verifications")
        .to_return { |req|
        captured = req.headers
        {status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"}}
      }

      client.start_verification(destination: "+49", delivery_method: "sms")

      expect(captured["Authorization"]).to match(/\AApplication #{Regexp.escape(key)}:.+/)
      expect(captured["X-Timestamp"]).to match(/\A\d+\z/)
    end

    it "signs after a user Faraday block that mutates the request body" do
      # A request middleware from the user block appends to the body. Signing
      # must run after it, so CONTENT-MD5 covers the final bytes on the wire.
      appender = Class.new(Faraday::Middleware) do
        def on_request(env)
          env.body = "#{env.body}<!--appended-->"
        end
      end
      client = described_class.new(key: key, secret: secret, env: :sandbox, auth_mode: :application) do |conn|
        conn.use appender
      end

      captured = {}
      stub_request(:post, "#{base}/api/v1/verifications")
        .to_return { |req|
        captured = {body: req.body, sig: req.headers["Authorization"], ts: req.headers["X-Timestamp"]}
        {status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"}}
      }

      client.start_verification(destination: "+49", delivery_method: "sms")

      expect(captured[:body]).to end_with("<!--appended-->")
      _, signature = captured[:sig].split(" ", 2).last.split(":", 2)
      expected = DIDWW::OTPVerification::Signer.new(secret).sign(
        method: "POST", path: "/api/v1/verifications",
        content_type: "application/json", body: captured[:body], timestamp: captured[:ts]
      )
      expect(signature).to eq(expected)
    end
  end

  describe "Verification#to_h" do
    it "returns the raw data envelope" do
      stub_request(:post, "#{base}/api/v1/verifications")
        .to_return(status: 201, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      v = build.start_verification(destination: "+49", delivery_method: "sms")
      expect(v.to_h).to eq(v.raw)
      expect(v.to_h["id"]).to eq("0f9c8b7a-1")
    end
  end

  # Every field is optional independently, so each reader falls back to nil
  # rather than assuming the block's shape.
  describe "Verification sms block" do
    def get_with_sms(sms)
      body = verification_body
      if sms.nil?
        body["data"].delete("sms")
      else
        body["data"]["sms"] = sms
      end
      stub_request(:get, "#{base}/api/v1/verifications/abc")
        .to_return(status: 200, body: body.to_json, headers: {"Content-Type" => "application/json"})
      build.get_verification("abc")
    end

    it "reads every field of a full sms block" do
      v = get_with_sms("template" => "Your code is {{CODE}}", "language" => "de-DE",
        "interception_timeout" => 120, "app_hash" => "A1b2C3d4E5f")

      expect(v.sms_template).to eq("Your code is {{CODE}}")
      expect(v.sms_language).to eq("de-DE")
      expect(v.sms_interception_timeout).to eq(120)
      expect(v.sms_app_hash).to eq("A1b2C3d4E5f")
      expect(v.sms).to eq("template" => "Your code is {{CODE}}", "language" => "de-DE",
        "interception_timeout" => 120, "app_hash" => "A1b2C3d4E5f")
    end

    it "returns nil for a key the sms block omits" do
      v = get_with_sms("template" => "Your code is {{CODE}}", "interception_timeout" => 120)

      expect(v.sms_app_hash).to be_nil
      expect(v.sms_interception_timeout).to eq(120)
    end

    it "returns nil from every sms reader when there is no sms block" do
      v = get_with_sms(nil)

      expect(v.sms).to be_nil
      expect(v.sms_template).to be_nil
      expect(v.sms_language).to be_nil
      expect(v.sms_interception_timeout).to be_nil
      expect(v.sms_app_hash).to be_nil
    end
  end

  # The callout block is its own block with its own keys, so it is read
  # independently of the sms one: a callout verification carries no sms block.
  describe "Verification callout block" do
    def get_with_callout(callout)
      body = verification_body("delivery_method" => "callout")
      body["data"].delete("sms")
      body["data"]["callout"] = callout unless callout.nil?
      stub_request(:get, "#{base}/api/v1/verifications/abc")
        .to_return(status: 200, body: body.to_json, headers: {"Content-Type" => "application/json"})
      build.get_verification("abc")
    end

    it "reads the language the server chose" do
      v = get_with_callout("language" => "de-DE")

      expect(v.callout_language).to eq("de-DE")
      expect(v.callout).to eq("language" => "de-DE")
    end

    # An unmatched tag is not an error: the announcement falls back to en-US,
    # and this reader is the only way to see that it happened.
    it "reports the en-US fallback rather than echoing the request" do
      v = get_with_callout("language" => "en-US")

      expect(v.callout_language).to eq("en-US")
    end

    # A key the API adds to the block needs no release here.
    it "keeps an unknown key readable through the raw block" do
      v = get_with_callout("language" => "de-DE", "future_key" => "x")

      expect(v.callout).to eq("language" => "de-DE", "future_key" => "x")
      expect(v.callout_language).to eq("de-DE")
    end

    it "returns nil for a key the callout block omits" do
      v = get_with_callout({})

      expect(v.callout).to eq({})
      expect(v.callout_language).to be_nil
    end

    it "returns nil from every callout reader when there is no callout block" do
      v = get_with_callout(nil)

      expect(v.callout).to be_nil
      expect(v.callout_language).to be_nil
    end

    it "leaves the sms readers nil on a callout verification" do
      v = get_with_callout("language" => "de-DE")

      expect(v.sms).to be_nil
      expect(v.sms_language).to be_nil
      expect(v.sms_template).to be_nil
    end
  end

  # A verification that ended badly reports why on a 2xx body — not an APIError.
  describe "outcome error codes" do
    def get_with(overrides)
      stub_request(:get, "#{base}/api/v1/verifications/abc")
        .to_return(status: 200, body: verification_body(overrides).to_json,
          headers: {"Content-Type" => "application/json"})
      build.get_verification("abc")
    end

    it "exposes the code and detail of a failed verification" do
      v = get_with("status" => "failed", "error_code" => "too_many_attempts",
        "error_detail" => "too many attempts")

      expect(v).to be_failed
      expect(v).to be_finished
      expect(v.error_code).to eq("too_many_attempts")
      expect(v.error_detail).to eq("too many attempts")
    end

    it "exposes a denial cause" do
      v = get_with("status" => "denied", "error_code" => "denied_by_callback",
        "error_detail" => "your callback denied the request")

      expect(v).to be_denied
      expect(v.error_code).to eq("denied_by_callback")
    end

    # A newer start for the same number retires the older one.
    it "exposes a superseded verification as failed" do
      v = get_with("status" => "failed", "error_code" => "superseded",
        "error_detail" => "superseded")

      expect(v.error_code).to eq("superseded")
    end

    it "synthesizes expired without mutating status semantics" do
      v = get_with("status" => "expired", "error_code" => "expired", "error_detail" => "expired")

      expect(v).to be_expired
      expect(v).to be_finished
      expect(v.error_code).to eq("expired")
    end

    it "leaves the code nil on a verified verification" do
      v = get_with("status" => "verified")

      expect(v).to be_verified
      expect(v).to be_finished
      expect(v.error_code).to be_nil
      expect(v.error_detail).to be_nil
    end

    it "keeps an unknown status as not finished" do
      v = get_with("status" => "something_new")

      expect(v.status).to eq("something_new")
      expect(v).not_to be_finished
    end
  end

  describe "error mapping" do
    {
      401 => DIDWW::OTPVerification::UnauthorizedError,
      402 => DIDWW::OTPVerification::BalanceInsufficientError,
      404 => DIDWW::OTPVerification::NotFoundError,
      422 => DIDWW::OTPVerification::ValidationError,
      500 => DIDWW::OTPVerification::ServerError
    }.each do |status, klass|
      it "raises #{klass} on #{status}" do
        stub_request(:get, "#{base}/api/v1/verifications/x")
          .to_return(status: status, body: "", headers: {})
        expect { build.get_verification("x") }.to raise_error(klass) do |e|
          expect(e.status).to eq(status)
        end
      end
    end

    it "raises a typed APIError when a 2xx body is not JSON" do
      stub_request(:get, "#{base}/api/v1/verifications/x")
        .to_return(status: 200, body: "<html>gateway</html>", headers: {"Content-Type" => "text/html"})

      expect { build.get_verification("x") }
        .to raise_error(DIDWW::OTPVerification::APIError, /unexpected response body/)
    end

    it "raises a typed APIError when a 2xx body is empty" do
      stub_request(:get, "#{base}/api/v1/verifications/x")
        .to_return(status: 200, body: "", headers: {"Content-Type" => "application/json"})

      expect { build.get_verification("x") }
        .to raise_error(DIDWW::OTPVerification::APIError, /unexpected response body/)
    end

    # 401 carries the coded envelope like every other status.
    it "exposes the coded envelope on 401" do
      stub_request(:get, "#{base}/api/v1/verifications/x")
        .to_return(status: 401, body: {errors: [{code: "unauthorized", detail: "unauthorized"}]}.to_json,
          headers: {"Content-Type" => "application/json"})

      expect { build.get_verification("x") }
        .to raise_error(DIDWW::OTPVerification::UnauthorizedError) do |e|
          expect(e.code).to eq("unauthorized")
          expect(e.message).to eq("unauthorized")
        end
    end

    # A proxy in front of the API can still answer without one.
    it "falls back to a status message when 401 has no body" do
      stub_request(:get, "#{base}/api/v1/verifications/x").to_return(status: 401, body: "", headers: {})

      expect { build.get_verification("x") }
        .to raise_error(DIDWW::OTPVerification::UnauthorizedError) do |e|
          expect(e.errors).to be_empty
          expect(e.code).to be_nil
          expect(e.message).to eq("HTTP 401")
        end
    end

    it "exposes coded errors on 422" do
      stub_request(:post, "#{base}/api/v1/verifications")
        .to_return(status: 422, body: {errors: [
          {code: "destination_blank", detail: "destination can't be blank"},
          {code: "delivery_method_invalid", detail: "delivery method is invalid"}
        ]}.to_json, headers: {"Content-Type" => "application/json"})

      expect { build.start_verification(destination: "", delivery_method: "sms") }
        .to raise_error(DIDWW::OTPVerification::ValidationError) do |e|
          expect(e.code).to eq("destination_blank")
          expect(e.codes).to eq(["destination_blank", "delivery_method_invalid"])
          expect(e.errors.first.detail).to eq("destination can't be blank")
          expect(e.message).to eq("destination can't be blank, delivery method is invalid")
        end
    end
  end

  describe "#get_verification_by_number" do
    it "GETs by url-encoded number" do
      stub = stub_request(:get, "#{base}/api/v1/verifications/by_number/%2B4915112345678")
        .to_return(status: 200, body: verification_body.to_json, headers: {"Content-Type" => "application/json"})

      v = build.get_verification_by_number("+4915112345678")
      expect(stub).to have_been_requested
      expect(v).to be_a(DIDWW::OTPVerification::Verification)
    end
  end

  describe "#report_verification_by_number" do
    it "PATCHes code for callout by url-encoded number" do
      stub = stub_request(:patch, "#{base}/api/v1/verifications/by_number/%2B4915112345678")
        .with(body: {data: {delivery_method: "callout", code: "1234"}})
        .to_return(status: 200, body: verification_body("status" => "verified").to_json,
          headers: {"Content-Type" => "application/json"})

      v = build.report_verification_by_number("+4915112345678", delivery_method: "callout", code: "1234")
      expect(stub).to have_been_requested
      expect(v).to be_verified
    end
  end
end
