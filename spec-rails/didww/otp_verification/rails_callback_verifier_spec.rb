require "rails_helper"

RSpec.describe DIDWW::OTPVerification::RailsCallbackVerifier do
  include Rack::Test::Methods

  def app
    Rails.application
  end

  let(:signer) { DIDWW::OTPVerification::Signer.new(CALLBACK_SECRET) }
  let(:key) { "app-key" }
  let(:path) { "/callbacks/didww" }
  let(:body) { '{"data":{"destination":"+4915112345678"}}' }

  def sign(timestamp, signed_body = body)
    signer.sign(
      method: "POST", path: path, content_type: "application/json",
      body: signed_body, timestamp: timestamp.to_s
    )
  end

  # Issues the callback POST the way DIDWW would: raw JSON body plus the signed
  # Authorization / x-timestamp headers.
  def post_callback(signature:, timestamp:, request_body: body)
    post path, request_body, {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Application #{key}:#{signature}",
      "HTTP_X_TIMESTAMP" => timestamp.to_s
    }
  end

  it "passes the before_action and returns allow for a valid, matching callback" do
    ts = Time.now.to_i
    post_callback(signature: sign(ts), timestamp: ts)

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq("action" => "allow")
  end

  it "passes the before_action but returns deny when params don't match" do
    other = '{"data":{"destination":"+100000000000"}}'
    ts = Time.now.to_i
    post_callback(signature: sign(ts, other), timestamp: ts, request_body: other)

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq("action" => "deny")
  end

  it "responds 401 when the signature is wrong" do
    ts = Time.now.to_i
    post_callback(signature: "not-a-real-signature", timestamp: ts)

    expect(last_response.status).to eq(401)
  end

  it "responds 401 when the body was tampered with after signing" do
    ts = Time.now.to_i
    good = sign(ts)
    post_callback(signature: good, timestamp: ts, request_body: '{"data":{"destination":"+999"}}')

    expect(last_response.status).to eq(401)
  end

  it "responds 401 when the timestamp is stale beyond tolerance" do
    stale = Time.now.to_i - 301
    post_callback(signature: sign(stale), timestamp: stale)

    expect(last_response.status).to eq(401)
  end

  it "responds 401 when the Authorization header is missing" do
    post path, body, {"CONTENT_TYPE" => "application/json", "HTTP_X_TIMESTAMP" => Time.now.to_i.to_s}

    expect(last_response.status).to eq(401)
  end
end
