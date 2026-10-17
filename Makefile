SHELL := /bin/bash
PSQL  ?= psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off
# The three paths below are paths INSIDE the SereneDB container (CACHE is the host side, mounted
# at /data). Keep the comments off the assignment lines: in Make, the whitespace before a trailing
# `#` becomes part of the value, and `/data/loghub   ` is not a path that any glob will match --
# which is exactly how `make derive` came to fail on a fresh clone while every other target passed.
DATA  ?= /data/loghub
MAP   ?= /data/ownership.csv
CACHE ?= $(PWD)/data
BENCH_SECONDS ?= 1

# Python prints check marks and arrows; a Windows console defaults to cp1252 and raises
# UnicodeEncodeError on the first one. UTF-8 mode is a no-op on Linux and macOS.
export PYTHONUTF8 := 1

.PHONY: help setup doctor up down fetch parse probe derive index bootstrap smoke demo bench bench-ladder eval validate roles evidence mcp check clean-check

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

doctor: ## check docker + psql + a live connection
	@docker --version; docker ps --filter name=serenedb --format '{{.Names}}  {{.Image}}  {{.Status}}'
	@$(PSQL) -c "SELECT version();" || (echo "no connection - is the container up?"; exit 1)

up: ## start SereneDB (arm64-safe tag: 26.09.1.3); trust auth, published on loopback only
	docker run -d --name serenedb -p 127.0.0.1:7890:7890 \
	  -e SERENEDB_HOST_AUTH_METHOD=trust \
	  -v serenedb-data:/var/lib/serenedb -v "$(CACHE)":/data serenedb/serenedb:26.09.1.3

down: ## stop it
	docker stop serenedb

fetch: ## download + unpack the two Loghub archives (63 MB, ~800 MB unpacked) into data/loghub/
	mkdir -p data/loghub && cd data/loghub && \
	curl -sSL -o BGL.zip 'https://zenodo.org/records/8196385/files/BGL.zip?download=1' && \
	curl -sSL -o OpenStack.tar.gz 'https://zenodo.org/records/8196385/files/OpenStack.tar.gz?download=1' && \
	unzip -o -q BGL.zip BGL.log && tar -xzf OpenStack.tar.gz

parse: ## raw .log -> Parquet in data/loghub/ (= $(DATA) in the container; parity in docs/data-notes.md)
	uv run --no-project --with pyarrow python -X utf8 scripts/parse.py --in data/loghub --out data/loghub

probe: ## re-measure docs/capabilities.md against the engine; DRIFT lines mean the doc changes
	PSQL='$(PSQL)' DATA='$(DATA)' bash scripts/probe_capabilities.sh

derive: ## raw Parquet -> bgl_ev, os_ev, owner_map
	$(PSQL) -v data='$(DATA)' -v map='$(MAP)' < sql/10_derive.sql

index: ## dictionary + bgl_idx / os_idx + refresh
	$(PSQL) < sql/20_indexes.sql

views: ## signatures, incidents, episodes, durations, role views
	$(PSQL) < sql/30_views.sql

roles: ## role views + GRANTs (scope enforced in the database)
	$(PSQL) < sql/50_roles.sql

evidence: ## the evidence ledger table + its grants (sql/55_evidence.sql; after roles, which resets grants)
	$(PSQL) < sql/55_evidence.sql

bootstrap: derive index views roles evidence ## full rebuild from raw Parquet (idempotent, ~25 s); roles then evidence, views' CASCADE drops them

setup: ## create the venv and install dependencies (uv)
	uv sync

mcp: ## run the exhibit MCP server on stdio (point any MCP client at it)
	uv run exhibit-mcp

check: ## Stage 2 acceptance: tool numbers vs make smoke, then a stock MCP client
	uv run exhibit-check
	uv run python scripts/stage2_mcp_client.py

smoke: ## the three headline numbers, printed for comparison
	$(PSQL) < sql/99_smoke.sql

demo: ## the two worked investigations, exactly as the video runs them
	$(PSQL) < sql/90_queries.sql

bench: ## huge data: index a slice of the remote 1B-row OTel file + a view over local Parquet
	$(PSQL) -v seconds=$(BENCH_SECONDS) < sql/70_bench.sql

bench-ladder: ## the bench at 1 and 10 s slices, each index sized on disk (bench/README.md)
	PSQL='$(PSQL)' bash bench/run_ladder.sh

eval: ## score the question bank against the hand-written golden SQL
	uv run python evals/run_eval.py

validate: ## ground truth, outside the agent: anomaly_labels.txt vs durations; BGL label vs signatures
	uv run python scripts/validate_ground_truth.py

clean-check: ## clone into a temp dir and run the whole sequence from scratch
	@tmp=$$(mktemp -d) && git clone -q "$(PWD)" "$$tmp/exhibit" && cd "$$tmp/exhibit" && \
	  $(MAKE) bootstrap smoke && echo "clean checkout OK: $$tmp/exhibit"
