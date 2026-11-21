# Lakehouse fixtures and test entry points (specs/lakehouse/10-testing.md §6).
#
#   make lakehouse-up           # docker compose: s3 + lakekeeper + azurite + fake-gcs
#   make lakehouse-check        # cargo test + upstream regress suite + lakehouse regress suite
#   make lakehouse-conformance  # interop suite vs pyiceberg (M1+)
#   make lakehouse-down
#   make perf-lakehouse         # perf harness (M4+, doc 10 §5)
#
# Reached via the root Makefile forward (meson-only checkouts).

COMPOSE = docker compose -f docker-compose.yml -p pgdatalake

.PHONY: lakehouse-up lakehouse-down lakehouse-check lakehouse-conformance perf-lakehouse

# Explicit orchestration: `compose up --wait` with no service list fails on
# one-shot jobs (s3-setup, lakekeeper-migrate exit after finishing), so wait
# on the servers, run the one-shots, then wait on the catalog.
lakehouse-up:
	$(COMPOSE) up -d --wait s3 azurite fake-gcs lakekeeper-db
	$(COMPOSE) run --rm s3-setup
	$(COMPOSE) run --rm lakekeeper-migrate
	$(COMPOSE) up -d --wait lakekeeper
	curl -sf http://localhost:8181/health > /dev/null
	fixtures/lakekeeper-setup.sh
	fixtures/smoke.sh
	@echo "lakehouse fixtures up: S3 :9000, Lakekeeper :8181 (/health ok), Azurite :10000, fake-gcs :4443"

lakehouse-down:
	$(COMPOSE) down --volumes --remove-orphans

lakehouse-check:
	@echo "cargo test -p pgdatalake-core"
	cargo test --manifest-path $(CURDIR)/../../backend/access/lakehouse/core/Cargo.toml
	@echo "meson install (meson test runs the INSTALLED binaries — a stale"
	@echo "tmp_install silently tests old code; CI learned this the hard way)"
	meson install --destdir $(CURDIR)/../../../build/tmp_install > /dev/null
	@echo "meson test (setup + regress + lakehouse suites)"
	meson test -C $(CURDIR)/../../../build --suite setup
	meson test -C $(CURDIR)/../../../build --suite regress
	meson test -C $(CURDIR)/../../../build --suite lakehouse

lakehouse-conformance:
	@echo "lakehouse-conformance: not implemented until M1 (specs/lakehouse/12-roadmap.md)" && exit 1

perf-lakehouse:
	@echo "perf-lakehouse (spec 10 §5): python driver + pyiceberg fixture gen"
	@echo "  README + usage: scripts/perf/README.md"
	@echo "  tpcds: python3 scripts/perf/lakehouse_perf.py --suite tpcds --dsn <dsn>"
	@echo "  scan : python3 scripts/perf/lakehouse_perf.py --suite scan --dsn <dsn> --generate-scan"
	@if [ -n "$$DSN" ]; then \
	  python3 scripts/perf/lakehouse_perf.py --suite $${PERF_SUITE:-tpcds} --dsn "$$DSN" $(PERF_ARGS); \
	else \
	  echo "  set DSN=postgres://... (a RELEASE-build server) to actually run; see scripts/perf/README.md"; \
	fi
