## MISIS Solution / HackGenesis

Smart payout routing between payment providers.

### Setup

```bash
ruby bin/setup
```

Or `bundle install` in this directory. Ruby 4.0+ is required (see `.ruby-version`).

### Commands

```bash
bundle exec rake          # RSpec + RuboCop
bundle exec rspec
bundle exec rubocop
bundle exec rubocop -A    # lint + auto-format
bundle exec rake validate # public-queue acceptance check
ruby bin/route --help
ruby bin/console
```

Validate your own output:

```bash
bundle exec rake validate[routing_decisions_test.json]
# PowerShell: bundle exec rake "validate[routing_decisions_test.json]"
# or
ruby scripts/validate_10.rb path/to/routing_decisions.json
```

Enable YJIT in the CLI via `RUBY_YJIT_ENABLE=1` (already defaulted in `bin/route`).

### Strategy selection

`config/routing_policy.yml` supports two mutually exclusive modes:

1. Individual mode: keep `active_profile: null` and set `strategies.<name>.enabled: true` for each required strategy.
2. Profile mode: set every individual `enabled` flag to `false` and set `active_profile` to a name from `profiles`.

Each profile contains its own strategy combination and weights. Strategies listed inside a profile are enabled automatically.
The application rejects an unknown profile and rejects a selected profile when at least one individual strategy is enabled.

### Layout

```
bin/                 # setup, console, route
config/              # routing_policy.yml (strategy weights)
data/                # public fixtures (providers, queue, history, samples)
lib/routing/         # application code (Zeitwerk)
scripts/             # organizer validate_10.rb (acceptance)
spec/                # RSpec
```
