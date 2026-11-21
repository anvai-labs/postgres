# perf-lakehouse harness (spec 10 §5)

Drivers for the performance gates and the §5.1/§5.2 recorded comparisons.

## What runs where

| Piece | Engine | Role |
|---|---|---|
| `lakehouse_perf.py` | psycopg2 (plain pgwire) | attach foreign tables, warmup + 3 measured runs, median, markdown output — talks ONLY to pgdatalake SQL |
| fixture generation | pyiceberg inside the fixture docker network | bulk data writing; rides the container network because the `smoke` warehouse's storage profile carries the docker-internal `s3:9000` |

**Why pyiceberg still generates the data:** the managed/FDW write path is
row-transport-bound (write staging measured 2.3M rows/s, but bulk-load
throughput is the M4 gate — §5's ≥50 MB/s/backend). When that gate
lands, the generator flips to pgdatalake INSERTs; the driver above
never changes (it only ever speaks SQL to the server under test).

## TPC-DS suite (the §5.1/§5.2 comparison set)

Same fixture as the M1 gate: TPC-DS SF=10 (28.8M-row store_sales, 73
bin-packed files) as Iceberg tables on the fixture stack. q1/q2/q3 are
the recorded comparison set; q3 is the row-transport canary that perf
fix #1 (columnar batch reads) targeted.

```bash
# 1. a RELEASE build (debug-optimized timings are not comparable):
CC=/usr/bin/gcc meson setup build-release -Ddatalake=enabled -Dbuildtype=release
ninja -C build-release && meson install -C build-release --destdir build-release/tmp_install

# 2. a fresh server on a free port (initdb once, then start):
build-release/tmp_install/usr/local/pgsql/bin/initdb -D /tmp/vg-perf -U postgres
# postgresql.conf: shared_preload_libraries='lakehouse', port=52021
build-release/tmp_install/usr/local/pgsql/bin/pg_ctl -D /tmp/vg-perf start

# 3. measure (warmup + 3 runs, median):
python3 scripts/perf/lakehouse_perf.py --suite tpcds \
    --dsn postgres://postgres@localhost:52021/postgres
```

`tpcds/ddl.sql` attaches the 22 fixture tables with CURRENT option
placement — endpoint + s3_endpoint on the SERVER, credentials ONLY on
the user mapping (RULES §6). `tpcds/queries/` holds q1–q10 verbatim.

## Scan microbench (fast, no full TPC-DS fixture needed)

```bash
python3 scripts/perf/lakehouse_perf.py --suite scan \
    --dsn postgres://postgres@localhost:52021/postgres
```

An existing fixture that VERIFIES (exact row count + `sum(id)`
checksum — the ids are deterministic 0..N-1) is reused with a NOTICE;
a mismatching one is regenerated with a WARNING; `--force-regen`
overrides reuse. The TPC-DS suite verifies the 28,800,991-row
store_sales sanity count the same way.

## Gate rule (§5)

Regressions > 10% on two consecutive runs block merge. Wall-clock is
runner-noisy; the deterministic P0b metrics (bytes fetched, GET counts,
cold/warm ratio via the `fetched_bytes` cache counter) are the primary
regression signal for read-path changes.
