# Tester Environment Deployment

Baseline: upstream Plausible Analytics `v3.2.1` at `e4f5a87a5570bd61605217e7ceb376636db8eddb`.

## Commands

```bash
./tester-env deploy
./tester-env seed
./tester-env verify
./tester-env reset
```

`deploy` builds the editable source with the root `Dockerfile` (`MIX_ENV=ce`), starts PostgreSQL 16 and ClickHouse 24.3, creates/migrates both databases, creates `admin@plausible.test` with password `PlausibleTesterEnv123!`, and serves `http://localhost:8032/` by default.

`reset` runs project-scoped `docker compose down -v`, removing only this tester environment's containers and volumes; it does not remove images or shared browser infrastructure. `seed` creates fixed `northstar-market.test` data: 12 sessions, 12 pageviews, 3 Newsletter Signup events, goals Completed checkout and Newsletter signup, and sources Google 5, Direct 4, GitHub 3. Events are fixed from 2026-08-12 10:00 through 2026-08-13 21:00 UTC. `seed` also ensures `editor@plausible.test` (`PlausibleTesterEnv123!`) as team `:editor` on the site team and one passwordless shared link `Tester Env Shared Link` (slug `testerenvsharedlink01`); both are idempotent on reseed. `verify` asserts this state.

`IMAGE_TAG` selects the image name; `RUN_ID` scopes only the Compose project. The compose stack uses host networking because Docker address pools are exhausted, so PostgreSQL 5432 and ClickHouse 8123 prevent concurrent runs. Set `PORT` and `BASE_URL` together if port 8032 is occupied.

## Recorded Browser Smoke

On 2026-09-07, browser-checker logged in as Tester Env Admin at `http://host.docker.internal:8032/`, selected `northstar-market.test`, set the visible range to 12 Aug - 13 Aug, and observed 12 unique visitors, 12 visits, 12 pageviews, Google 5, Direct 4, GitHub 3, and both goals. Applying and clearing Source = Google (5 visitors) and Goal = Newsletter signup (3 conversions) restored the unfiltered 12-metric dashboard.
