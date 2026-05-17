# DeFi Super-App — Foundry Makefile
# Usage: make <target>
# Requires Foundry: https://getfoundry.sh

.PHONY: all build test unit fuzz invariant fork coverage snapshot slither clean fmt fmt-check install

FORGE       := forge
FORGE_FLAGS := --optimize --optimizer-runs 200
FORK_URL    := $(FORK_RPC_URL)

# ─── Install ──────────────────────────────────────────────────────────────────
install:
	$(FORGE) install

# ─── Build ────────────────────────────────────────────────────────────────────
build:
	$(FORGE) build --sizes

# ─── Format ───────────────────────────────────────────────────────────────────
fmt:
	$(FORGE) fmt

fmt-check:
	$(FORGE) fmt --check

# ─── Test ─────────────────────────────────────────────────────────────────────
all: build unit fuzz invariant

test:
	$(FORGE) test -v

unit:
	$(FORGE) test --match-path "test/unit/**" -v

fuzz:
	$(FORGE) test --match-path "test/fuzz/**" -v

invariant:
	$(FORGE) test --match-path "test/invariant/**" -v

fork:
	FORK_RPC_URL=$(FORK_URL) $(FORGE) test --match-path "test/fork/**" -v

# Specific contract test
test-%:
	$(FORGE) test --match-contract "$*" -v

# ─── Coverage ─────────────────────────────────────────────────────────────────
coverage:
	$(FORGE) coverage --match-path "test/unit/**" --report lcov --report summary

coverage-html:
	$(FORGE) coverage --match-path "test/unit/**" --report lcov
	genhtml lcov.info --output-directory coverage-html
	@echo "Report: coverage-html/index.html"

# ─── Gas ──────────────────────────────────────────────────────────────────────
snapshot:
	$(FORGE) snapshot --match-path "test/unit/**" --snap .gas-snapshot

gas-diff:
	$(FORGE) snapshot --diff .gas-snapshot --match-path "test/unit/**"

gas-report:
	$(FORGE) test --match-path "test/unit/**" --gas-report

# ─── Static Analysis ──────────────────────────────────────────────────────────
slither:
	slither contracts/ \
	  --exclude-dependencies \
	  --filter-paths "contracts/mocks/|contracts/attacks/" \
	  --checklist

# ─── Deploy ───────────────────────────────────────────────────────────────────
deploy-local:
	$(FORGE) script script/Deploy.s.sol \
	  --rpc-url http://localhost:8545 \
	  --broadcast \
	  -e USE_MOCK_ORACLE=true

deploy-testnet:
	$(FORGE) script script/Deploy.s.sol \
	  --rpc-url $(RPC_URL) \
	  --broadcast \
	  --verify \
	  --etherscan-api-key $(ETHERSCAN_API_KEY)

upgrade:
	$(FORGE) script script/Upgrade.s.sol \
	  --rpc-url $(RPC_URL) \
	  --broadcast \
	  --verify \
	  --etherscan-api-key $(ETHERSCAN_API_KEY)

# ─── Clean ────────────────────────────────────────────────────────────────────
clean:
	$(FORGE) clean
	rm -rf out cache
