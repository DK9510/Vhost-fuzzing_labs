SHELL := /bin/bash
LAB ?=
EDGE_IMAGE := vhostlab/edge:1.0
LABS := $(patsubst labs/%/,%,$(wildcard labs/*/))

.PHONY: help build certs up down reset verify up-all down-all verify-all ports list logs lan lan-hosts lan-check

help:
	@echo "vhostlab — one lab per case"
	@echo
	@echo "  make build                 build the shared edge image ($(EDGE_IMAGE))"
	@echo "  make certs                 issue/renew per-lab leaf certs from the lab CA"
	@echo "  make up LAB=<lab>          start one lab"
	@echo "  make down LAB=<lab>        stop one lab (keeps volumes unless reset)"
	@echo "  make reset LAB=<lab>       stop + remove volumes + re-up"
	@echo "  make verify LAB=<lab>      run that lab's assertions"
	@echo "  make up-all down-all       operate on every lab"
	@echo "  make verify-all            run every lab, writes instances/results.json"
	@echo "  make ports                 port map + host collisions"
	@echo "  make list                  labs present"
	@echo
	@echo "  make lan                   LAN address, port map, client hosts file"
	@echo "  make lan-hosts             print the /etc/hosts block for a client machine"
	@echo "  make lan-check             curl every lab over the LAN IP (not loopback)"
	@echo
	@echo "labs: $(LABS)"

build:
	bash scripts/build-edge.sh

certs:
	bash scripts/issue-all-certs.sh

up:
	@test -n "$(LAB)" || (echo "LAB required, e.g. make up LAB=c01-bare-ip-404"; exit 1)
	bash scripts/issue-all-certs.sh >/dev/null
	docker compose -f labs/$(LAB)/docker-compose.yml up -d
	@echo "started $(LAB)"

down:
	@test -n "$(LAB)" || (echo "LAB required"; exit 1)
	docker compose -f labs/$(LAB)/docker-compose.yml down

reset:
	@test -n "$(LAB)" || (echo "LAB required"; exit 1)
	docker compose -f labs/$(LAB)/docker-compose.yml down -v
	bash scripts/issue-all-certs.sh >/dev/null
	docker compose -f labs/$(LAB)/docker-compose.yml up -d

verify:
	@test -n "$(LAB)" || (echo "LAB required"; exit 1)
	bash labs/$(LAB)/checks/verify.sh

up-all: build certs
	@for l in $(LABS); do echo "== $$l"; docker compose -f labs/$$l/docker-compose.yml up -d --force-recreate || exit 1; done

down-all:
	@for l in $(LABS); do echo "== $$l"; docker compose -f labs/$$l/docker-compose.yml down; done

verify-all:
	bash scripts/verify-all.sh

ports:
	bash scripts/ports.sh

lan:
	bash scripts/lan.sh

lan-hosts:
	bash scripts/lan.sh --hosts

lan-check:
	bash scripts/lan.sh --check

list:
	@printf '%s\n' $(LABS)

logs:
	@test -n "$(LAB)" || (echo "LAB required"; exit 1)
	docker compose -f labs/$(LAB)/docker-compose.yml logs -f --tail=50
