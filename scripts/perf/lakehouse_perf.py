#!/usr/bin/env python3
"""lakehouse_perf.py — perf-lakehouse harness driver (spec 10 §5).

Talks to a RUNNING pgdatalake server over plain pgwire (psycopg2 — the
server is stock Postgres wire protocol; no third-party engine involved).
The fixture data itself is generated out-of-band (pyiceberg via the
docker fixture network — see scripts/perf/README), because the managed
write path is not yet at the M4 bulk-load gate; when it is, the
generator flips to pgdatalake INSERTs and this driver does not change.

Protocol (matches the M1 gate + §5.1/§5.2 records): per query — 1
warmup run (fills the BlockCache: cold timing measures fetch+compute,
warm timing is cache-served), then 3 measured runs, median reported.
Runs against a RELEASE build; wall-clock on a debug build is not
comparable to any recorded number.

Suites:
  tpcds  TPC-DS q1–q3 full-scale (SF=10 fixture, 28.8M-row store_sales):
         the §5.1/§5.2 comparison set — q3 is the row-transport canary
         that perf fix #1 (columnar batch reads, #5/#17) targeted.
  scan   single-file projection/aggregate microbench (small, fast).

Usage:
  python3 scripts/perf/lakehouse_perf.py --suite tpcds \
      --dsn postgres://postgres@localhost:52021/postgres
"""
import argparse
import statistics
import sys
import time
from pathlib import Path

import psycopg2

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DDL = REPO / "scripts" / "perf" / "tpcds" / "ddl.sql"
DEFAULT_QUERIES = REPO / "scripts" / "perf" / "tpcds" / "queries"

# q1/q2/q3 = the recorded §5.1 comparison set
TPCDS_QUERIES = ["query1", "query2", "query3"]

SCAN_DDL = """
DROP TABLE IF EXISTS perf_scan CASCADE;
CREATE FOREIGN DATA WRAPPER IF NOT EXISTS perf_scan_wrapper
    HANDLER lakehouse.lakehouse_fdw_handler;
DO $$ BEGIN CREATE SERVER perf_scan_srv FOREIGN DATA WRAPPER perf_scan_wrapper
    OPTIONS (endpoint %s, warehouse 'smoke', s3_endpoint %s);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER perf_scan_srv
    OPTIONS (s3_access_key %s, s3_secret_key %s);
CREATE FOREIGN TABLE perf_scan (
    id bigint, name text
) SERVER perf_scan_srv OPTIONS (table %s);
"""

SCAN_SETUP_PY = """
TABLE = "perfcn.scan_bench_n%d"
import random
import pyarrow as pa
from pyiceberg.catalog import load_catalog
from pyiceberg.exceptions import NoSuchTableError
from pyiceberg.schema import Schema
from pyiceberg.types import LongType, NestedField, StringType

random.seed(7)
cat = load_catalog("smoke", type="rest", uri=%r, warehouse="smoke",
                   **{"s3.endpoint": %r,
                      "s3.access-key-id": "lakehouse-test",
                      "s3.secret-access-key": "lakehouse-test-password"})
try:
    cat.create_namespace("perfcn")
except Exception:
    pass
try:
    cat.drop_table(TABLE)
except NoSuchTableError:
    pass
schema = Schema(NestedField(1, "id", LongType(), required=False),
                NestedField(2, "name", StringType(), required=False))
t = cat.create_table(TABLE, schema=schema,
                     properties={"format-version": "2"})
N = %d
CHUNK = 200_000
for base in range(0, N, CHUNK):
    k = min(CHUNK, N - base)
    t.append(pa.table({
        "id": pa.array([base + i for i in range(k)], pa.int64()),
        "name": pa.array([f"row-{base + i}-" + "y" * 40 for i in range(k)],
                         pa.string()),
    }))
print(f"generated {TABLE} rows={N} files={len(list(t.scan().plan_files()))}")
"""


def connect(dsn: str, autocommit: bool = True):
    conn = psycopg2.connect(dsn)
    conn.autocommit = True
    return conn


def timed(cur, sql: str, timeout_s: int) -> float:
    cur.execute(f"SET statement_timeout = {timeout_s * 1000}")
    t0 = time.perf_counter()
    try:
        cur.execute(sql)
        while cur.nextset():  # drain multi-statement payloads
            pass
    except psycopg2.errors.QueryCanceled:
        raise SystemExit(f"TIMEOUT after {timeout_s}s: {sql[:60]}...")
    return time.perf_counter() - t0


def measure(cur, sql: str, timeout_s: int, warmup: bool = True):
    if warmup:
        timed(cur, sql, timeout_s)
    runs = [timed(cur, sql, timeout_s) for _ in range(3)]
    return runs, statistics.median(runs)


def remote_table_exists(args, ns_table: str) -> bool:
    """Probe the Iceberg catalog WITHOUT reading data (pyiceberg in the
    fixture docker network — the host cannot reach s3:9000's internal
    name). One REST lookup, no scan."""
    import subprocess
    code = f"""
from pyiceberg.catalog import load_catalog
cat = load_catalog("smoke", type="rest", uri={args.catalog_uri!r},
                   warehouse="smoke",
                   **{{"s3.endpoint": {args.s3_endpoint!r},
                      "s3.access-key-id": "lakehouse-test",
                      "s3.secret-access-key": "lakehouse-test-password"}})
try:
    cat.load_table({ns_table!r})
    print("EXISTS")
except Exception:
    print("MISSING")
"""
    out = subprocess.run(
        ["docker", "run", "--rm", "-i", "--network", args.docker_net,
         "-v", f"{args.pdi_venv}:/venv",
         "-e", f"PYTHONPATH=/venv/lib/{args.pdi_py_minor}/site-packages",
         "python:3.12-slim", "python3", "-"],
        input=code, capture_output=True, check=True, text=True)
    return "EXISTS" in out.stdout


def generate_scan_fixture(args):
    # bulk generation rides pyiceberg in the fixture docker network
    # (host cannot reach s3:9000's docker-internal name); python-
    # formatted into a standalone script — see SCAN_SETUP_PY above.
    import subprocess
    code = SCAN_SETUP_PY % (args.scan_rows, args.catalog_uri,
                            args.s3_endpoint, args.scan_rows)
    subprocess.run(
        ["docker", "run", "--rm", "-i", "--network", args.docker_net,
         "-v", f"{args.pdi_venv}:/venv",
         "-e", f"PYTHONPATH=/venv/lib/{args.pdi_py_minor}/site-packages",
         "python:3.12-slim", "python3", "-"],
        input=code, check=True, text=True)


def ensure_scan_fixture(conn, args):
    """Reuse a verified fixture if one exists; generate only when missing
    or when verification FAILS (accuracy is checked, not assumed — a
    stale/mismatched fixture would silently poison every measurement)."""
    cur = conn.cursor()
    remote_name = f"perfcn.scan_bench_n{args.scan_rows}"
    exists = remote_table_exists(args, remote_name) \
        if not args.force_regen else False
    if exists:
        # attach first (the fixture may predate this foreign table), then
        # VERIFY: ids are exactly 0..N-1, so count and sum have exact
        # expected values — one cheap scan proves content accuracy
        cur.execute(SCAN_DDL, [args.catalog_uri, args.s3_endpoint,
                               "lakehouse-test", "lakehouse-test",
                               remote_name])
        cur.execute("SELECT count(*), sum(id) FROM perf_scan")
        n, total = cur.fetchone()
        want_n, want_total = args.scan_rows, \
            args.scan_rows * (args.scan_rows - 1) // 2
        if n == want_n and total == want_total:
            print(f"NOTICE: scan fixture exists and VERIFIED "
                  f"(rows={n}, sum(id)={total}) — reusing, no generation")
            return n
        print(f"WARNING: scan fixture MISMATCH (rows={n}/{want_n}, "
              f"sum(id)={total}/{want_total}) — regenerating")
    elif args.force_regen:
        print("NOTICE: --force-regen — regenerating scan fixture")
    else:
        print("NOTICE: no scan fixture in the catalog — generating")
    generate_scan_fixture(args)
    cur.execute(SCAN_DDL, [args.catalog_uri, args.s3_endpoint,
                           "lakehouse-test", "lakehouse-test",
                           remote_name])
    cur.execute("SELECT count(*), sum(id) FROM perf_scan")
    n, total = cur.fetchone()
    want_total = args.scan_rows * (args.scan_rows - 1) // 2
    if n != args.scan_rows or total != want_total:
        raise SystemExit(f"generated fixture FAILED verification "
                         f"(rows={n}, sum(id)={total})")
    print(f"scan fixture generated and VERIFIED: rows={n}")
    return n


def run_scan_suite(conn, args):
    ensure_scan_fixture(conn, args)
    cur = conn.cursor()
    queries = {
        "scan_count": "SELECT count(*) FROM perf_scan;",
        "scan_agg": ("SELECT count(*), sum(id) FROM perf_scan "
                     "WHERE id %% 97 = 0;"),
        "scan_group": ("SELECT name, count(*) FROM perf_scan "
                       "GROUP BY 1 ORDER BY 2 DESC LIMIT 5;"),
    }
    rows = []
    for name, sql in queries.items():
        runs, med = measure(cur, sql, args.timeout, warmup=args.warmup)
        print(f"{name}: runs={['%.2f' % r for r in runs]} median={med:.2f}s")
        rows.append((name, med))
    return rows


def run_tpcds_suite(conn, args):
    cur = conn.cursor()
    # foreign tables are attached UNPREFIXED (that is how the shipped
    # query files reference them); args.tpcds_ns names the ICEBERG
    # namespace only
    cur.execute(f"SELECT count(*) FROM store_sales")
    n = cur.fetchone()[0]
    if n == 28_800_991:
        print("NOTICE: TPC-DS fixture exists and VERIFIED "
              "(store_sales rows=28,800,991) — reusing, no generation")
    else:
        print(f"WARNING: store_sales rows={n} != 28,800,991 — the SF=10 "
              "fixture is stale or wrong; regenerate with "
              "scripts/gen_tpcds.py + write_tpcds_iceberg.py before "
              "trusting these numbers")
    rows = []
    for q in TPCDS_QUERIES:
        sql = (Path(args.queries) / f"{q}.sql").read_text()
        runs, med = measure(cur, sql, args.timeout, warmup=args.warmup)
        print(f"{q}: runs={['%.1f' % r for r in runs]} median={med:.1f}s")
        rows.append((q, med))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--suite", choices=["tpcds", "scan"], default="tpcds")
    ap.add_argument("--dsn", default="postgres://postgres@localhost:52021/postgres")
    ap.add_argument("--timeout", type=int, default=1200,
                    help="per-run statement timeout (s)")
    ap.add_argument("--no-warmup", dest="warmup", action="store_false",
                    help="skip the warmup run (measures genuinely cold)")
    # scan-suite knobs
    ap.add_argument("--force-regen", action="store_true",
                    help="regenerate the scan fixture even if one exists "
                         "and verifies (default: reuse verified fixtures)")
    ap.add_argument("--scan-rows", type=int, default=1_000_000)
    ap.add_argument("--catalog-uri", default="http://lakekeeper:8181/catalog")
    ap.add_argument("--s3-endpoint", default="http://s3:9000")
    ap.add_argument("--docker-net", default="pgdatalake_default")
    ap.add_argument("--pdi-venv", default="/tmp/pdi-venv")
    ap.add_argument("--pdi-py-minor", default="python3.12")
    ap.add_argument("--tpcds-ns", default="tpcds",
                    help="fixture namespace; convention for NEW fixtures: "
                         "tpcds_sf<N> so scales never collide (existing "
                         "M1 fixture lives in 'tpcds' at SF=10)")
    ap.add_argument("--queries", default=str(DEFAULT_QUERIES))
    args = ap.parse_args()

    conn = connect(args.dsn)
    cur = conn.cursor()
    cur.execute("SELECT lakehouse.version()")
    print(f"engine: {cur.fetchone()[0]}")

    rows = run_tpcds_suite(conn, args) if args.suite == "tpcds" \
        else run_scan_suite(conn, args)

    print("\n| query | median (s) |")
    print("|---|---|")
    for name, med in rows:
        print(f"| {name} | {med:.2f} |")


if __name__ == "__main__":
    main()
