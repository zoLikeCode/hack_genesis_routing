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

The route command also writes `routing_runtime_state.json` by default. Use `--runtime PATH` to change its location.

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
`capacity_obligation` for `quickpay`. `only_*` profiles demonstrate every strategy independently.

A **metric** is an observable from the session, provider catalog, bounded attempt window, runtime state, or current operation.
A **strategy** turns those inputs into a score in `[0, 1]`. A **profile** is a normalized weighted combination:
`total = Σ normalized_weight × strategy_score`. There are no additional health multipliers.

To add a metric that should affect selection: register it in `Routing::Metrics::Inputs`, produce the value, then list
it on an existing `SoftGoals::*::METRICS` (or add a strategy class to `GOALS` and a YAML weight).

`conversion` is the only quality strategy. It estimates the probability of receiving `approved` on the initial provider call:
`p = (approved + prior_strength × conversion_24h) / (n + prior_strength)`, where timeout counts in `n` as initial failure.
The last 24 hours are filtered before the newest 50 compatible attempts are selected. A segment needs at least 10 rows and is
selected in this order: bank + amount band, bank, amount band, provider. A segment is shrunk to the estimate calculated from
the rest of the provider history, so it is not included in its own baseline.

Each observation keeps immutable `initial_status` and `latency_sec`; `status` is the current/final result. A status-check changes
only final status. Therefore a late approval improves final analytics but never erases the original timeout or retroactively
improves the conversion forecast. Initial conversion, timeouts, refusals, answered success and p90 initial response latency are
reported separately from final approvals, rejections and unresolved attempts.

Count and volume share strategies compare the whole target distribution after a hypothetical reservation. Their score is
`1 - 0.5 * sum((actual_share - target_share)^2)` and therefore stays in `[0, 1]`.
Targets must total 100%; unavailable providers retain their targets and fallback has target zero. `load_balance` includes the
candidate in in-progress count/amount, RPM and daily-volume utilization. Amount preferences are explicit inclusive bands under
`amount_bands:` rather than `amount / limit_amount_max`.

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
- late cancellation: atomically release the reservation and reroute that operation on a fresh snapshot without replaying
  decisions already made for other operations.

`Routing::StatusChecker` registers every timed-out reservation. `Routing::StatusCheckRunner` executes checks due before the next
online operation and drains the remaining schedule after a finite queue has been routed, advancing logical test time instead of
sleeping. This means a timeout on the final queue item is still resolved. `approved` commits the reservation,
`rejected`/`cancelled` atomically releases it, and `pending`/`processing`/another timeout is retried with the delays from
`status_check.retry_delays_sec`. Provider and transport errors follow the same retry path. Once the finite `max_attempts`
budget is reached, the task moves to `reconciliation_pending` and active polling stops. Its reservation remains held because
an unknown result must never trigger an unsafe fallback.
Status-check tasks are deduplicated by the same idempotency key as the original payout request. A terminal response that
conflicts with an already-settled reservation also moves to `reconciliation_pending` without rewriting the first terminal
result.
Long-lived hosts can start `engine.status_check_runner`; scheduling a timeout wakes that single runner, which waits for the
nearest `next_check_at` and therefore does not depend on another operation arriving. The finite JSON replay uses `drain`
instead, so configured delays advance logical time and never make the CLI sleep.

When unresolved count or amount reaches the configured circuit-breaker threshold, the provider is excluded from new routes
with the explicit `circuit_breaker_open` reason. The existing hard-constraint implementation remains unchanged.

The supplied simulator implements both `call` and `status`. A real provider adapter must expose the same two methods. The CLI
rewrites `routing_runtime_state.json` through a temporary file after reservation and status transitions. It contains provider
counters, reservations, metrics, status-check tasks, and circuit-breaker state. Automatic restoration after process restart is
not attempted because the case has no real provider recovery API; the JSON is a durable reconciliation and audit snapshot.

Every provider attempt receives a stable `<operation_id>:<provider>` idempotency key when the provider client accepts keyword
context. Decision details include the selected profile, conversion source/scope/sample size/prior, normalized strategy weights,
contributions, before/after share errors, and total score. Eligible providers that lose are `lower_soft_score` skips.

Historical rows are not mixed into the test queue traffic denominator. They are included separately in
`routing_report_test.json` as `history_baseline`. `provider_metrics` separates initial and final outcomes, and
`conversion_backtest` contains a sequential Brier comparison with the fixed published prior. This evaluates forecasts on
observed attempts; it is not evidence about unobserved provider outcomes or causal routing improvement. The report also contains
`status_checks`; a timeout resolved before report generation uses its terminal reservation status in final traffic distribution.

### Layout

```
bin/                 # setup, console, route
config/              # routing_policy.yml (strategy weights, metrics, profiles)
data/                # public fixtures (providers, queue, history, samples)
lib/routing/         # application code (Zeitwerk)
scripts/             # organizer validate_10.rb (acceptance)
spec/                # RSpec
```
