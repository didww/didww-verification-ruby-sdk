source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "webmock", "~> 3.0"
  gem "rake", "~> 13.0"
  gem "standard", "~> 1.0"
end

# Rails is a dev-only dependency, used solely by the spec-rails/ integration
# suite. It is never a runtime dependency of the gem (see gemspec).
group :test do
  # Rails 8.1 ships Ruby 3.4-only syntax (actionview's capture_helper forwards
  # anonymous rest args inside a block) despite declaring required_ruby_version
  # >= 3.2, so it cannot load on the 3.3 leg. 8.0 covers the floor — pinned to
  # 8.0.x, since "~> 8.0" would resolve to 8.1 again — and 8.1 covers the rest.
  gem "rails", (RUBY_VERSION >= "3.4") ? "~> 8.1" : "~> 8.0.0"
  gem "rack-test", "~> 2.1"
end
