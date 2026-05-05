LUA54  := /opt/homebrew/opt/lua@5.4/bin
TL     := $(LUA54)/tl
BUSTED := $(LUA54)/busted
LOVE   := love

SRC_TL    := src_tl
SRC_OUT   := src
SPEC_TL   := spec_tl
SPEC_OUT  := spec
LUA_COMPAT := lua_compat

LUA    := $(LUA54)/lua

.PHONY: check build test run playtest clean

check:
	$(TL) check $(SRC_TL)/main.tl

build:
	@mkdir -p $(SRC_OUT)
	@find $(SRC_TL) -name '*.tl' ! -name '*.d.tl' | while read f; do \
		rel="$${f#$(SRC_TL)/}"; \
		out="$(SRC_OUT)/$${rel%.tl}.lua"; \
		mkdir -p "$$(dirname $$out)"; \
		$(TL) gen "$$f" -o "$$out"; \
	done
	@mkdir -p $(SPEC_OUT)
	@find $(SPEC_TL) -name '*.tl' ! -name '*.d.tl' | while read f; do \
		rel="$${f#$(SPEC_TL)/}"; \
		out="$(SPEC_OUT)/$${rel%.tl}.lua"; \
		mkdir -p "$$(dirname $$out)"; \
		$(TL) --global-env-def spec_tl/support/busted gen "$$f" -o "$$out"; \
	done
	@cp $(LUA_COMPAT)/bit32.lua $(SRC_OUT)/bit32.lua

test: build
	$(BUSTED) --lpath "$(LUA_COMPAT)/?.lua;$(SRC_OUT)/?.lua;$(SRC_OUT)/?/init.lua;$(SPEC_OUT)/?.lua;$(SPEC_OUT)/?/init.lua" $(SPEC_OUT)/

run: build
	$(LOVE) $(SRC_OUT)/

# Headless AI playtest harness. Runs scripts/playtest.lua against the built
# Lua tree and reports per-seed outcomes plus aggregate metrics. The S06
# baseline (6/10 Hu) is documented in scripts/playtest.lua's header.
playtest: build
	$(LUA) scripts/playtest.lua

clean:
	rm -rf $(SRC_OUT)/ $(SPEC_OUT)/
