LUA54  := /opt/homebrew/opt/lua@5.4/bin
TL     := $(LUA54)/tl
BUSTED := $(LUA54)/busted
LOVE   := love

SRC_TL   := src_tl
SRC_OUT  := src
SPEC_TL  := spec_tl
SPEC_OUT := spec

.PHONY: check build test run clean

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
	@find $(SPEC_TL) -name '*_spec.tl' | while read f; do \
		rel="$${f#$(SPEC_TL)/}"; \
		out="$(SPEC_OUT)/$${rel%.tl}.lua"; \
		mkdir -p "$$(dirname $$out)"; \
		$(TL) --global-env-def spec_tl/support/busted gen "$$f" -o "$$out"; \
	done

test: build
	$(BUSTED) $(SPEC_OUT)/

run: build
	$(LOVE) $(SRC_OUT)/

clean:
	rm -rf $(SRC_OUT)/ $(SPEC_OUT)/
