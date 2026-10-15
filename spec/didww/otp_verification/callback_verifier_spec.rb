RSpec.describe DIDWW::OTPVerification::CallbackVerifier do
  # Runs in a child process because spec_helper has already loaded everything,
  # so this suite cannot otherwise prove the README's require works alone.
  describe "standalone require path" do
    def child(require_path)
      script = <<~RUBY
        require "#{require_path}"
        DIDWW::OTPVerification::CallbackVerifier.new(secret: "dGVzdA==")
        abort("faraday was loaded") if $LOADED_FEATURES.any? { |f| f.include?("faraday") }
        print "ok"
      RUBY
      lib = File.expand_path("../../../lib", __dir__)
      IO.popen([RbConfig.ruby, "-I#{lib}", "-e", script], err: [:child, :out], &:read)
    end

    it "constructs from didww/otp_verification/callback_verifier alone, without Faraday" do
      expect(child("didww/otp_verification/callback_verifier")).to eq("ok")
    end

    it "constructs from didww/otp_verification/rails alone, without Faraday" do
      expect(child("didww/otp_verification/rails")).to eq("ok")
    end
  end

  let(:secret) { "tEsT_secret_urlsafe_base64_value_AA" }
  let(:signer) { DIDWW::OTPVerification::Signer.new(secret) }
  let(:now) { 1_700_000_000 }
  let(:body) { '{"event":"verification_request"}' }
  let(:path) { "/callbacks/didww" }

  subject(:verifier) { described_class.new(secret: secret, clock: -> { now }) }

  def sign(timestamp)
    signer.sign(
      method: "POST", path: path, content_type: "application/json",
      body: body, timestamp: timestamp.to_s
    )
  end

  def valid?(timestamp:, signature:, previous_signature: nil, with: verifier)
    with.valid?(
      method: "POST", path: path, content_type: "application/json",
      body: body, timestamp: timestamp.to_s, signature: signature,
      previous_signature: previous_signature
    )
  end

  it "accepts a correctly signed, fresh callback" do
    expect(valid?(timestamp: now, signature: sign(now))).to be(true)
  end

  it "rejects a tampered body" do
    good = sign(now)
    tampered = described_class.new(secret: secret, clock: -> { now })
    result = tampered.valid?(
      method: "POST", path: path, content_type: "application/json",
      body: '{"event":"tampered"}', timestamp: now.to_s, signature: good
    )
    expect(result).to be(false)
  end

  it "rejects a wrong signature" do
    expect(valid?(timestamp: now, signature: "not-a-real-signature")).to be(false)
  end

  it "rejects a stale timestamp beyond tolerance" do
    old = now - 301
    expect(valid?(timestamp: old, signature: sign(old))).to be(false)
  end

  it "accepts a timestamp within tolerance" do
    old = now - 299
    expect(valid?(timestamp: old, signature: sign(old))).to be(true)
  end

  it "rejects a missing signature" do
    expect(valid?(timestamp: now, signature: nil)).to be(false)
  end

  describe "secret rotation (x-signature-previous)" do
    let(:old_secret) { "oLd_secret_urlsafe_base64_value_AA" }
    let(:new_secret) { "nEw_secret_urlsafe_base64_value_AA" }
    let(:old_signature) { DIDWW::OTPVerification::Signer.new(old_secret).sign(method: "POST", path: path, content_type: "application/json", body: body, timestamp: now.to_s) }
    let(:new_signature) { DIDWW::OTPVerification::Signer.new(new_secret).sign(method: "POST", path: path, content_type: "application/json", body: body, timestamp: now.to_s) }
    let(:old_verifier) { described_class.new(secret: old_secret, clock: -> { now }) }
    let(:new_verifier) { described_class.new(secret: new_secret, clock: -> { now }) }

    it "accepts the current signature with the new secret configured" do
      expect(valid?(timestamp: now, signature: new_signature, previous_signature: old_signature, with: new_verifier)).to be(true)
    end

    it "accepts the previous signature when the old secret is still configured" do
      expect(valid?(timestamp: now, signature: new_signature, previous_signature: old_signature, with: old_verifier)).to be(true)
    end

    it "rejects when neither signature matches the configured secret" do
      expect(valid?(timestamp: now, signature: new_signature, previous_signature: new_signature, with: old_verifier)).to be(false)
      expect(valid?(timestamp: now, signature: "bad", previous_signature: "also-bad", with: new_verifier)).to be(false)
    end

    it "behaves as before when the previous signature is nil or empty" do
      [nil, ""].each do |prev|
        expect(valid?(timestamp: now, signature: new_signature, previous_signature: prev, with: new_verifier)).to be(true)
        expect(valid?(timestamp: now, signature: new_signature, previous_signature: prev, with: old_verifier)).to be(false)
      end
    end

    it "still rejects a stale timestamp even when the previous signature matches" do
      stale = now - 301
      signature = DIDWW::OTPVerification::Signer.new(old_secret).sign(method: "POST", path: path, content_type: "application/json", body: body, timestamp: stale.to_s)
      expect(valid?(timestamp: stale, signature: "x", previous_signature: signature, with: old_verifier)).to be(false)
    end

    it "still requires the Authorization signature" do
      expect(valid?(timestamp: now, signature: nil, previous_signature: old_signature, with: old_verifier)).to be(false)
    end

    it "compares both signatures in constant time" do
      allow(OpenSSL).to receive(:fixed_length_secure_compare).and_call_original
      valid?(timestamp: now, signature: old_signature, previous_signature: old_signature, with: old_verifier)
      expect(OpenSSL).to have_received(:fixed_length_secure_compare).twice
    end
  end

  describe ".parse_authorization" do
    it "splits an Application key:signature header" do
      expect(described_class.parse_authorization("Application app-uuid:sig+base64=="))
        .to eq(["app-uuid", "sig+base64=="])
    end

    it "returns nils for a Basic header" do
      expect(described_class.parse_authorization("Basic abc")).to eq([nil, nil])
    end

    it "returns nils for a missing header" do
      expect(described_class.parse_authorization(nil)).to eq([nil, nil])
    end
  end
end
