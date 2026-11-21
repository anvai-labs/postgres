# HANDOFF.md — State for the Next Session

*Updated 2026-11-19. Working directory: `/home/vsingh/code/postgres`.*

## What exists

- Repo: `/home/vsingh/code/postgres`, clone of `postgres/postgres` master
  (`61f6021b110`, PG 20 dev). `origin` = `anvai-labs/pgdatalake` (private),
  `upstream` = `postgres/postgres`.
- **Branch layout**: `main` = fork base (upstream master + specs commits, merge
  sync per RULES §1 as amended); `lakehouse-dev` = integration branch (renamed
  from `iceberg-dev` 2026-11-19). NOTE: GitHub's default branch is still
  `master` on the remote — flipping it to `main` via `gh repo edit` was denied
  by the harness and `origin/master` still exists; do that manually
  (`gh repo edit anvai-labs/pgdatalake --default-branch main`, then
  `git push origin --delete master`).
- **Naming (decided 2026-11-19, user)**: format-generic lakehouse. Rust core
  `pgdatalake-core` (C ABI `pg_datalake_*`, `libpgdatalake_core.a`), SQL
  surface `lakehouse` (schema/extension/`USING lakehouse FORMAT iceberg`),
  views `pg_lakehouse`, GUCs `lakehouse.*`, SQLSTATE `LD0`, meson
  `-Ddatalake=auto`, branch/tests/fixtures/make-targets all `lakehouse*`.
  Iceberg is a FORMAT layer, not the product name. Don't relitigate.
- **M0 done 2026-11-19** — tag `milestone/m0`, GitHub release, cold-room gate
  ALL GREEN (transcript `retro/m0-smoke-transcript.txt`, retro `retro/m0.md`).
  Upstream regress 243/243 under `meson test --suite regress` (meson-only
  tree; autoconf `make check` = legacy escape hatch, see RULES §9 amendment).
- **M1 in progress** (REST client + read path, all TDD, live-verified vs the
  Lakekeeper + SeaweedFS fixture stack):
  - slice 1 `GET /v1/config` (+ `?warehouse=` — Lakekeeper requires it);
  - slice 2 OAuth2 client-credentials, cached, proactive refresh at 80% TTL;
  - slice 3 `loadTable` + **v3-first** metadata model (FormatVersion enum
    rejects v1; v3 types — unknown/timestamp_ns/variant + snapshot
    sequence-number/first-row-id — are first-class; v2 parses same model).
    Namespace `%1F` joins, prefix auto-stored from merged config view
    (Lakekeeper puts prefix in **defaults**), 404 -> `RestError::NotFound`;
  - slice 4 object-store IO: `Location` (s3:// full bucket keys, file://
    rooted local), `StorageIo` over object_store (aws+http), gzip decode
    for `.gz.metadata.json`, blocking over internal tokio current-thread rt.
  - live example: `cargo run --example fetch_config` walks config ->
    loadTable -> S3 fetch -> gzip -> parse (fixture: Lakekeeper `smoke`
    warehouse, table `analytics.events` — both created idempotently by
    `lakekeeper-setup.sh`, wired into `make lakehouse-up`).
  - 22 cargo unit tests; deps: serde/serde_json/reqwest(rustls,blocking)/
    tokio(rt)/object_store(aws,http)/flate2/uuid/urlencoding; tiny_http +
    tempfile in dev-deps (unit tests use in-process mocks + local store —
    no network at unit-test time, doc 10 §1).
  - slice 5 manifest-list Avro reader (apache-avro dep; embedded writer
    schema VALIDATED against required fields — doc 10 §4 fuzz hardening);
  - slice 6 manifest data-file reader (entry status, delete-file content
    types, column-stats maps by field id; partition opaque until pruning);
  - slice 7 plan_scan() — snapshot selection -> manifest-list -> manifests
    -> ScanTask list (DELETED dropped, sequence numbers resolved, row/file
    aggregates); fully offline-tested via file:// fixtures;
  - 27 cargo tests; apache-avro dep added.
  - slice 8 partition-spec model + identity-transform pruning
    (conservative: non-identity transforms always keep the file);
  - slice 9 FFI boundary (pg_datalake_scan_*, panic-free catch_unwind,
    caller-owned error buffers, # Safety docs) + CatalogClient
    orchestrator + lakehouse.scan_files() SQL SRF (8 text args; storage
    credentials are caller-side — object_store IMDS fallback caught live);
  - slice 10 Parquet row reads (parquet/arrow 54) + rows FFI
    (pg_datalake_rows_open/next/col_*/close; values rendered to text at
    advance time, nulls via parallel flags; CellValue normalization
    Int32->Int64, Float32->Float64);
  - slice 11 FDW handler (fdw.c): GetForeignRelSize/Paths/Plan +
    Begin/Iterate/ReScan/End; table option 'analytics.events' with
    namespace = last-dot prefix (doc 03 §3); quals evaluated locally
    (no pushdown yet); regress fdw.sql proves pg_class relkind 'f' +
    information_schema + 08000 fail-fast. NOTE: FDW ships in the single
    lakehouse module for M1 (doc 01 said contrib/lakehouse_fdw — split is
    the M5 extraction item; note in retro).
  - 35 cargo tests + 3 regress groups; deps now incl. parquet/arrow 54.
  - slice 12 PyIceberg fixture data + interop fixes: scripts/gen_fixtures.py
    (3 runs x 1000 rows into analytics.events; venv at build/venv, or run
    in-container per script docs); int->long Avro promotions, nullable
    union snapshot_id, long split_offsets, arrow temporal primitive
    arrays, CellValue::TimestampMicros + ISO rendering (civil-from-days,
    no chrono). LIVE: SELECT count/min/max/WHERE through the FDW over
    PyIceberg-written data — full read path works end-to-end.
  - 36 cargo tests + 3 regress groups.
  - slice 13 EXPLAIN visibility (ExplainForeignScan: table/endpoint/
    task count/rows/projection/pushdown status) + projection pushdown
    from targetlist+qual Vars + live BUG FIX: local quals were in the
    fdw_recheck_quals slot (never evaluated on plain scans — WHERE
    returned all rows); moved to qpqual, verified live (4/3000/2100).
  - slice 14 bounds-based predicate pushdown: ScanPredicate Lt/Le/Gt/Ge
    + bounds_keep() over manifest column stats (conservative: missing
    bounds/ids/types always keep; field-id resolution via current
    schema); plan_scan prunes partitions AND bounds.
  - slice 15 FDW qual->predicate translation: TranslateQual (Var-op-Const,
    =/</<=/>/>= with flipped-op inversion; per-type value conversion —
    int/date days, timestamp(s)/tstz micros matching bounds width,
    floats, text with JSON escaping) -> predicate JSON via FFI ->
    plan_scan pruning; ALL clauses stay in qpqual (pruning conservative,
    executor enforces exact per-row filter); live bugs fixed: RestrictInfo
    vs plain-Expr (translate after extract_actual_clauses), double
    extract segfault, predicate/opts ordering (pruning silently skipped +
    wrong counts), qpqual slot (Filter never applied). LIVE: EXPLAIN shows
    tasks: 1 (pruned from 3) for WHERE id<5; count(*)=4 exact.
  - pyiceberg manifest metric maps fixed: real manifests encode metrics as
    ARRAYS of {key:int, value} records (raw avro dump confirmed); parser
    accepts both shapes; fixtures updated to spec shape.
  - 40 cargo tests + 3 regress groups.
  - slice 16 EXPLAIN pruned evidence: ScanPlan.files_before/after_pruning
    + FFI accessors; EXPLAIN shows 'Iceberg files examined: N' and
    'Iceberg files pruned: M' (omitted when nothing pruned). LIVE:
    WHERE id<5 -> examined 3 / pruned 2 / tasks 1.
  - 41 cargo tests + 3 regress groups.
  - slice 17 parallel scans: IsForeignScanParallelSafe (required or the
    planner disables parallel entirely), partial path with
    parallel_aware=true (without it the worker DSM hook never runs and
    every process scans all tasks — the 3x-duplicates bug, caught live),
    DSM hooks + pg_atomic_uint64 claim counter in Iterate. LIVE:
    Gather/2 workers, count=3000 distinct=3000, WHERE under parallelism
    exact. M1 limitation: one foreign scan per query for the shared
    static pointer (documented, revisit when multi-scan queries matter).
  - slice 18 snapshot pinning: FDW option snapshot_id -> FFI
    scan_new(snapshot_id) -> plan_scan snapshot selection. LIVE:
    table pinned to first pyiceberg snapshot reads 1000 rows while
    current reads 3000 — time-separated reads verified.
  - slice 19 time travel grammar (SELECT ... FOR TIMESTAMP/VERSION/TAG
    AS OF): the design DECISION — the clause lives in the LOCKING-CLAUSE
    position (per-table attachment is impossible: after a from-item a
    bare FOR starts FOR UPDATE and LALR(1) cannot disambiguate; bison
    %expect 0 rejects it). The pin rides in SelectStmt.lockingClause as
    a raw DefElem; consumers of that list skip DefElem entries
    (analyze.c x2 error paths + main loop, parse_relation.c
    isLockedRefname). applyLakehouseTimeTravel (parse_clause.c) resolves
    the DefElem into a canonical selector string on RTE.lakehouse_snapshot
    ("ts:<ms>" / "id:<n>" / "ref:<name>") for every foreign-table RTE of
    the level — timestamps via timestamptz_in at parse time (rules/views
    store epoch ms, timezone-stable); big ids lex as Float and are
    validated with pg_strtoint64_safe. FDW carries the selector in
    fdw_private[2], OpenSession prefers it over the snapshot_id option,
    plan-time errors name the selector (regress-observable). Rust core:
    SnapshotSelector enum (Id/Ts/Ref) + metadata refs map + resolve
    (ts = latest snapshot <= ts; ref = refs map lookup); FFI takes
    selector JSON instead of i64. catversion bumped (parsed trees in
    rules). LIVE: 3 snapshots x 1000 rows — VERSION AS OF id -> 2000,
    TIMESTAMP AS OF between snapshots -> 1000, TAG AS OF 'main' -> 3000,
    pin wins over table option, stored view keeps pin, EXPLAIN pruning
    within pinned snapshot. NEW regress group time_travel (deterministic:
    parse validation, VALUES/setop/locking non-applicability, plain-table
    no-op, rule round-trip via selector-named plan errors). 44 cargo
    tests + 4 regress groups.
    SPEC: 02-sql-surface.md §4 amended (implemented surface + LALR(1)
    rationale, original sketch kept as Superseded); RULES §3 grammar
    plumbing row added (kwlist/parse_clause/parse_relation/analyze/
    parsenodes RTE field/catversion).
  - slice 20 v2 delete application: plan_scan separates delete files
    (manifest content 1/2) into ScanPlan.delete_tasks (never data tasks);
    load_row_deletes reads them eagerly at scan_new -> LoadedDeletes
    (positions_by_file from (file_path,pos) parquet + EqDeleteMatch
    tuples with the delete's sequence number). rows_open slices
    LoadedDeletes per data file: position deletes exact per-file;
    equality deletes only when delete seq > data seq and, in M1, only
    for UNPARTITIONED data files (partitioned + eq deletes -> loud
    Config error; partition-scoped application deferred). ParquetRows
    gained open_with_deletes + absolute-position tracking across batches
    (batch_start_abs) + eq columns join the INTERNAL read set when not
    projected. FFI end-to-end test: mock catalog + REAL position-delete
    parquet -> rows 1,3 (id=2 removed) through pg_datalake_rows_open.
    LIVE: PyIceberg 0.12 table.delete() is COW (rewrites the data file,
    no delete files) — the live transcript proves COW-rewrite read compat
    (analytics.events_del: 10 appended -> delete -> FDW reads 8 rows,
    pre-delete snapshot via FOR VERSION AS OF reads 10); live MoR
    fixtures come from Spark/Trino at the M1 gate or our M2 writer.
    GOTCHA: lakekeeper serves per-table config s3.endpoint=http://s3:9000
    (container-scoped) which BEATS pyiceberg client/table properties —
    host-side pyiceberg writes must run inside the compose network
    (docker run --network pgdatalake_default with the venv mounted at
    its absolute path; see scripts note in retro). SPEC: 06-execution.md
    §3 amended (slice 20 amendment). 46 cargo tests + 4 regress groups.
  - slice 21 conformance read-half (M1 gate item): full primitive type
    matrix decodes to PG-input-compatible TEXT — NEW decodes: decimal128
    -> canonical unscaled/scale text, uuid (parquet FLBA(16)) ->
    canonical hyphenated text, date/date64 -> ISO, time32/64 ->
    HH:MM:SS.ffffff, binary -> \x-prefixed bytea hex (previously raw
    ints / bare hex that date_in/time_in/bytea_in reject — caught by
    TDD red tests). Conformance fixtures:
    scripts/gen_conformance_fixtures.py (PyIceberg writer, MUST run
    inside the compose network — see lakekeeper per-table
    s3.endpoint gotcha at slice 20) writes analytics.types_all (full
    type matrix, 3 rows incl. all-NULL) + analytics.parts_multi
    (day/month/bucket[8]/truncate[2]/identity spec, 12 files). LIVE:
    types_all reads with correct SQL values (uuid/decimal/date/time/
    bytea round-trip, all-NULL row); parts_multi identity pruning
    EXPLAIN examined 12 / pruned 6 / tasks 6, non-identity predicates
    correct-conservative. INTEROP QUIRK: pyiceberg 0.12 writes Iceberg
    fixed[L] as ASCII hex STRINGS (spec wants FLBA(L)) — documented in
    05-types.md §1; Trino/Spark-written fixed reads fine. PyIceberg
    table.delete() is COW (slice 20 note). 49 cargo tests + 4 regress
    groups.
  - slice 22 Trino interop (M1 gate item DONE): trino service in
    docker-compose (profile "trino", host port 18081 — 8080 is taken on
    the dev host; config fixtures/trino-catalog.properties: REST catalog
    over lakekeeper + native S3 filesystem). LIVE: Trino writes
    day-partitioned trino_smoke.events (bigint/varchar/decimal/
    timestamp/boolean), DELETEs id=2 via an MoR POSITION-DELETE file
    (verified content=1 in $manifests); our FDW reads exactly ids {1,3}
    — agreeing with Trino's own view — and FOR VERSION AS OF matches
    Trino on every historical snapshot (Trino's two-phase commit writes
    an empty first append snapshot; both engines read 0). INTEROP FIX:
    Trino writes single-valued optional manifest fields as plain Int
    inside the Avro union (sort_order_id hit it live) — manifest parser
    accepts Int/Long singles in unions alongside pyiceberg's shapes.
    SPEC: 10-testing.md §2 interop-gate status amended (outstanding:
    Spark eq-deletes, Trino codec matrix, Trino-reads-our-writes at M2).
  - slice 23 M1 TPC-DS gate + rescan fix: dataset = TPC-DS SF=10 via
    duckdb dsdgen (21 tables, 3.1GB parquet on S3; store_sales 28.8M
    rows). PRUNING EVIDENCE: identity-partitioned store_sales (18,240
    files) -> WHERE ss_sold_date_sk = 2450992 examined 18,240 / pruned
    18,230 / tasks 10, exact count, 3.6s incl. planning over 18k
    manifests; negative control documented (unpartitioned dsdgen output
    cannot bounds-prune — every file spans the full date range; correct,
    and the motivating case for optimize). TIMINGS: full scale q1 1.2s /
    q2 18.0s / q3 >60min terminated (CPU-bound; row-by-row FDW
    transport = known M1 bottleneck, fix path slice 24 columnar batch
    reads); sampled-scale (1% facts) ALL 10 QUERIES GREEN 0 errors
    (q1 1.33s q2 .36s q3 .21s q4 2.31s q5 7.26s q6 .5s q7 2.97s q8 1.0s
    q9 7.26s q10 5.3s). Engine findings: (1) FIXED
    ReScanForeignScan re-planned per rescan (catalog round-trip +
    manifest fetch) — merge-join inner rescans made join queries take
    minutes; now rewind-only, session reused, snapshot pinned at open.
    (2) RECORDED correlated-subplan pathology (q6: per-outer-row full
    foreign scan of item, no index available) — fix path remote
    parameterization or hash-subplan conversion (M2/M3). Evidence
    ledger: src/test/lakehouse/fixtures/gate-evidence-m1-tpcds.md.
    TPC-DS helpers: duckdb dsdgen -> /tmp/tpcds parquet ->
    scripts-driven PyIceberg write (transient scripts in /tmp during the
    gate run; worth promoting to scripts/ if the fixture is reused).
    Cross-engine: proximadb session (proximadb-e4) benchmarking the
    same fixture (native/DataFusion/DuckDB) against these numbers;
    results land in 10-testing.md when delivered.
  - M1 CLOSED 2026-11-19: cold-room ceremony COLDROOM M1 ALL GREEN
    (scripts/coldroom-smoke-m1.sh — fresh clone + fresh fixture stack:
    build, setup/upstream/lakehouse suites incl. time_travel, cargo,
    PyIceberg fixture generation in-network, live read-path/
    time-travel-mechanics/type-matrix verification). Retro at
    specs/lakehouse/retro/m1.md (8 findings incl. row-transport
    bottleneck, rescan re-plan bug, LALR(1) FOR-clause lesson, 2
    operational gotchas). Tag milestone/m1. NEXT: M2 per the slice
    plan above (slice 24 first: Rust Parquet writer).
  - **Next slices**: M1 conformance
    gate (Trino-written tables, TPC-DS subset, perf vs doc 10 §5) ->
    smoke ceremony -> M1 retro + tag milestone/m1.
- **M2 slice plan (written 2026-11-19, before M1 close; per doc 07 §2
  commit protocol + doc 01 §2 module layout)**:
  - slice 24 — DONE 2026-11-19 (writer.rs, CI green): Rust Parquet
    writer: columnar batch accumulator -> arrow RecordBatch -> parquet
    bytes -> StorageIo put; deterministic <rows>-<seq>.parquet naming.
  - slice 25 — DONE 2026-11-19 (catalog/commit.rs, CI green): REST
    commit protocol: commitTable with requirements [AssertTableUUID,
    AssertRefSnapshotId(main, base), + all spec requirement types],
    conflict classification (409 -> RestError::Conflict, the only
    retryable class) + bounded re-plan retry; wire shapes pinned against
    installed pyiceberg 0.12 (requirements tag "type", updates tag
    "action", explicit-null snapshot-id). 59 cargo tests incl. scripted
    mock-catalog 409->re-plan->success and budget-exhaustion paths.
  - slice 26 — DONE 2026-11-19 (tableam.c + extension SQL, regress
    green): `USING lakehouse` TableAM skeleton. PLAN AMENDMENT: the
    pg_am.dat [core-allowlist] row + catversion bump turned out
    unnecessary — runtime CREATE ACCESS METHOD (in lakehouse--1.0.sql)
    registers the AM as an ordinary pg_am row, zero core edits. Scan
    callbacks DELEGATE to the FDW session pipeline (shared lakehouse.h:
    LakehouseOptions + lakehouse_OpenSession + BuildSelectorJson moved
    out of fdw.c statics); identity lives in lakehouse.managed_tables +
    lakehouse.attach_table (slice 27 wires it at CREATE time; drop-GC
    via sql_drop event trigger). Regress tableam.sql: AM round-trip,
    relam wiring, default_table_access_method, unattached-scan clean
    error, unreachable-endpoint 08000 fail-fast parity with the FDW,
    INSERT 0A000, re-attach idempotence, DROP hygiene.
  - slice 27 — INSERT, SPLIT into two commits (2026-11-20 planning,
    after slice 26 showed the gap): the missing piece between slice 24
    (parquet data files) and slice 25 (commitTable client) is ICEBERG
    METADATA WRITING:
    - 27a — DONE 2026-11-20 (snapshot_write.rs, CI green): manifest
      avro + manifest-list avro writers (spec field-ids included —
      Trino/pyiceberg readers map by field-id, needed for the slice-29
      gate) + write_snapshot assembler (writes both avros, returns the
      AddSnapshot payload Snapshot + written keys). 62 cargo tests incl.
      the END-TO-END anchor: BatchWriter -> data file -> write_snapshot
      -> metadata merge -> OUR plan_scan reads rows back; manifest and
      manifest-list round-trip through the existing readers.
    - 27b-i — DONE 2026-11-20 (ffi.rs write surface + session.rs +
      writer.rs row-JSON, CI green): pg_datalake_write_new/push/flush/
      commit/free. write_table_open resolves identity + field-ids from
      the table's schema; commit_append flushes -> write_snapshot ->
      commit_with_retry with requirements rebuilt from each fresh
      loadTable (appends are additive — only the base pin moves).
      Typed row-JSON cells (bare values + {"d"}/{ "t"}/{"ts"}/{"dec"}/
      {"u"}/{"b"} wrappers) so the C side sends datum arithmetic, not
      text formatting. Anchor: mock-catalog write->commit->capture
      commitTable body->merge snapshot->scan OUR OWN rows back (1,2).
    - 27b-ii — DONE 2026-11-20 (tableam.c + ffi fixes, LIVE-VERIFIED):
      tuple_insert accumulates typed row-JSON into the FFI write
      session (backend-local hash keyed by relid; RegisterXactCallback:
      PRE_COMMIT commits each session via pg_datalake_write_commit,
      ABORT/COMMIT frees + destroys the hash), own-writes overlay
      (scan yields staged datum copies after file rows — verified
      live: staged_visible = 3 pre-commit), datum arithmetic for
      date/time/ts (PG epoch 2000 -> unix epoch via JULIAN offsets),
      numeric/uuid/bytea as canonical text, unsupported types rejected
      at first insert. LIVE CYCLE: INSERT 3 rows (incl NULL) -> commit
      -> fresh PG session reads 3 rows -> PYICEBERG reads
      {1,2,3}/{alpha,beta,None} -> TRINO reads 1|alpha,2|beta,3|NULL.
      THE SLICE-29 GATE (Trino reads a table we wrote) IS PROVEN LIVE
      ahead of the ceremony. Offline regress anchors updated: INSERT
      now stages (identity error 0A000 unattached; 08000 unreachable at
      session open).
      WIRE-CONVENTION GOTCHAS (all caught live by cross-engine reads,
      recorded for doc 03): (1) manifest avro field-ids go ONLY on
      record FIELDS — never on records/arrays; missing field-id on the
      data_file FIELD made Trino+pyiceberg both fail ("Missing required
      field: data_file"); (2) real LIST arrays need "element-id"
      (partitions 508, split_offsets 133, equality_ids 136); (3) kv
      metric arrays need "logicalType": "map" (pyiceberg's reader
      requirement); (4) parquet footers MUST carry PARQUET:field_id
      metadata (WriteColumn.field_id) — Trino/pyiceberg map parquet
      columns by field id and read EMPTY columns without it; (5) S3
      keys are bucket-relative in StorageIo (location path prefix must
      be re-appended on writes); (6) Lakekeeper's commitTable response
      carries in-band metadata + explicit-null config (tolerant decode).
      27c — DONE 2026-11-20 (managed CREATE, live-verified): PURE-SQL
      lifecycle now works end-to-end: CREATE TABLE ... USING lakehouse
      -> attach_table -> lakehouse.create_remote(regclass) (schema from
      the relation's tupdesc, namespace auto-created, 409 -> 'exists')
      -> INSERT. Verified live across PG + pyiceberg ({7,8}/{seven,
      None}) + Trino (7|seven, 8|NULL) on the freshly created table.
      RestCatalog gained create_namespace/create_table (spec wire
      shapes; tolerant decode). Remote CREATE went from manual pyiceberg
      helper to SQL.
  - slice 28-prep — DONE 2026-11-20 (DECISION + core patch): managed
    DDL UX decided by thought experiment over three alternatives
    (one-statement CREATE ... WITH vs multi-statement attach flow vs
    wrapper functions) under 5-year scenarios (pg_dump/restore, ORM/
    migrations, multi-AM ecosystem, upstreamability): ONE-STATEMENT
    CREATE ... USING lakehouse WITH (...) wins; attach/create_remote
    stay as internals. [core-allowlist] TableAmRoutine.
    relation_reloptions hook + table_am_reloptions() dispatch in
    reloptions.c (extract path) + tablecmds.c (CREATE/ALTER validate
    path, AM resolved from stmt->accessMethod or
    default_table_access_method). No catversion impact. Our AM parses
    endpoint/warehouse/token/table/s3_*/snapshot_id into a fixed-order
    NUL-packed bytea (rd_options); identity resolves WITH-options
    FIRST, attach row second — attach_table optional when WITH carries
    the identity. Regress: WITH-options scan fail-fast, unknown-key +
    missing-table rejections (22023), NULL-options guard (segfault
    caught live). Upstream regress suite green on the patch. Upstream
    patch + proposal being filed from the core commit.
  - slice 28 — UPDATE/DELETE as COW (rewrite affected files, reuse
    slice-20 delete reading for concurrent reads), TRUNCATE (empty
    snapshot commit); regress vs heap parity.
  - slice 29 — MERGE + M2 gate: Trino reads a table WE wrote (the
    compose trino service is already in place for exactly this);
    smoke ceremony + tag milestone/m2.
  - Principle to honor throughout: one catalog, one visibility
    (00-goals #3) — managed tables are ordinary pg_class rows; the
    remote catalog is source of truth; local reconciliation via
    metadata_ttl.
- Core-allowlist patches so far: meson_options.txt,
  src/backend/access/meson.build, root Makefile (each committed with
  `[core-allowlist]` rationale).

## First actions for the next session (M1)

1. Read `specs/lakehouse/README.md` → `00-goals.md` → `01-architecture.md`;
   naming amendment notes in RULES §4 / 01 D1-D2.
2. Verify CI green on GitHub Actions (datalake-ci on lakehouse-dev).
3. Start M1 per `12-roadmap.md`: REST catalog client + metadata model in
   `pgdatalake-core`, `lakehouse_fdw` read path, S3 fixtures in tests.
   TDD per RULES §8; weekly upstream sync per RULES §2 before starting.

## Gotchas found while exploring the tree

- `cc`/`python3` in PATH resolve to anaconda/conda-forge toolchains; conda gcc
  has its own sysroot (no readline headers). Build with `CC=/usr/bin/gcc`.
  meson picks anaconda python — works, but mind version-sensitive tooling.
- meson setup FAILS if autoconf configure artifacts exist in the source tree
  (GNUmakefile conflict check) — stay meson-only, or distclean first.
- `pgindent` needs `pg_bsd_indent` in PATH + perltidy; pg_bsd_indent can be
  built manually (gcc -I src/include -I build/src/include
  src/tools/pg_bsd_indent/*.c build/src/port/libpgport.a
  build/src/common/libpgcommon.a). perltidy not yet installed.
- `pg_regress --inputdir <dir>` expects `<dir>/sql/` and `<dir>/expected/`
  subdirs; psql column headers are CENTERED — take expected output from the
  results file after eyeballing correctness.
- **meson test runs the INSTALLED binaries** (`tmp_install`) — after changing
  backend C code you MUST `meson install --destdir build/tmp_install` (and
  rerun `--suite setup` after a catversion bump) or the suite silently tests
  old code; this cost one CI cycle on slice 19 (stale expected file with a
  pre-fix error message). `make lakehouse-check` now installs first.
- Upstream `pg_mod_args`/`backend_mod_code` are defined *after*
  `subdir('access')`; `src/backend/access/lakehouse/meson.build` assembles
  module args from earlier-defined components (see file comment).
- meson cannot `link_with` a custom_target: link the static lib via
  `link_args` + `link_depends` (see lakehouse/meson.build).
- `#[no_mangle]` is an unsafe attribute: crate uses `deny(unsafe_code)` with
  `allow` only in `ffi.rs` (RULES §4).
- Fixture creds are fake (`lakehouse-test`/`lakehouse-test-password` etc.);
  never use real cloud credentials outside OIDC-federated CI (RULES §6).

## Rules

`specs/lakehouse/RULES.md` is binding: allowlist-limited core edits, branch
layout, style, secrets, TDD (§8), smoke-test ceremony (§9). Follow it.
  - GPT-6 review fixes — DONE 2026-11-20: (1) CORRECTNESS: rd_options
    now carries a valid StdRdOptions prefix (autovacuum's
    extractRelOptions copy can't read past our buffer) with identity as
    a NUL-packed tail blob; standard keys (fillfactor, autovacuum)
    parse via default_reloptions. (2) SECURITY: token/s3 keys are no
    longer accepted in WITH-options (rejected with a hint); they merge
    from the attach row unconditionally. (3) merge semantics: WITH
    identity wins, attach row supplies credentials + any NULL fields.
    Live-verified (WITH-options create_remote + INSERT + count with
    attach-row credentials); lakehouse suite + clippy green. REMAINING
    from the triage: credential storage in the attach TABLE itself is
    still dumpable — full fix = user-mapping/server-based credentials
    (doc 09); SET ACCESS METHOD + matview/partitioned AM-resolution
    tests; CF #5631 v14 consumer evaluation.
  - CF #5631 PORT — DONE 2026-11-20 (branch cf5631-port, all suites
    green + live smoke): the fork now runs Dunstan's amoptions contract
    (CF #5631 v13/14): TableAmRoutine.amoptions + has_std_options_prefix,
    table_reloptions/RelationGetTableAmOptions dispatch, dummy_table_am
    upstream module, our scratch hook removed. Our lakehouse AM sets
    .amoptions (same parse semantics; StdRdOptions prefix + identity
    tail; credentials from attach row only). Port battle scars: a
    splice over-deleted DefineRelation's transformRelOptions block
    (caught live: pg_class.reloptions stored NULL; restored with
    Dunstan's switch). Live smoke green: WITH-options + attach creds ->
    create_remote -> INSERT -> count = 1. Port decisions to carry into
    the CF #5631 review reply: matview dispatch (our fix; check if
    Dunstan covers), our destination-AM SET ACCESS METHOD validation
    (superseded by his deferValidation flow — reconcile semantics),
    preset helper heap_reloptions_for_am (dropped in port; propose
    upstream or re-add per review), and the security finding
    (credentials never in options) as review input.
  - 13-implementation-review Blocker #1 — PARTIALLY FIXED 2026-11-20
    (Rust core, 66 cargo tests): (a) data files now carry a per-flush
    UUID in the key (write_file returns WrittenFile{key, record_count,
    file_size_in_bytes} — no GET-based measurement, no name-parsing);
    equal-size batches from separate sessions can no longer overwrite
    each other (acceptance: A-then-B test — pinned read of A yields A,
    current yields A+B, A's bytes intact). (b) write_snapshot carries
    the BASE snapshot's live manifests (data AND delete, content field
    now parsed on ManifestListEntry) into the child's manifest list —
    the child no longer drops the parent's history. REMAINING from
    blocker #1: create-only PUT semantics (object-store conditional
    write), two-writer concurrency, externally-written base with
    deletes, independent-reader verification. Blockers #2-#8 queued in
    review order.
  - 13-implementation-review Blocker #2 — FIXED 2026-11-20 (Rust core,
    66 cargo tests + upstream regress + live smoke): commit_append now
    REBUILDS the commit per attempt against verified current metadata —
    (a) requirement binds the ORIGINAL table uuid (a replacement table
    aborts server-side, never adopted); (b) parent/sequence/carried
    manifests re-derived from the FRESH loadTable (fetching the
    referenced metadata file when the catalog omits in-band metadata);
    (c) collision-resistant positive snapshot ids (time<<20 | uuid
    entropy) replacing seq*1000+millis; (d) plan closures return
    Result — assembly errors abort without retry, only
    CommitFailedException retries; (e) write_table_open gates: v2
    format only, unpartitioned only (writer capability limits, per
    review). Obsolete seq-derived snapshot-id plumbing removed. NEXT
    blockers: #3 txn boundary, #4 predicate serialization (2^53
    pruning bug), #5 delete schema binding, #6 credential authority,
    #7 per-scan queues, #8 type statuses.
  - 13-implementation-review Blocker #4 — PARTIALLY FIXED 2026-11-20
    (69 cargo tests + C-side, suites green): RUST: bounds/coercion are
    exact i64 for Int/Long/Timestamp/Timestamptz (BoundVal::Int);
    integer-vs-float compares exactly only within f64's integer
    continuum (|v| <= 2^53), beyond it the file is conservatively
    KEPT; tests: the review's reproduced 2^53 case (Gt/Eq above 2^53
    no longer pruned), below-2^53 pruning still prunes, float-literal
    cross-type keeps. C SIDE (fdw.c TranslateQual): DATE pushed
    days-since-2000 and TIMESTAMP/TZ micros-since-2000 (epoch bug:
    every temporal predicate mis-pruned by 10957 days / 946684800000000
    micros) -> converted to Iceberg epoch; float pushdown now uses
    float4out/float8out shortest round-trip (not %g) with
    NaN/Inf -> no pushdown; escape buffer 2x (the strlen+3 buffer
    overflowed on backslash-heavy values). REMAINING #4: operator
    allowlist (same-named user operators, collation), identity
    partition matching by field ID, unknown-partition-spec fallback,
    missing-schema continue, JSON-injection of identifiers (typed
    representation refactor).
  - 13-implementation-review Blocker #6 — PARTIALLY FIXED 2026-11-20
    (managed side; suites green + live smoke): credential authority now
    follows the postgres_fdw model — lakehouse.attach_table takes
    (regclass, identity, SERVER NAME); endpoint/warehouse/s3_endpoint
    live on the FOREIGN SERVER options; token/s3 keys live in USER
    MAPPINGS (per-user, ACL-controlled, single rotation point); the
    attach row stores only (relid, identity, serverid, snapshot_id) —
    NO credential columns; WITH-options credential keys already
    rejected. ExtractManagedIdentity resolves server + GetUserMapping
    per user. create_remote gained an ownership check
    (ERRCODE_INSUFFICIENT_PRIVILEGE). drop-gc trigger is SECURITY
    DEFINER with pinned search_path (ordinary owners can clean their
    rows). Live-verified: server+mapping -> attach -> create_remote ->
    INSERT -> count. REMAINING #6 (FDW side + hardening): fdw wrapper
    validator + ExtractOptions literal-credential removal for FOREIGN
    tables, scan_files ACL, transport policy (scheme/origin/redirect,
    redaction), OAuth refresh, sentinel-string dump verification.
  - 13-implementation-review Blocker #5 (metadata wire) — FIXED
    2026-11-20 (72 cargo tests): the wire misspellings the review
    called out are real and now fixed — TableMetadata reads the spec
    name default-spec-id (legacy default-partition-spec-id tolerated
    via serde alias; every real table's default spec was silently None
    and commits fell back to spec zero), and map types parse BOTH
    key/value (spec, pyiceberg alias-confirmed) and keys/values
    (legacy) while serializing the spec members. TDD: spec-shaped
    metadata with nonzero default-spec-id + map column loads; map
    serializes spec members; legacy tolerance test. REMAINING #5:
    equality_ids-driven equality deletes, position-delete sequence/
    partition applicability, empty-projection open_all branch,
    delete-specific pruning rule, map/list nested field IDs.
  - 13-implementation-review Blocker #5 (equality binding) — FIXED
    2026-11-20 (73 cargo tests): load_row_deletes binds equality-delete
    key columns to the manifest's equality_ids via the TABLE schema
    (id -> name) instead of "every column in the delete file" — an
    extra non-key column no longer prevents a valid delete from
    matching. scan_table returns the schema; an unresolvable
    equality_id is a loud Decode error (never a silently partial key);
    manifests without equality_ids keep the all-columns fallback.
    Acceptance test: delete file with key id + extra "note" column
    kills only the keyed row; unresolvable id errors. REMAINING #5:
    position-delete sequence/partition applicability, empty-projection
    open_all branch, delete-specific pruning rule, map/list nested
    field IDs.
  - 13-implementation-review Blocker #3 — FIXED (narrow contract)
    2026-11-20 (live-verified): (a) SUBTRANSACTION ROLLBACK discards
    staged rows — rows are staged C-side ONLY (per-row
    SubTransactionId); SUBXACT_EVENT_ABORT_SUB prunes rows owned by the
    aborted subxact tree; rows reach the Rust parquet accumulator at
    PRE-COMMIT, AFTER pruning — the deferred-push design. (The first
    attempt pushed at INSERT time and leaked savepoint-rolled-back rows
    into the committed snapshot; caught live and redesigned.)
    (b) PREPARE is rejected with pending managed writes at
    XACT_EVENT_PRE_PREPARE (FEATURE_NOT_SUPPORTED — the AM's recovery
    protocol does not support crash-safe prepared remote commits yet).
    (c) Mixed multi-table commits stay per-relation (documented, not
    atomic); savepoint + commit verified live: INSERT 50 kept, INSERT
    51 rolled back to savepoint, count = 1. PREPARE error path leaves
    the table usable. REMAINING #3: crash-recovery/reconciliation
    protocol, unknown-outcome verification, operator procedures
    (doc 07 hardening). REMAINING overall per the review: #5 tail
    (position-delete applicability, empty-projection branch, nested
    field IDs, delete-specific pruning), #4 tail (typed representation,
    operator allowlist), #6 FDW side, #7, #8, blocker #1 tail.
  - 13-implementation-review Blocker #5 tail (part) — FIXED 2026-11-20
    (75 cargo tests): (a) POSITION-DELETE SEQUENCE APPLICABILITY:
    positions_by_file now maps path -> (delete seq -> positions);
    for_task applies a position delete only when its sequence >= the
    data file's sequence (v2 applicability) — path/position alone
    over-applied when a path was reused by a later write. (b)
    EMPTY-PROJECTION BRANCH: rows_open no longer routes count(*)-style
    scans through open_all (which silently dropped position deletes) —
    always open_with_deletes, which skips deleted absolute rows even
    with zero projected columns. (c) PARTITIONED FLAG: partition
    is_some() conflated the empty record (our own unpartitioned files)
    with a partitioned spec — equality deletes on our own writes were
    wrongly rejected; empty object / null now mean unpartitioned.
    TDD: sequence applicability (data seq > delete seq not applied),
    empty-projection position-delete skip, partitioned-flag via the
    eq-delete binding test. REMAINING #5: delete-specific pruning rule,
    map/list nested field IDs, manifest inheritance with null
    snapshot IDs.
  - 13-implementation-review Blocker #5 depth — FIXED 2026-11-20
    afba7ef29e7 (78 cargo tests): (a) DELETE-SPECIFIC PRUNING: content
    routing now happens BEFORE the predicate block — data predicates
    (partition + column bounds) prune DATA files only; delete files
    prune by partition applicability only (a delete file's bounds are
    over its keys, not the surviving rows; position deletes carry no
    key bounds). Previously a delete file whose min/max fell outside
    the query bounds was eliminated from delete_tasks and its
    deletions silently lost. (b) MANIFEST INHERITANCE: a NULL entry
    snapshot_id inherits the enclosing manifest's added-snapshot-id
    Avro container metadata (older writers); null with no metadata is
    a loud Decode error, never a silent 0. (c) NESTED FIELD IDS:
    ListType/MapType retain element-id/key-id/value-id and
    element-required/value-required; IDs required on the wire (loud
    parse failure — columns bind by ID through schema evolution),
    *-required defaults true per spec. Serialization emits the full
    spec member set. TDD: delete_tasks_survive_data_bounds_pruning,
    null_entry_snapshot_id_inherits_manifest_added_snapshot,
    nested_types_keep_field_ids_and_requiredness (all written
    failing first). Spec: 06-execution.md 13-review #5 amendment.
    REMAINING #5: NONE — blocker #5 CLOSED pending independent-reader
    acceptance (external-reader survivor-ID matrix from the review's
    acceptance list, lands with M2 #29 ceremony). REMAINING overall:
    #4 tail (typed representation, operator allowlist), #6 FDW side,
    #7, #8, blocker #1 tail.
  - 13-implementation-review Blocker #4 — CLOSED 2026-11-20 (two
    commits; earlier pieces landed pre-summary: exact BoundVal::Int
    2^53-conservative pruning, epoch-correct date/timestamptz values,
    float4out/float8out shortest round-trip, NaN/Inf no-pushdown,
    buffer-safe escapes).
    (a) PLANNER (5f3ad99ea2d, 81 cargo tests, TDD): unknown partition
    spec = loud decode error (old silent default-spec fallback could
    prune against the WRONG spec after evolution; tolerance kept: a
    table with NO partition-specs at all resolves spec-0 to the
    implicit empty spec, provably cannot mis-prune); missing current
    schema with a predicate = loud error (old per-file continue
    discarded EVERY file -> plausible empty result); identity-partition
    matching proves spec field source-id == predicate column's schema
    field ID (name reuse across drop+re-add must not compare the new
    column against the old column's partition member); inconclusive
    keeps the file.
    (b) FDW (ea62dfd2653, TDD LIVE against Lakekeeper+S3 fixtures,
    ground truth via identical heap tables, two disjoint-range files
    with real pyiceberg bounds): operator allowlist = pg_catalog
    namespaces only (same-named user operator pdtest.< pushed as
    byte-lt: ground truth {Banana} -> returned 0 rows, now stays
    local); ordering pushes only under byte-ordered collations (C) —
    ICU en-US column lt 'B': ground truth 2 rows -> returned 0, now
    stays local; eq pushes only under deterministic collations
    (und-u-ks-level1 ci eq 'APPLE': ground truth {apple} -> 0, now
    local); growable StringInfo JSON encoder escapes control chars
    (newline constant previously failed the Rust serde decode
    outright) + encodes field names; default branch returns NULL —
    no arbitrary user output functions called during eligibility
    (only text/varchar/name push; bpchar excluded: trailing-blank-
    insensitive eq is not byte eq). ALL acceptance queries now equal
    heap ground truth; deterministic-eq and C-ordered pushdowns still
    prune; 2^53 exact. Spec: 06-execution.md amendments (#4 planner,
    #4 FDW + the corrected never-correctness claim).
    FOLLOW-UP (perf, not correctness): our own manifest writer emits
    empty lower/upper bounds — bounds pruning is inert on PG-written
    tables until the writer collects parquet stats (WrittenFile has
    no stats today). Landing stats unlocks the pushdown equivalence
    acceptance matrix on our own tables too.
    REMAINING overall per the review: #6 FDW side (wrapper validator,
    foreign-table literal-credential removal, transport policy,
    OAuth refresh), #7 parallel per-scan queues, #8 type-boundary
    statuses, #1 tail (create-only PUTs, two-writer concurrency,
    independent-reader verification).
  - 13-implementation-review Blocker #6 (FDW side) — FIXED 2026-11-20
    371573da8b3 (regress fdw_auth green; live-verified on the
    /tmp/live-fdw fixture instance): (a) OPTION AUTHORITY: one legal
    home per option — SERVER endpoint/warehouse/s3_endpoint, USER
    MAPPING token/s3 keys, FOREIGN TABLE table/snapshot_id — enforced
    at DDL by the new lakehouse_fdw_validator (canonical lakehouse_fdw
    wrapper ships wired to it) and AGAIN on use by ExtractOptions, so
    legacy pre-validator tables with table-level credentials error
    instead of silently using them (live: re-added s3_access_key ->
    "option ... belongs on user mappings"). The table-level
    s3_endpoint override (credential/destination repurposing) is
    rejected both ways. Foreign tables now resolve credentials from
    the mapping of the INVOKING user; missing mapping = loud plan-time
    error. (b) FUNCTION HARDENING: scan_files (caller-chosen endpoint
    + creds = arbitrary egress) and create_remote (external DDL,
    C-side ownership check kept) revoked from PUBLIC. (c) REGRESS
    fdw_auth: validator rejections (unknown/misplaced x server/table/
    mapping), sentinel-token catalog-output check, on-use legacy
    rejection, PUBLIC revocation, unrelated-DROP non-interference by
    an ordinary owner. ALL prior pushdown acceptance queries re-run
    green on mapping-only creds. Fixture expectations regenerated
    (fdw.sql, time_travel.sql moved to mapping creds). Spec:
    09-security.md FDW option authority section; managed interim-state
    marked resolved. REMAINING #6 (Rust transport): shared scheme/
    origin/bucket/path policy per hop (catalog redirects + delegated
    locations), redaction of URL userinfo/query + remote bodies,
    explicit OAuth config resolution + refresh-token invalidation,
    type-conflict responses instead of "409" string search, ambient
    cloud credentials opt-in. Then #7, #8, #1 tail.
  - 13-implementation-review Blocker #6 (transport) — FIXED 2026-11-20
    f8336a8746e (85 cargo tests; live acceptance re-run green on the
    fixture stack): (a) TABLE-ROOT SCOPE GATE: plan_scan checks every
    hop (manifest list, manifests, data/delete paths) against the
    table location — same scheme/bucket, segment-aware prefix
    (s3://b/a does not admit s3://b/ab); violations are loud decode
    errors. (b) file:// stores DEFAULT-DENY with a cfg(test)-only
    opt-in — the shipped binary structurally cannot open
    catalog-supplied local paths (monotonic global flag, gate tested
    directly on the constructor so parallel tests never race).
    (c) AMBIENT CREDENTIALS REMOVED (stricter than the review's
    opt-in wording): static S3 keys are REQUIRED — missing keys are a
    loud config error pointing at the user mapping, never an IMDS
    probe (the 20s retry storms observed live pre-fix). (d) plain
    HTTP only for explicit http:// endpoints; absent endpoint = AWS =
    TLS-only. Fixture manifests relocated under the table location
    (real catalog layout). Spec: 04-storage.md §7 transport policy.
    REMAINING #6 (REST client): URL userinfo/query redaction +
    response-body truncation in errors, same-origin redirect policy,
    explicit OAuth config resolution + refresh invalidation,
    type-conflict responses instead of "409" string search. Then #7,
    #8, #1 tail; M2 #28/#29.
  - 13-implementation-review Blocker #6 (REST client) — FIXED
    2026-11-20 571c4085806 (85 cargo tests; live typed-conflict
    verified): (a) REDACTION: redact_url masks userinfo + query values
    in every RestError site (rest.rs + commit.rs). (b) REDIRECTS:
    same-origin-per-hop policy — cross-origin catalog redirects fail
    loudly with a redacted message (mock 302 test). (c) OAUTH LOUD:
    TokenProvider::token() -> Result — no-cache fetch failures error
    the request (never an empty bearer); stale serving bounded by the
    hard TTL (expired + failed refresh = loud error). (d) TYPED
    CONFLICTS: RestError::Conflict -> StorageError::Conflict -> FFI
    err_kind out-param -> tableam.c branches on kind; the "409"
    string search in create_remote is GONE (and createTable now maps
    409 to Conflict at all — live: create_remote returns "exists"
    via the typed path). Spec: 04-storage.md §7 updated from
    follow-up to implemented. BLOCKER #6 NOW FULLY CLOSED.
    REMAINING overall: #7 parallel per-scan queues, #8 type-boundary
    statuses, #1 tail (two-writer concurrency, independent-reader
    verification); M2 #28 UPDATE/DELETE COW, #29 MERGE + ceremony.
  - 13-implementation-review Blocker #7 — FIXED 2026-11-20 30c887d12ae
    (live acceptance matrix; regress + cargo green): (a) PER-NODE
    QUEUES: the process-global lakehouse_shared_state is gone — each
    executor node carries LakehouseExecState.shared; hooks attach to
    the node's own state; Shutdown clears only its own. (b) STABLE
    TASK MAPPING: leader's Begin resolves the concrete snapshot
    (per-execution = plancache-fresh boundary; refs/"current" resolve
    ONCE there), InitializeDSM records it before workers launch, and
    each worker RE-PINS its session to that id when its own
    resolution differs (pg_datalake_scan_snapshot_id accessor added).
    Concurrent commits can no longer make task index N mean different
    files per process. (c) PARTIAL PATH gated on consider_parallel.
    CAUGHT PRE-COMMIT by the acceptance matrix: Begin runs before the
    DSM hooks in workers TOO (children init before the Gather parent —
    the "InitializeWorker runs before Begin" assumption was wrong), so
    the first per-node attempt left workers unshared and
    leader-participation=off duplicated rows 4x; fixed by attaching in
    the hooks + re-pinning. Live: serial == parallel(2 workers) ==
    leader-off multisets across self-join / two distinct scans /
    serial×parallel mix / correlated rescan; exactly-once verified.
    Remaining #7 notes: catalog-advance barrier demo needs
    injection-point test infrastructure (design is structurally
    benign: worker detects id mismatch and re-pins). REMAINING
    overall: #8 type-boundary statuses, #1 tail (two-writer
    concurrency, independent-reader verification); M2 #28/#29.
  - 13-implementation-review Blocker #8a (read path) — FIXED
    2026-11-20 d25b89f3f63 (88 cargo tests; regress green; live reads
    verified): (a) ROW/EOF/ERROR status on pg_datalake_rows_next — a
    caught panic used to return false = EOF (silent result-set
    truncation); Iterate loops (FDW + TableAM) abort with
    ERRCODE_DATA_EXCEPTION + bounded diagnostic. (b) Open-time Arrow
    type validation over the FULL read set (eq-delete columns too) —
    unsupported types used to surface as per-cell SQL NULL (fabricated
    empty data); now a loud Config error before any row. (c)
    LargeUtf8/LargeBinary decode with their own array types (the
    shared downcast silently NULLed them). (d) Interior NUL in text =
    ERROR (was silently EMPTY). (e) write_push/flush/commit carry the
    catch_unwind boundary (shared panic_message helper). Spec:
    05-types.md #8a section. REMAINING #8b (write path): name-Datum
    routing, dropped-attribute schema/row mismatch, decimal scale
    reconciliation, whole-row validation before builder mutation,
    counted projection fields (vs comma CSV), typmod pass-through,
    bytea_output independence, fixed[16]-vs-UUID disambiguation by
    iceberg field type. Then #1 tail; M2 #28/#29.
  - 13-implementation-review Blocker #8b (write path) — FIXED
    2026-11-20 bc98a8c3794 (90 cargo tests; regress green; live +
    independent pyiceberg verification): name via nameout (NameData*
    is NOT varlena text — textout read garbage); bpchar via
    bpcharout; bytea hex-encodes DIRECTLY (byteaout followed the
    bytea_output GUC — escape mode silently corrupted stored bytes);
    decimal text reconciles to the column's scale (was verbatim
    unscaled: 123.45 into scale-3 read 12.345; extra fractional
    digits = loud error, precision checked); push() two-passes
    (whole-row validation before ANY builder mutation — a mid-row
    failure used to misalign every later row in the batch); dropped
    attributes skipped in rows (schema omits them — mismatch broke
    managed INSERT on altered tables); reader projection = counted
    JSON array (commas in column names split wrongly); atttypmod
    passed to input functions (was -1). Live: name/varchar/bytea/
    numeric(10,3) table under bytea_output=escape — PG + pyiceberg
    independently confirm exact bytes/decimals/names. NOTE: meson
    install raced the custom-target regeneration for the live
    instance — after rebuilds, copy lakehouse.so into tmp_install
    directly. BLOCKER #8 FULLY CLOSED (fixed[16]-vs-UUID
    disambiguation remains noted in HANDOFF as an interop nicety;
    both render canonical text today). REMAINING overall: #1 tail
    (two-writer concurrency, independent-reader verification);
    M2 #28 UPDATE/DELETE COW, #29 MERGE + ceremony.
  - M2 slice 28 (UPDATE/DELETE COW) — DONE 2026-11-20 (core ada a856/f8c639c/
    b70af08/fb63861/2697e1e + tableam C commit; live-verified vs pyiceberg):
    TOMBSTONE model — scan encodes TID (task, rowidx; block=fanout-encoded,
    offset=rowidx&0x7FF+1), tuple_delete/tuple_update record (file,rowidx)
    in the per-txn per-rel entry (per-row subxact ids: savepoint rollback
    prunes tombstones; the file record drops when its last tombstone rolls
    back). PRE-COMMIT: rewrite pass re-reads each tombstoned file FROM THE
    BASE SNAPSHOT via pg_datalake_rows_open_path (write-session creds,
    table-root scope gate), survivors re-encoded exactly like staged rows
    (input fns + append_cell_json), then ONE overwrite commit: rewritten +
    staged files ADDED, originals DELETED, summary operation=overwrite.
    tuple_fetch_row_version implemented (the executor calls it on EVERY
    UPDATE to build the new tuple) — point read of the encoded position.
    tuple_lock still unsupported (clean error, M3). Staged rows carry
    invalid tids; deleting/updating them = loud error (same-statement
    overlay rows are unaddressable, matching FDW practice).
    INTEROP (caught live): pyiceberg 0.12 plans discard_deleted and does
    NOT apply cross-manifest deletions — DELETED entries in the NEW
    manifest resurrected overwritten files for the independent reader.
    FIX: deletions carry via MANIFEST REWRITE (Java/Trino convention):
    carried manifests touching a deleted path are re-serialized with the
    entry flipped to DELETED (original snapshot_id/seq/metrics kept),
    survivors to EXISTING; list serializer no longer hardcodes
    existing/deleted counts to 0; deletion-only commits write NO new data
    manifest. Liveness: every retry re-verifies deleted paths are live in
    the fresh base via plan_scan — a concurrent rewrite aborts loudly
    (lost-update protection; unit-tested abort-before-commit).
    BUGS FIXED EN ROUTE (all live-caught): repalloc(NULL) on first
    tombstone (segfault); own-writes overlay not served after files drain
    (EOF path skipped staged rows); entry->tupdesc/opts allocated in the
    EXECUTOR context — freed at ExecutorEnd, read at PRE-COMMIT
    (intermittent garbage palloc sizes + segfaults; valgrind caught reads
    of an ExecutorEnd-freed block; fix: entire entry init in the txn
    mcxt). OPERATIONAL: NEVER cp over lakehouse.so of a RUNNING server
    (shared_preload_libraries='lakehouse' — the startup process maps it
    too; hot-swap produced random segfaults in unrelated processes);
    stop -> copy -> start. Managed time travel (FOR ... AS OF on AM
    scans) is NOT yet wired — selectors remain FDW-only (follow-up
    noted). Live acceptance: mixed INSERT/UPDATE/DELETE txn with in-txn
    read-your-writes; pyiceberg agreement after commit; subxact rollback
    pruning; 12+8 stress txns clean under gdb + native. REMAINING: #29
    MERGE + ceremony (two-writer + independent reader = the #1 tail).
  - M2 slice 29 (MERGE + ceremony) — DONE 2026-11-20 (live, NO new code for
    MERGE): MERGE INTO decomposes through the slice-28 DML contract —
    matched UPDATE/DELETE via tuple_fetch_row_version + tombstones, NOT
    MATCHED insert via staging, one overwrite commit at PRE-COMMIT. All
    branch kinds live-verified vs pyiceberg (matched UPDATE, NOT MATCHED
    INSERT, matched DELETE, NOT MATCHED BY SOURCE delete). CEREMONY (the
    #1 tail) CLOSED — two-writer interleaves live vs Lakekeeper/SeaweedFS
    with pyiceberg 0.12 as writer #2 + independent reader: (A) foreign
    commit then PG commit = carried forward, agree; (B) PG txn open across
    foreign commit = 409 retry re-plans fresh base, agree; (C) PG tombstone
    vs foreign COW rewrite = overwrite liveness check ABORTS loudly,
    rollback clean, agree after. pyiceberg writing notes: static fixture
    S3 keys are read-only — writes need Lakekeeper's VENDED credentials
    (load_catalog with ONLY uri+warehouse; pyiceberg sends the
    vended-credentials delegation header; Lakekeeper vends remote signing
    via S3V4RestSigner; SeaweedFS PUTs are intermittently flaky — retry).
    v3 pass landed first (266fc05de88, doc 14): scan_table rejects v3
    reads loudly until DV slice. BLOCKER #1 TAIL CLOSED. M2 REMAINING:
    none — M2 slices 24-29 all done. Next: read-side slice V1 (DV apply,
    doc 14) or M3 slice 24 (columnar batch reads, THE perf fix).
  - V1 slice (doc 14) — DONE 2026-11-20 (puffin.rs + scan routing + gate
    lift, TDD): v3 DELETION VECTORS read/apply. Fixture = the Apache
    Iceberg JAVA reference implementation (1.10.0 HadoopTables, JDK 23
    needs -Djava.security.manager=allow for Hadoop; maven project at
    /tmp/v3fixture, NOT in-repo) writing a v3 table + deletion-vector-v1
    puffin; pyiceberg 0.12 CANNOT write DVs but its DV DECODER verified
    the blob (positions [2,4]). Fixture checked in at
    pgdatalake-core/tests/fixtures/v3_dv_table (HadoopTables writes BARE
    local paths — parse_location now accepts scheme-less absolute paths
    as Local, same default-deny + scope gates). WIRE NOTES: DV blob
    framing = [len BE][DV1\n][data][crc BE] where len covers magic+data
    only; data = [count LE64][key LE32][roaring portable]*; row ids =
    key*2^32 + pos; DV manifests = content=position-deletes +
    file-format PUFFIN (uppercase from Java — routing is
    case-insensitive); DVs fold into position-deletes with an
    i64::MAX sentinel sequence (always applicable). pyiceberg 0.12
    local scan planning does NOT apply DVs (read all 6 rows) — our
    reader is the applying engine. V0 read gate LIFTED (v3 tables
    scan; the old gate test rewritten). E2E: Java fixture → plan →
    DV decode → {1,2,4,6}. 100 cargo tests green. V2 remainder:
    pyiceberg format_version=3 COW tables + Trino gate.
  - V2 slice (doc 14) — DONE 2026-11-20: TRINO 484 writes v3 DVs (its
    v3 DELETE) and OUR reader applies them (e2e fixture
    tests/fixtures/v3_dv_trino, dv_trino_fixture_tests: Trino deleted
    ids 3,5 -> we read {1,2,4}). pyiceberg leg closed: pyiceberg 0.12
    CANNOT write v3 at all (upstream #1551) — Java + Trino are the two
    real v3 writers, both verified. WIRE NOTES: Trino manifests are
    COMPRESSED avro (byte-patching impossible — the test re-serializes
    manifests via build_manifest_list_bytes/build_manifest_bytes_entries
    with remapped paths); Trino validates DV CRC over magic+data and
    locates the blob via the manifest's content-offset/
    content-size-in-snapshot fields (populate BOTH in hand-rolled DV
    writers; pyiceberg's property lookup is lenient); Trino table
    registration via Lakekeeper register + its location must be a valid
    s3:// sublocation (Java s3a:// rejected). Trino writes DVs on v3
    DELETE — verified self-consistent, then decoded by us + pyiceberg.
    Fixture gen: docker trino CLI (CREATE TABLE WITH format_version=3,
    INSERT, DELETE). V3 (DV write mode) remains future; M3 slice 24
    columnar reads is the next major slice.
  - M3-R1 slice — DONE 2026-11-20 (typed batch read ABI, TDD + live):
    13-review perf #3 scan-reader half LANDED. pg_datalake_rows_batch_next
    (Rust) materializes one arrow batch at a time: typed views (Bool u8 /
    Int64 / Float64 / TimestampUs / Date32 buffers; zero-copy Text/Bytes
    spans; Rendered spans via cell_from_arrow for date/time/decimal/uuid),
    live-row list with deletes+DVs still applied in Rust, byte-per-row
    null map. batch_fill.c maps (kind, atttypid, typmod) -> exact fast
    Datum constructors; unprovable combinations (bpchar/name/timestamp
    precision<6/numeric/float4) fall back via
    pg_datalake_rows_batch_cell_text + InputFunctionCall — byte-identical
    to the old renderer. fdw.c Iterate + tableam.c scan_getnextslot
    rewired; per-row CString render + InputFunctionCall GONE from both
    hot paths. MEASURED (500Kx4 managed table): aggregate 465 -> 145 ms
    (~3.2x), full materialize 0.69 -> 0.31 s, FDW wall 0.51 -> 0.18 s.
    TDD: 3 new ffi tests (multitype+nulls+position-delete, multi-batch
    advance, interior-NUL loud) + start_abs anchor; 104 cargo green; 6/6
    regress. LIVE: COW UPDATE/DELETE multi-batch round-trips verified
    against pyiceberg (per-row values + row presence).
    **INCIDENT (never-misread violated by slice 28):** first cut exposed
    that slice-28's TID/tombstone identity used the LIVE-ROW ORDINAL
    while the batch live list is batch-LOCAL — rows past the first
    arrow batch (1024 rows) tombstoned the WRONG ROWS silently: victim
    updates vanished, unintended rows dropped at commit (caught live:
    UPDATE id=2500 recorded tombstone row 451; a 500K-row table lost a
    staged update). Fix: PgDatalakeRowBatch.start_abs; consumers split
    local (buffer index) vs absolute (identity) by construction; ABI
    test asserts start_abs. Tables written between e986095cc7c (slice
    28) and this fix must be REGENERATED (dev fixtures only: t28, t28b,
    t29, bench_rows, vg_bench show lost/misapplied DML). Next: writer
    min/max bounds, or spec 15 (staged-write WAL + background
    compaction + caching, spec-only per user direction).
  - M3-R2 slice — DONE 2026-11-20 (writer column stats, TDD + live +
    pyiceberg): pruning no longer inert on PG-written tables. writer.rs
    collects per-column manifest metrics in write_file: value/null
    counts from the arrow arrays, min/max bounds serialized per the
    Iceberg single-value table (LE i32/i64/f32/f64, UTF-8 bytes for
    string) keyed by FIELD ID, column_sizes from the parquet footer
    (thrift total_compressed_size summed per column chunk). NaNs
    excluded from float bounds (spec rule); all-null columns omit
    bounds (conservative keep). Bounds written for int/long/double/
    float/string/date/time/timestamp; binary/decimal/uuid/bool omit
    (read-side prune decoder doesn't compare them yet — conservative).
    The existing NewDataFile->manifest plumbing carried them unchanged.
    TESTS: 2 writer unit tests (byte-exact bounds, null/NaN handling) +
    e2e ffi_write_commit_stats_prune_predicate (commit via mock ->
    manifest entry bounds asserted at WIRE level -> id>1000 prunes to
    0 tasks, full scan 5 rows). 107 cargo green, clippy -D warnings
    clean. LIVE: two-transaction table — EXPLAIN shows files examined
    2 / pruned 1 / tasks 1; pyiceberg reads our bounds (LE 1000/1010,
    counts 11/0). NEXT: P0 (ranged reads + block cache, spec 15) or
    M3 remainder; writer-bounds item CLOSED.
  - P2 slice — DONE 2026-11-21 (extension-defined GUCs, TDD): the
    lakehouse.* GUC family registered via DefineCustom*Variable in
    _PG_init — the extension seam; the guc_tables.c allowlist entry
    RETIRED (RULES §3 note) before first use. GUCs: write_mode
    (enum cow/staged, USERSET, byte-exact rejection message + "HINT:
    Available values: cow, staged."), target_file_size (int,
    GUC_UNIT_KB, min 128MB, consumed by P1 rollover), publish_max_lag
    (int, GUC_UNIT_S, SUSET), cache_max_bytes (int, GUC_UNIT_KB,
    USERSET). GOTCHAS (cost real debugging): GUC_UNIT_MEMORY is a MASK
    not a unit — use GUC_UNIT_KB; enum GUCs store int, not char*;
    extension GUCs register PER BACKEND at library load — a test
    session must load the library (SELECT lakehouse.version()) before
    SHOW/SET, else SET silently creates unvalidated PLACEHOLDERS (SET
    on unknown qualified names!). regress test gucs.sql in the suite
    (7th test); suite 7/7 green. RANGE error text in this tree uses
    "kB .. kB" format. NEXT: P1 writer rollover (consumes
    lakehouse.target_file_size via a new FFI flush threshold), or P0
    read-path integration (cache into fetch_metadata/manifests).
  - HANDOFF REPAIR 2026-11-21: the P1 commit briefly landed directly on
    lakehouse-dev (branch-discipline slip, RULES §1a B3) as a merge
    object; repaired by cherry-pick -m 1 onto cf5631-port + clippy fix
    (manual_checked_ops on the rollover avg). 112 cargo green.
  - P0 read-path integration — DONE 2026-11-21 (TDD): the scan path's
    manifest-list, manifest and DV-puffin reads go through the global
    per-backend BlockCache (cache.rs global + StorageIo.scope_id =
    endpoint+bucket / local root — the cache namespace). metadata.json
    is DELIBERATELY UNCACHED: it is the catalog's pointer TARGET and its
    path can be served with new content (fixtures/HadoopTables reuse
    names) — the immutable-path law applies to content-unique objects
    only (correction caught by the e2e mock serving rewritten metadata:
    the cached version silently planned 0 tasks). PROOF: destructive
    test — scan once (fills cache), DELETE manifest-list + manifest from
    the store, scan again plans 1 task entirely from cache. FFI:
    pg_datalake_core_cache_init(max_bytes) called from _PG_init with
    lakehouse.cache_max_bytes (first call wins). 113 cargo green,
    clippy -D warnings, suite 7/7. NEXT: P3 delta store as PG table +
    P4 publisher worker (staged-INSERT critical path), or P0b lazy
    ranged parquet reader.
  - P3 core slice — DONE 2026-11-21 (staged INSERT capture + delta
    read side, TDD offline): write_mode='staged' now routes managed
    INSERT through the delta-segments TABLE — durability from the
    txn's own WAL record (D1-rev): tuple_insert skips the remote
    session entirely; PRE_COMMIT serializes staged rows as ONE JSON
    payload (the write path's typed row-JSON) and SPI-INSERTs it into
    lakehouse.lakehouse_delta_segments ($1::bytea parameterized);
    scan_begin in staged mode opens NO session (delta-only scan: zero
    tasks) and scan_getnextslot serves committed unpublished segments
    via SPI (active snapshot = MVCC — cross-backend staged visibility
    free, own-txn rows via the overlay, no duplicates). Rust:
    pg_datalake_delta_rows_* FFI (payload -> renderer-exact text forms;
    WriteColumn serde accepts "type"). OFFLINE PROOF (the point):
    staged INSERT COMMITTED against an unreachable catalog with
    read-your-writes across TWO transactions and TWO segments — COW
    structurally cannot do this. 114 cargo + suite 9/9 (staged_insert
    is the 9th). PENDING: kill-9 crash test (live), publisher
    read/emission side, tombstone gating (staged DML = R4 after V3).
    Branch: feature/p3-staged-writes (PR next).
  - P3 CRASH TEST — PASSED 2026-11-21 (live, §7.2 P3 acceptance):
    staged INSERT of 50 rows committed (write_mode=staged, 1 delta
    segment, published=false) -> pg_ctl stop -m immediate (kill-class:
    no clean shutdown, WAL replay on restart) -> recovery ran -> delta
    segment SURVIVED (count 1) -> read-your-writes after recovery =
    ALL 50 rows served from the recovered segment. The D1-rev claim
    ("the row IS the durable record; recovery restores it") is now
    demonstrated, not asserted. PENDING: publisher read/emission
    (P4), tombstone gating note for staged DML (R4 after V3).
  - P4 slice 1 — DONE 2026-11-21 (publisher emission core + SQL entry,
    live + pyiceberg): pg_datalake_publish_segment (Rust: payload ->
    parse_row_json -> writer push -> flush, one data file per segment,
    M3-R2 stats carried) + lakehouse.publish_staged(regclass) (C:
    SPI-select unpublished segments ordered by seg_id, ONE write
    session, publish_segment + write_commit per segment (v1
    single-segment-per-commit per §4.4), ledger flip immediately after
    each commit). LIVE: staged 50-row segments -> publish_staged ->
    TWO APPEND snapshots on the remote table (+50 rows, +1 file each),
    pyiceberg reads 100 rows, ledger drained to 0 unpublished. P4b
    TODO: parse snapshot-id from commit result into the ledger column
    (currently flips published only), bgworker wrapper + publish_max_lag
    scheduling, coalesced multi-segment emission.
  - P4 slice 2 — DONE 2026-11-21 (coalesced emission + ledger snapshot
    id, live): commit_append now returns (metadata-location,
    snapshot-id) — the id captured from the locally-generated AddSnapshot
    (the REST response carries only metadata-location); C-side
    pg_datalake_write_last_snapshot_id; publish_staged COALESCES all
    unpublished segments into ONE snapshot (rollover bounds file sizes)
    and flips every segment's ledger to published=true +
    published_snapshot_id=<real id>. LIVE: 2 segments (20+11 rows) -> 1
    commit -> ledger {2, all_pub=t, snap=1882430676134503717}; cow-mode
    remote scan reads 31 rows, sum exact. P4c remaining: bgworker
    wrapper + publish_max_lag scheduling.
  - P4c slice — DONE 2026-11-21 (publisher bgworker, TDD + live): the
    hands-off loop — discover DISTINCT unpublished relids via SPI,
    publish each table in its OWN transaction (publish_staged's
    coalesced emission + ledger flip), sleep
    lakehouse.publish_max_lag, repeat. Registration DUAL: static under
    shared_preload (production, lakehouse.publisher_enabled +
    lakehouse.publish_database GUCs, PGC_POSTMASTER — defined only
    during preload: defining them in a backend FATALs), DYNAMIC via
    lakehouse.start_publisher() (tests/dev — no preload needed;
    postmaster-owned, survives the registering backend; guards via
    pg_stat_activity). GOTCHAS CAUGHT LIVE: the worker entry must be
    PGDLLEXPORT (-fvisibility=hidden hid it: "could not find
    lakehouse_publisher_main"); AND the per-table txn must COMMIT not
    ABORT — aborting rolled back the ledger flip so every cycle
    re-published the same segment (duplicate rows remote-side, seen as
    40 rows of the same 10). FIXED + verified hands-off: staged insert
    -> 2 cycles -> segments published=true with the real snapshot id;
    pyiceberg reads exactly 10 rows (no duplicates). Offline
    acceptance: publisher.sql (10th test) asserts the worker runs via
    start_publisher. Suite 10/10, 114 cargo.
  - R2 slice — MOSTLY DONE 2026-11-21 (write_mode table option + guard,
    live): WITH (write_mode='staged') sticks per table over the session
    GUC (resolved on every identity path); validator accepts write_mode
    alone at CREATE (identity attach later); scans/captures/flip all
    honor the table mode. NEW NEVER-MISREAD GUARD: staged rows with no
    capture path (mode unresolved + no session) now ereport LOUDLY —
    the first wm_stick insert vanished silently through exactly that
    hole (entry mode unresolved on the attach-row identity path; fixed:
    resolved on EVERY path via a local decode). EDITORIAL INCIDENT:
    a non-unique sed/replace duplicated ~3000 lines of tableam.c
    (caught by the compile; truncated at the true handler end and the
    scan bypass re-applied as a SINGLE pre-OpenSession block — decode
    into a LOCAL, never into scan->opts (memset clobbers the
    server-derived endpoint: "builder error")). OPEN BUG (next session
    first item): the publisher's append REPLACES the previous snapshot
    instead of extending it — fresh write session per cycle isn't
    carrying the base snapshot's manifests (wm_stick: published 5, then
    published 6 -> remote shows only 6/75; prior rows recoverable via
    the prior snapshot). Suspect carried-manifests handling in the
    fresh-session commit path. Also cleanup: relid=0 delta rows from
    the broken window.
  - RETRACTION 2026-11-21: the "publisher append REPLACES the previous
    snapshot" bug recorded earlier today DOES NOT EXIST. Manifest-level
    inspection (pyiceberg, wm_stick snapshot chain) shows every append
    correctly CARRIES all prior files forward (each snapshot = prior
    files + its own added file). The "lost rows" were victims of the
    pre-guard silent drop (unresolved entry write_mode on the
    attach-row identity path — fixed in R2 with the loud never-misread
    guard); the 6-vs-11 discrepancy came from repeated manual test
    attempts, not snapshot replacement. The publisher's append path is
    correct as-is; carried-manifests handling needs NO change.
  - ✅ PER-ROW CAPTURE REGRESSION FIXED (commit 42f2174b23e, PR #9
    should go green). ROOT CAUSE: dynahash hash-key aliasing. hash_search
    returns a pointer to the KEY BYTES (ELEMENTKEY) — the entry struct
    overlays them. LakehouseWriteEntry declared `int write_mode` at
    offset 0 (inside the 4-byte keysize window), so its !found init
    (`entry->write_mode = ...`) rewrote the stored key: every later
    HASH_ENTER for the same relid MISSED and minted a duplicate entry —
    one per row, each with 1 staged row, each captured as its own
    segment. Probes proved it directly: `found 0` three times, hash
    growing 1→2→3, same relid, same hashp. COW multi-row had the same
    bug latently (one write session per row). Fix: `Oid relid` is the
    FIRST member (canonical dynahash idiom, matching
    LakehouseScanRegistryEntry); init code never touches the key
    field. Also removed: redundant entry->relid init, unused save_uid,
    C90 mixed-declaration warning in the delta-serve path. Verified:
    probe log found=0 once then found=1 per row, ONE entry rows=3, ONE
    capture; lakehouse suite 10/10 green, upstream regress suite green.
    LESSON (generalizes): any struct used as a dynahash HASH_ELEM entry
    must declare the key first and treat it as hash-owned — a member
    landing inside [0, keysize) silently corrupts lookups.
  - (history) The two suspects previously eliminated — xact-callback
    registration and seq-search iteration — were never the cause; the
    earlier "capture 3× with staged_rows=1" observation was the alias
    entries. The two-phase PRE_COMMIT restructure (commit 5ded905e) is
    still the correct pattern and stays.

## PERF INSIGHTS (2026-11-21, internal receipts — not marketable claims)

Post perf-fix #1 arc (#14 parquet/arrow 60.1.0 → #15 object_store 0.14.2
→ #16 audit gate + smart CI → #17 P0b ranged/cached opens), measured on
the TPC-DS SF=10 fixture (release build, fresh instance):

- EXPLAIN (VERBOSE) count(*) on store_sales: Parallel Foreign Scan
  outputs ALL 23 columns; aggregate ABOVE the scan — 28.8M rows × 23
  cols transported for a count. 3 backends, zero I/O wait (CPU-bound
  transport). Fetch side proven done (P0b ProjectionMask fetches no
  chunks for empty projection).
- Full-table count ≈ 12 min = pure executor transport.
- P0b4 (spec 15 §6.6) PROMOTED to next: planner-level trivial-aggregate
  elision from cached footers + manifest record_counts; needs row_count
  column on lakehouse_delta_segments (next ext-version bump).
- Perf harness SHIPPED (#19): scripts/perf/lakehouse_perf.py (psycopg2/
  pgwire only), tpcds + scan suites, scale-factor fixture identity
  (perfcn.scan_bench_n<rows>, --tpcds-ns tpcds_sf<N>), verified fixture
  reuse (count+sum checksum; NOTICE reuse / WARNING regen /
  --force-regen), make perf-lakehouse wired.
- Measurement discipline learned the hard way: NEVER launch overlapping
  runner invocations against one instance (server restarts kill each
  other's counts; racing duplicates poison timings). One runner, one
  instance, one protocol pass.

NEXT STEPS (driven by insights): P0b4 elision (regress-testable offline:
fixture table + count(*) exactness + EXPLAIN shows no foreign-scan
transport) → P0b3 row-group-deferred iteration (q3 canary) → P0b2
page-index pruning → §5.2 marketed comparison once clean protocol
completes.
