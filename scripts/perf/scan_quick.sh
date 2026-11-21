#!/bin/sh
# perf-lakehouse seed (spec 10 §5): cold/warm scan measurement over an
# Iceberg table at TPC-H-lineitem shape, ~1% scale. NOT a CI gate —
# wall-clock is runner-noisy; the deterministic P0b metrics are the
# cold/warm ratio (repeat scans must be cache-served) and file/GET
# evidence in EXPLAIN.
#
#   scripts/perf_scan.sh [rows]      default 1000000 (~1% of lineitem)
#
# Requires: fixture stack up (make lakehouse-up), vg-m3-style postgres
# with the lakehouse extension (PGHOST/PGPORT/PGUSER/PGDATABASE/PSQL env,
# defaults to the dev instance on :52018), PDI_VENV with pyiceberg.
set -eu

ROWS=${1:-1000000}
PGHOST=${PGHOST:-localhost}
PGPORT=${PGPORT:-52018}
PGUSER=${PGUSER:-postgres}
PGDATABASE=${PGDATABASE:-postgres}
PSQL=${PSQL:-psql}
PDI_VENV=${PDI_VENV:-/tmp/pdi-venv}
PDI_NET=${PDI_NET:-pgdatalake_default}
NS=perf
TBL=lineitem_sf001
REMTBL="$NS.$TBL"
PGTBL="perf_$TBL"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

PDI_SITE=$(ls -d "$PDI_VENV"/lib/python3.*/site-packages 2>/dev/null | head -1)
[ -n "$PDI_SITE" ] || { echo "FAIL: no site-packages under PDI_VENV=$PDI_VENV"; exit 1; }
PDI_PY_MINOR=$(basename "$(dirname "$PDI_SITE")")
PDI() {
    docker run --rm -i --network "$PDI_NET" \
        -v "$PDI_VENV":/venv \
        -e PYTHONPATH="/venv/lib/$PDI_PY_MINOR/site-packages" \
        python:3.12-slim python3 -
}

psql_run() {
    "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        -v ON_ERROR_STOP=1 "$@"
}

echo "== perf_scan: $REMTBL rows=$ROWS =="

# --- generate the table in Iceberg (pyarrow synthetic lineitem shape) ------
PDI <<PYEOF
import random
import pyarrow as pa
from pyiceberg.catalog import load_catalog
from pyiceberg.exceptions import NoSuchTableError
from pyiceberg.schema import Schema
from pyiceberg.types import (DoubleType, IntegerType, LongType,
                             NestedField, StringType)

random.seed(42)
cat = load_catalog("smoke", type="rest",
                   uri="http://lakekeeper:8181/catalog", warehouse="smoke",
                   **{"s3.endpoint": "http://s3:9000",
                      "s3.access-key-id": "lakehouse-test",
                      "s3.secret-access-key": "lakehouse-test-password"})
try:
    cat.create_namespace("$NS")
except Exception:
    pass
try:
    cat.drop_table("$REMTBL")
except NoSuchTableError:
    pass
schema = Schema(
    NestedField(1, "l_orderkey", LongType(), required=False),
    NestedField(2, "l_partkey", LongType(), required=False),
    NestedField(3, "l_suppkey", IntegerType(), required=False),
    NestedField(4, "l_linenumber", IntegerType(), required=False),
    NestedField(5, "l_quantity", DoubleType(), required=False),
    NestedField(6, "l_extendedprice", DoubleType(), required=False),
    NestedField(7, "l_discount", DoubleType(), required=False),
    NestedField(8, "l_tax", DoubleType(), required=False),
    NestedField(9, "l_returnflag", StringType(), required=False),
    NestedField(10, "l_linestatus", StringType(), required=False),
    NestedField(11, "l_shipdate", StringType(), required=False),
    NestedField(12, "l_comment", StringType(), required=False),
)
t = cat.create_table("$REMTBL", schema=schema, properties={"format-version": "2"})

ROWS = $ROWS
CHUNK = 200_000
for base in range(0, ROWS, CHUNK):
    k = min(CHUNK, ROWS - base)
    tbl = pa.table({
        "l_orderkey": pa.array([base + i for i in range(k)], pa.int64()),
        "l_partkey": pa.array([random.randrange(1, 200_000) for _ in range(k)], pa.int64()),
        "l_suppkey": pa.array([random.randrange(1, 10_000) for _ in range(k)], pa.int32()),
        "l_linenumber": pa.array([i % 7 + 1 for i in range(k)], pa.int32()),
        "l_quantity": pa.array([random.uniform(1, 40) for _ in range(k)], pa.float64()),
        "l_extendedprice": pa.array([random.uniform(800, 90_000) for _ in range(k)], pa.float64()),
        "l_discount": pa.array([random.uniform(0, 0.08) for _ in range(k)], pa.float64()),
        "l_tax": pa.array([random.uniform(0, 0.08) for _ in range(k)], pa.float64()),
        "l_returnflag": pa.array([random.choice("ARN") for _ in range(k)], pa.string()),
        "l_linestatus": pa.array(["O" if i % 2 else "F" for i in range(k)], pa.string()),
        "l_shipdate": pa.array([f"1998-{(i % 12) + 1:02d}-{(i % 28) + 1:02d}" for i in range(k)], pa.string()),
        "l_comment": pa.array([f"comment {base + i} " + "x" * 60 for i in range(k)], pa.string()),
    })
    t.append(tbl)
print(f"generated $REMTBL rows={ROWS} files={len(t.scan().plan_files())}")
PYEOF

# --- attach in postgres (staged->published path not needed: pyiceberg
# wrote the files; we measure the SCAN side) ------------------------------
psql_run -q <<EOF
DROP TABLE IF EXISTS $PGTBL CASCADE;
DO \$\$ BEGIN CREATE FOREIGN DATA WRAPPER perf_wrapper
    HANDLER lakehouse.lakehouse_fdw_handler;
EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;
DO \$\$ BEGIN CREATE SERVER perf_srv FOREIGN DATA WRAPPER perf_wrapper
    OPTIONS (endpoint 'http://localhost:8181/catalog',
             warehouse 'smoke',
             s3_endpoint 'http://localhost:9000');
EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER perf_srv
    OPTIONS (s3_access_key 'lakehouse-test',
             s3_secret_key 'lakehouse-test-password');
CREATE TABLE $PGTBL (
    l_orderkey bigint, l_partkey bigint, l_suppkey int, l_linenumber int,
    l_quantity double precision, l_extendedprice double precision,
    l_discount double precision, l_tax double precision,
    l_returnflag text, l_linestatus text, l_shipdate text, l_comment text
) SERVER perf_srv
    OPTIONS (table '$REMTBL');
EOF

# --- cold/warm measurements ------------------------------------------------
# cold: a FRESH backend per query (connection per run => per-backend cache).
# warm: same backend, repeat scans (shared_buffers has no object bytes —
# the win must come from the BlockCache).
run_q() { # $1 label, $2 sql, $3 cold(1)/warm(0)
    if [ "$3" = "1" ]; then
        "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
            -v ON_ERROR_STOP=1 -q -c "$2" >/dev/null
    else
        psql_run -q -c "$2" >/dev/null
    fi
}
timeit() { # $1 label, $2 cold, $3..=query via stdin
    local label="$1" cold="$2" sql="$3" t0 t1
    t0=$(date +%s.%N)
    run_q "$label" "$sql" "$cold"
    t1=$(date +%s.%N)
    echo "$label: $(echo "$t1 $t0" | awk '{printf "%.2f", $1 - $2}')s"
}

Q_COUNT="SELECT count(*), sum(l_extendedprice * (1 - l_discount)) FROM $PGTBL;"
Q_PROJ="SELECT l_returnflag, l_linestatus, sum(l_quantity), sum(l_extendedprice)
         FROM $PGTBL GROUP BY 1, 2 ORDER BY 1, 2;"
Q_FATPROJ="SELECT count(*) FROM $PGTBL;"   # count needs no columns at all

echo "-- cold (fresh backend = empty per-backend cache) --"
timeit "q_count  cold" 1 "$Q_COUNT"
timeit "q_proj   cold" 1 "$Q_PROJ"
echo "-- warm (same backend, repeat scans = BlockCache-served) --"
timeit "q_count  warm" 0 "$Q_COUNT"
timeit "q_count  warm" 0 "$Q_COUNT"
timeit "q_proj   warm" 0 "$Q_PROJ"

# --- EXPLAIN evidence (file/GET shape) -------------------------------------
psql_run -q -c "EXPLAIN (COSTS OFF) SELECT count(*) FROM $PGTBL;"

echo "== perf_scan done =="
