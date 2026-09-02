# Changelog

Notable changes to the DIDWW OTP Verification Ruby SDK.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): from 1.0.0 onwards a breaking change
to the public surface requires a major version.

## [1.0.0] — 2026-08

First public release.

### Added

- **Every verification endpoint, addressable two ways.** `start_verification`,
  `report_verification` and `get_verification` take a verification id;
  `report_verification_by_number` and `get_verification_by_number` take a phone number in E.164
  with the leading `+` optional, for when the id was never persisted. The number is
  percent-encoded into its path segment, so a leading `+` survives a proxy that would otherwise
  decode it to a space. "Latest" means the active verification when there is one, and otherwise
  the most recent finished attempt — so an outcome that was missed can still be read.

- **All three authentication modes**, selectable per client or globally. `:basic` sends
  `Basic base64(key:secret)`. `:public` sends `Application <key>` and uses no secret, for
  applications whose callback URL authorises each start. `:application` signs every request with
  HMAC-SHA256 and adds an `x-timestamp` header; signing is automatic and is installed as the last
  Faraday middleware, so the signature always covers the exact bytes that go on the wire — after
  any middleware the caller added. A secret that is not valid URL-safe base64 fails at
  construction rather than on the first request.

- **The API's coded error envelope as typed exceptions.** A non-2xx response raises under
  `DIDWW::OTPVerification::Error`: `UnauthorizedError` (401), `BalanceInsufficientError` (402),
  `NotFoundError` (404), `ValidationError` (400/422) and `ServerError` (5xx); any other status
  — a 403 or a 429 from a proxy, say — raises the `APIError` base class rather than going
  unnoticed. Each carries `#errors`, an array of `ErrorItem`s with a stable `#code` and a fixed
  human `#detail`, plus `#code` and `#codes` shortcuts. One response can carry several errors,
  so `#codes` is the reliable one.

- **Verification outcomes as data, not exceptions.** A failed, expired or denied verification is
  a successful HTTP call: `Verification#status`, `#error_code` and `#error_detail` say what
  happened, and `#finished?` is the signal to stop polling. Statuses and codes are plain strings
  and an open set, so new ones ship without an SDK release.

- **Inbound callback signature verification.** `CallbackVerifier` checks the signature DIDWW
  sends with a `verification_request` callback, enforcing a configurable 5-minute timestamp
  window against replays and comparing in constant time. Requiring
  `didww/otp_verification/callback_verifier` on its own loads no HTTP client at all, so a
  service that only receives callbacks never pays the cost of loading Faraday. (The gem still
  declares Faraday as a runtime dependency, so it is installed either way.)

- **A Rails helper for the same.** `RailsCallbackVerifier` reads every signed field off an
  `ActionDispatch::Request`, using `raw_post` so the received bytes are what get verified. It
  lives in `didww/otp_verification/rails`, which is deliberately not auto-required — Rails is
  never a runtime dependency of this gem.

- **Per-delivery-method options, passed through verbatim.** `sms:` carries `languages` and
  `app_hash`, `callout:` carries `languages`; each travels under the key the API names the method
  by, and only the block matching `delivery_method` is read. The response block comes back the
  same way and is readable via `#sms_template`, `#sms_language`, `#sms_interception_timeout`,
  `#sms_app_hash` and `#callout_language`, or `#sms`/`#callout` for the whole thing. Naming no
  field inside a block individually means a field the API gains needs no release here, and a
  method that gains a block gains one keyword rather than a new call shape.

- **The language the server actually chose.** `#sms_language` and `#callout_language` report the
  tag the message was rendered in or the announcement is played in — the first requested tag that
  matched, otherwise the `en-US` fallback — so a fallback is detected rather than guessed at. The
  templates and the recordings are separate catalogues, so a tag honoured on `sms` can still fall
  back on `callout`.

- **Configuration with no global-only settings.** Credentials, environment, auth mode, Faraday
  adapter and a Faraday customization block can all be set globally through
  `DIDWW::OTPVerification.configure` and overridden per `Client` — which is what a multi-tenant
  host needs. `register_env` adds environments beyond the published production and sandbox.

### Notes

- Requires Ruby 3.1 or newer. Faraday is the only runtime HTTP dependency.
- The SDK does not auto-retry. If you add `faraday-retry`, exclude `POST` (it would
  double-charge) and `PATCH` (each report counts against the three-attempt limit).
