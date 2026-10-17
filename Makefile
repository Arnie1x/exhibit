SHELL := /bin/bash
PSQL  ?= psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off
DATA  ?= /data/loghub          # path INSIDE the SereneDB container
MAP   ?= /data/ownership.csv   # ownership table, visible to the container
CACHE ?= $(PWD)/data           # mounted to /data in the container

.PHONY: help doctor up down fetch parse probe derive index bootstrap smoke demo bench eval roles mcp clean-check

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

doctor: ## check docker + psql + a live connection
	@docker --version; docker ps --filter name=serenedb --format '{{.Names}}  {{.Image}}  {{.Status}}'
	@$(PSQL) -c "SELECT version();" || (echo "no connection - is the container up?"; exit 1)

up: ## start SereneDB (arm64-safe tag: 26.09.1.3)
	docker run -d --name serenedb -p 127.0.0.1:7890:7890 \
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
	$(PSQL) -v data='$(DATA)' -v map='$(MAP)' -f sql/10_derive.sql

index: ## dictionary + bgl_idx / os_idx + refresh
	$(PSQL) -f sql/20_indexes.sql

views: ## signatures, incidents, episodes, durations, role views
	$(PSQL) -f sql/30_views.sql

roles: ## role views + GRANTs (scope enforced in the database)
	$(PSQL) -f sql/50_roles.sql

bootstrap: derive index views ## full rebuild from raw Parquet (idempotent, ~20 s)

smoke: ## the three headline numbers, printed for comparison
	$(PSQL) -f sql/99_smoke.sql

demo: ## the two worked investigations, exactly as the video runs them
	$(PSQL) -f sql/90_queries.sql

bench: ## optional: index a remote Parquet slice, measure rows/s (huge-datasets award)
	$(PSQL) -f sql/70_bench.sql

eval: ## score agent answers against golden SQL
	python3 evals/run_eval.py

clean-check: ## clone into a temp dir and run the whole sequence from scratch
	@tmp=$$(mktemp -d) && git clone -q "$(PWD)" "$$tmp/exhibit" && cd "$$tmp/exhibit" && \
	  $(MAKE) bootstrap smoke && echo "clean checkout OK: $$tmp/exhibit"
