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
  gem "rails", "~> 7.1"
  gem "rack-test", "~> 2.1"
end
