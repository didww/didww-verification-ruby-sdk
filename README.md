# DIDWW OTP Verification Ruby SDK

Ruby client for the [DIDWW OTP Verification API](https://verification.didww.com)
(`/api/v1`). Wraps all verification endpoints (address a verification by id or
by phone number), all three auth modes, and inbound callback signature
verification.

📖 [API documentation](https://doc.didww.com/otp-verification/index.html)

## Installation

```ruby
gem "didww-otp_verification"
```

## Quick start

```ruby
require "didww/otp_verification"

client = DIDWW::OTPVerification::Client.new(
  key:    "your-app-key",
  secret: "your-app-secret"
)

verification = client.start_verification(
  destination:     "+4915112345678",
  delivery_method: "sms",                 # "sms" | "callout"
  sms:             {languages: ["en-US"]} # optional, see below
)
verification.id       # => "0f9c8b7a-..."
verification.status   # => "pending"
verification.pending? # => true
verification.to_h     # => raw response data Hash with string keys

# Report the code the user entered (counts as an attempt; max 3, expires in 2 min)
result = client.report_verification(
  verification.id, delivery_method: "sms", code: "1234"
)
result.verified? # => true/false

# Poll status
client.get_verification(verification.id)
```

Both delivery methods are reported the same way: `code:` carries what the user
entered, whether they read it off a message or heard it in a call.

### Per-method options

Options that apply to one delivery method only go in a keyword named after that
method and travel verbatim, so the call above goes on the wire as:

```json
{ "data": { "destination": "+4915112345678", "delivery_method": "sms",
            "sms": { "languages": ["en-US"] } } }
```

`sms:` and `callout:` are the keywords today, one per delivery method. The API
reads only the block matching `delivery_method` and ignores the others.

#### `sms:`

| Field       | Description                                                                                                                                                                   |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `languages` | Preferred template languages as BCP 47 tags, most preferred first. Matched exactly, so the region subtag is required — `"pl"` does not match `pl-PL`. Unmatched tags fall back to `en-US`. |
| `app_hash`  | Android SMS Retriever hash: exactly 11 characters of `[A-Za-z0-9+/]`. The delivered message is then prefixed with `<#> ` and the hash appended as its last token, so the handset can auto-fill the code. Omit it on every other platform. |

`app_hash` is here because a Ruby backend often starts the verification on behalf
of an Android app — the hash identifies that app, so only the app can compute it.

```ruby
client.start_verification(
  destination: "+4915112345678", delivery_method: "sms",
  sms: {languages: ["en-US"], app_hash: "A1b2C3d4E5f"}
)
```

#### `callout:`

| Field       | Description                                                                                                                                                                   |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `languages` | Preferred announcement languages — the same tags, order and matching rules as the `sms:` ones, so the same list is valid for either method. It is not shared between them, though: each method reads only its own block, so the list goes under `callout:` here and under `sms:` there. The catalogues are separate too, so a tag that has a message template but no recording is accepted and falls back to `en-US`. |

```ruby
client.start_verification(
  destination: "+4915112345678", delivery_method: "callout",
  callout: {languages: ["de-DE", "en-US"]}
)
```

The SDK names no field inside a block individually — the block travels verbatim,
so a field the API adds to either one needs no release here and works the day the
API ships it. The cost of that is no typo protection: an unrecognized option is
ignored rather than rejected, and a misspelled key returns `201` with the
defaults applied, not an error.

### Reading a method block back

The response carries the block for the method that was used, readable field by
field or as a whole:

```ruby
v.sms_template             # => "Your code is {{CODE}}"
v.sms_language             # => "en-US"
v.sms_interception_timeout # => 120
v.sms_app_hash             # => "A1b2C3d4E5f", or nil if none was stored
v.sms                      # => the raw block, or nil on a callout verification

v.callout_language         # => "de-DE"
v.callout                  # => the raw block, or nil on an sms verification
```

`sms_language` and `callout_language` are the tag the **server** chose — the
first requested language it had a template (or a recording) for, otherwise the
`en-US` fallback — never an echo of what was asked for. Comparing one against the
list that was sent is how a fallback is detected rather than guessed at, and
because the two catalogues are separate, a tag honoured on `sms` can still fall
back on `callout`.

`sms_interception_timeout` is how many seconds a client should keep an on-device
SMS listener armed. It is a fixed budget, not a countdown, and **not** a deadline
for the verification — manual entry keeps working until `expires_at`.
`sms_app_hash` is echoed back only when one was stored, so it reflects what was
persisted rather than what was requested.

### Address by phone number

Every report/fetch call has a `_by_number` variant that targets the latest
verification for a phone number (E.164, leading `+` optional) instead of an id:

```ruby
client.get_verification_by_number("+4915112345678")
client.report_verification_by_number(
  "+4915112345678", delivery_method: "sms", code: "1234"
)
```

Numbers are matched on their digits, so any formatting works. "Latest" is the
active verification when there is one, otherwise the most recent finished
attempt — so you can still read an outcome you missed. A `404` means the number
has no verification at all.

## Sandbox environment

The SDK targets production by default. To hit the sandbox, pass `env: :sandbox`:

```ruby
client = DIDWW::OTPVerification::Client.new(
  key:    "your-app-key",
  secret: "your-app-secret",
  env:    :sandbox
)
```

Or set it as a global default:

```ruby
DIDWW::OTPVerification.configure do |c|
  c.env = :sandbox
end
```

## Configuration

Set global defaults; every field is overridable per `Client`.

```ruby
DIDWW::OTPVerification.configure do |c|
  c.key       = ENV["DIDWW_OTP_KEY"]
  c.secret    = ENV["DIDWW_OTP_SECRET"]
  c.auth_mode = :basic                      # :basic (default) | :public | :application

  # Register extra environments (a local dev server, a private mock, ...)
  c.register_env(:local, "http://localhost:3000")

  # Customize every Faraday connection (proxy, logging, timeouts, adapter)
  c.faraday do |conn|
    conn.options.timeout = 10
    conn.response :logger
  end
end

DIDWW::OTPVerification::Client.new  # picks up the globals
```

### Per-request credentials / config

Nothing is global-only. Pass anything straight to `Client.new` — ideal for
multi-tenant apps:

```ruby
DIDWW::OTPVerification::Client.new(
  key: tenant.key, secret: tenant.secret,
  base_url: "https://custom.host",          # wins over env
  adapter: :typhoeus                         # any Faraday adapter
) { |conn| conn.proxy = "http://proxy:3128" }
```

## Auth modes

| Mode               | Header                                          | Secret   | Notes                              |
| ------------------ | ----------------------------------------------- | -------- | ---------------------------------- |
| `:basic` (default) | `Basic base64(key:secret)`                      | required | Documented, simplest               |
| `:public`          | `Application <key>`                             | not used | Requires a callback URL on the app |
| `:application`     | `Application <key>:<signature>` + `x-timestamp` | required | HMAC-SHA256 signed                 |

Set the mode per `Client` via `auth_mode:`, or globally via
`c.auth_mode` in `configure`.

### `:basic` (default)

Sends `Basic base64(key:secret)`. Requires both `key` and `secret`.

```ruby
client = DIDWW::OTPVerification::Client.new(
  key:    "your-app-key",
  secret: "your-app-secret",
  auth_mode: :basic          # optional — this is the default
)
```

### `:public`

Sends `Application <key>`. No secret is used; the app must have a callback URL
configured so DIDWW can deliver results.

```ruby
client = DIDWW::OTPVerification::Client.new(
  key:       "your-app-key",
  auth_mode: :public
)
```

### `:application`

Sends `Application <key>:<signature>` plus an `x-timestamp` header. The `secret`
is the URL-safe base64 signing key and is required. Signing is applied
automatically; the signature is computed over the exact request bytes.

```ruby
client = DIDWW::OTPVerification::Client.new(
  key:       "your-app-key",
  secret:    "your-app-secret",
  auth_mode: :application
)
```

## Verifying inbound callbacks

DIDWW sends signed `verification_request` callbacks to your server using the
same HMAC scheme. The verifier has no HTTP-client dependency. The callback
request payload is documented at
[Request from DIDWW](https://doc.didww.com/otp-verification/callbacks.html#request-from-didww).

```ruby
verifier = DIDWW::OTPVerification::CallbackVerifier.new(secret: app_secret)

key, signature = DIDWW::OTPVerification::CallbackVerifier
                 .parse_authorization(request.headers["Authorization"])

ok = verifier.valid?(
  method:       request.request_method,   # "POST"
  path:         request.path,             # your callback URL's path
  content_type: request.content_type,
  body:         request.raw_post,         # RAW body bytes — do not re-serialize
  timestamp:    request.headers["x-timestamp"],
  signature:    signature
)

render json: { action: ok ? "allow" : "deny" }
```

The verifier also enforces a 5-minute timestamp window (configurable via
`tolerance:`) to reject replays.

### Rails

`RailsCallbackVerifier` pulls every signed field off an `ActionDispatch`
request for you. It lives in a separate file that is **not** auto-required —
Rails is an optional runtime dependency — so require it explicitly:

```ruby
require "didww/otp_verification/rails"
```

Controller:

```ruby
class DidwwCallbacksController < ActionController::API
  before_action :verify_didww_signature

  # Signature is already verified here — decide allow/deny from your own
  # logic and the callback params.
  def create
    # some custom logic to decide whether to allow or deny the verification request
    allow = expected_destination? params.dig(:data, :destination)

    render json: { action: allow ? "allow" : "deny" }
  end

  private

  def verify_didww_signature
    verifier = DIDWW::OTPVerification::RailsCallbackVerifier.new(
      secret: ENV["DIDWW_OTP_SECRET"]
    )
    head(:unauthorized) unless verifier.valid?(request)
  end
end
```

Routes (`config/routes.rb`) — the path must match the callback URL registered
on your app, since it is part of the signed payload:

```ruby
post "/callbacks/didww", to: "didww_callbacks#create"
```

## Verification outcomes

Every 2xx response carries the verification's `status`. One that ended badly also
carries `error_code` (switch on it) and `error_detail` (display it). These are
**not** exceptions — a failed or denied verification is a successful HTTP call.

| `status`   | Terminal | `error_code`                                                                                 |
| ---------- | -------- | -------------------------------------------------------------------------------------------- |
| `pending`  | no       | `nil` — on its way, or awaiting a report                                                       |
| `verified` | yes      | `nil`                                                                                          |
| `failed`   | yes      | `too_many_attempts`, `dispatch_failed`, `stale_dispatch`, `superseded`, `application_deleted`   |
| `expired`  | yes      | `expired` — past the 2-minute window                                                           |
| `denied`   | yes      | `denied_by_callback`, `denied_missing_callback_url`, `denied_invalid_callback_response`         |

`superseded` means a newer `start_verification` for the same number retired this
one — only the newest verification per number stays active.

```ruby
v = client.get_verification(id)

if v.finished?  # verified / failed / expired / denied — stop polling
  case v.error_code
  when nil                 then grant_access
  when "too_many_attempts" then lock_out
  when "expired"           then offer_resend
  else logger.warn("verification #{v.id}: #{v.error_detail}")
  end
end
```

Statuses and codes are plain strings and an open set — new ones ship without an
SDK release, so always keep a default branch and treat the
[API documentation](https://doc.didww.com/otp-verification/index.html) as the
authoritative list.

## Errors

Non-2xx responses raise a typed error under `DIDWW::OTPVerification::Error`:

| Class                      | Status    | Typical code                          |
| -------------------------- | --------- | ------------------------------------- |
| `UnauthorizedError`        | 401       | `unauthorized`                        |
| `BalanceInsufficientError` | 402       | `balance_insufficient`                |
| `NotFoundError`            | 404       | `not_found`                           |
| `ValidationError`          | 400 / 422 | `parameter_missing` / per-field codes |
| `ServerError`              | 5xx       | `internal_error`                      |

Every error carries the API's coded envelope: `#errors` is an array of
`ErrorItem`s (`#code`, `#detail`), and `#code`/`#codes` are shortcuts to the
stable, machine-readable slugs. Switch on `code`; the human `detail` is fixed per
code and only for display. One response can carry several errors — check `#codes`
rather than `#code`, which only returns the first.

Every status the API produces carries this envelope. `#errors` is empty only when
a response has no JSON body at all — e.g. a 502 from a proxy in front of it.

```ruby
begin
  client.start_verification(destination: "", delivery_method: "sms")
rescue DIDWW::OTPVerification::ValidationError => e
  e.status            # => 422
  e.code              # => "destination_blank"
  e.codes             # => ["destination_blank"]
  e.errors.first.code # => "destination_blank"
  e.message           # => every error's detail, joined by ", "
end
```

## Retries

The SDK does **not** auto-retry. If you add `faraday-retry`, exclude `POST`
(double-charges) and `PATCH` (each report counts against the 3-attempt limit).

## Development

Development is pinned to the Ruby in `.ruby-version`; the gem itself supports
3.1+.

```sh
bundle install
bundle exec rake spec         # core gem specs (no Rails)
bundle exec rake spec:rails   # Rails integration suite (spec-rails/)
```

The signing implementation is pinned to the server's own test vectors in
`spec/didww/otp_verification/signer_spec.rb`.

Rails is a **dev-only** dependency: it is exercised solely by the `spec-rails/`
suite and is never a runtime dependency of the gem. The core specs under
`spec/` never load Rails.
