RSpec.describe DIDWW::OTPVerification::Signer do
  # Pinned to the API's own signing test vectors: a wire-compatibility break
  # fails here rather than in production.
  let(:secret) { "tEsT_secret_urlsafe_base64_value_AA" }

  subject(:signer) { described_class.new(secret) }

  it "matches the server vector for a signed POST with a body" do
    signature = signer.sign(
      method: "POST",
      path: "/verifications",
      content_type: "application/json",
      body: '{"key":"value"}',
      timestamp: "1700000000"
    )
    expect(signature).to eq("k7TRVTzybQtVKYdpgKNd2QxH5n2LvQselVWSMOlYPo8=")
  end

  it "matches the server vector for a bodyless GET" do
    signature = signer.sign(
      method: "GET",
      path: "/verifications",
      content_type: "",
      body: "",
      timestamp: "1700000000"
    )
    expect(signature).to eq("kCJ2eLWCrmKMhEsBFRL1A8HcmBTozeljcfOy5i+kVZU=")
  end

  it "upcases the HTTP method" do
    lower = signer.sign(method: "post", path: "/x", content_type: "", body: "", timestamp: "1")
    upper = signer.sign(method: "POST", path: "/x", content_type: "", body: "", timestamp: "1")
    expect(lower).to eq(upper)
  end

  it "is sensitive to a trailing space in the body" do
    a = signer.sign(method: "POST", path: "/x", content_type: "application/json", body: '{"a":1}', timestamp: "1")
    b = signer.sign(method: "POST", path: "/x", content_type: "application/json", body: '{"a":1} ', timestamp: "1")
    expect(a).not_to eq(b)
  end

  describe "#string_to_sign" do
    it "joins the five canonical lines with newlines" do
      sts = signer.string_to_sign(
        method: "POST", path: "/verifications",
        content_type: "application/json", body: '{"key":"value"}', timestamp: "1700000000"
      )
      md5 = Base64.strict_encode64(Digest::MD5.digest('{"key":"value"}'))
      expect(sts).to eq(
        ["POST", md5, "application/json", "x-timestamp:1700000000", "/verifications"].join("\n")
      )
    end

    it "leaves CONTENT-MD5 empty when there is no body" do
      sts = signer.string_to_sign(method: "GET", path: "/x", content_type: "", body: "", timestamp: "1")
      expect(sts).to eq(["GET", "", "", "x-timestamp:1", "/x"].join("\n"))
    end
  end

  it "raises when the secret is blank" do
    expect { described_class.new("") }.to raise_error(DIDWW::OTPVerification::ConfigurationError)
  end
end
