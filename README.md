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

1. Individual mode: keep `active_profile: null`, omit `provider_profiles`, and enable the required direct strategies.
2. Profile mode: disable every direct strategy, set `active_profile` as the default, and optionally assign profiles through
   `provider_profiles.<payment_system>`.

Each profile contains its own strategy combination and weights. Strategies listed inside a profile are enabled automatically.
The application rejects unknown profiles and any attempt to mix profiles with directly enabled strategies. The supplied policy
uses history-calibrated provider profiles: `reliable_history` for `vipay`, `controlled_share` for `payflow`, and
`capacity_obligation` for `quickpay`. The `historical_only` profile demonstrates the single-strategy mode.

`historical_quality` reads a per-provider truncated attempt window, not the raw CSV as a whole. The mix is configured under
`metrics:` in `config/routing_policy.yml` and may be overlaid per profile. Components are **availability** (`1 - timeout_rate`),
**acceptance** (approvals among answered attempts), **approval_rate**, and **latency**. They are not extra strategies: stuffing
timeouts and refusals into one “uptime” percentage would collapse into conversion.

After the weighted strategy total, Ranker multiplies by **health** — a floored blend of availability and acceptance. Health
never excludes a provider; it only scales the score. `conversion` still uses `conversion_24h` from `providers.json` (a slow
published KPI). Windows are the fast local evidence, seeded from the most recent compatible CSV rows and updated on every
attempt, including cascade refusals. A later status-check rewrites an `expired` row instead of appending a second one.

`historical_quality` still prefers a sufficiently large provider + bank + amount segment, then falls back through bank, amount,
and provider-level samples. Small segments shrink toward the provider baseline; `conversion_24h` is the live prior when the
window is empty. Only rows older than the current operation and compatible with current bank/amount rules are eligible.

`Routing::Router` always applies every hard constraint before ranking. The eligible fallback is kept outside soft-goal
ranking and is selected only when no untried external provider remains.

### Online state and fallback

`Routing::Engine#route_one` processes one operation at a time and rejects duplicate IDs or timestamps older than the last
processed operation. The JSON queue is only a chronological replay adapter; future operations are never used for scoring or
capacity reservation.

Before every routing attempt, `Routing::RuntimeState` creates a point-in-time snapshot with a revision. The selected provider is
reserved atomically against that revision and the unchanged hard constraints are checked again inside the reservation boundary.
Pending count, volume, daily capacity, and in-progress load are visible to subsequent snapshots.

- `approved`: convert the pending reservation into committed traffic and approved turnover;
- `rejected`: roll back provisional counters and reroute through the next eligible provider on a fresh snapshot;
- `expired`: keep the reservation, treat the provider as the current final selection, and do not start fallback before a
  status-check;
- late cancellation: call `RuntimeState#resolve_timeout!` to compensate current counters without replaying earlier decisions.

`Routing::StatusChecker` registers every timed-out reservation and runs checks that are due before the next online operation is
routed. `approved` commits the reservation, `rejected`/`cancelled` releases it, and `pending`/`processing`/another timeout is
retried with the delays from `status_check.retry_delays_sec`. Provider and transport errors follow the same retry path. Once
`max_attempts` is reached, the task moves to `manual_review`; its reservation remains held because an unknown result must never
trigger an unsafe fallback. Status-check tasks are deduplicated by the same idempotency key as the original payout request.

The supplied simulator implements both `call` and `status`. A real provider adapter must expose the same two methods. Current
status-check tasks are kept in the process runtime; durable storage is still required before using this implementation across
process restarts.

Every provider attempt receives a stable `<operation_id>:<provider>` idempotency key when the provider client accepts keyword
context. Decision details include the selected provider profile, total score, weighted soft-goal contributions, and
goal disagreements. Eligible providers that lost the comparison are recorded as `lower_soft_score` skips.

Historical rows are not mixed into the test queue traffic denominator. They are included separately in
`routing_report_test.json` as `history_baseline`. Live windows appear as `provider_metrics` (availability, acceptance, health,
timeouts, refusals). Recommendations that cite availability name a concrete YAML knob such as
`profiles.<name>.metrics.multipliers.health.exponent`. The report also contains `status_checks`; a timeout resolved before the
report is built uses its terminal reservation status in the final traffic distribution.

### Layout

```
bin/                 # setup, console, route
config/              # routing_policy.yml (strategy weights, metrics, profiles)
data/                # public fixtures (providers, queue, history, samples)
lib/routing/         # application code (Zeitwerk)
scripts/             # organizer validate_10.rb (acceptance)
spec/                # RSpec
```
