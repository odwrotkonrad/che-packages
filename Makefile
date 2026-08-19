##[>] 🤖🤖
#[what] che-packages: the catalog plus the pytest suite proving every package installs
SHELL := zsh
.SHELLFLAGS := -c

PY ?= python3
VENV := .user/venv
PYTEST := $(VENV)/bin/pytest
include che-pin.env
#[what] a merge-request pipeline's resolved che: an open go-modules MR's prerelease, binary and
#   schema ref together, overriding che-pin.env's floor. Empty everywhere else, so the pin stands.
#[why] generated at parse time, before the includes below expand CHE_VERSION and CHE_SCHEMA_REF, and
#   ignoring failure: resolution is best-effort, never a reason to break a catalog build
RESOLVED_PIN := .user/che-pin.resolved.env
_ := $(shell ci/resolve-che-version.zsh $(RESOLVED_PIN) >&2 || :)
-include $(RESOLVED_PIN)
CHE_BIN := .user/bin/che
SCHEMA := .user/packages.schema.json
#[why] che owns the vocabulary: the schema is generated from its Go models and fetched from
#   the che repo, never copied here, so one contract has one source of truth
SCHEMA_URL ?= https://gitlab.com/konradodwrot/go-modules/-/raw/$(CHE_SCHEMA_REF)/che/assets/data/packages.schema.json
TARGET_ARCH ?= $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,amd64)
#[why] an os axis beside the arch, each naming exactly one: darwin arm64 needs a different
#   virtualisation engine rather than another docker --platform value, so one combined "all"
#   would read as every platform while meaning both linux arches
TARGET_OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')
CHE_PKG_URL := https://gitlab.com/api/v4/projects/konradodwrot%2Fgo-modules/packages/generic/che

PACKAGE ?=
METHOD ?=
INSTALL_JOBS ?= 4

WRAPPERS := $(VENV) $(CHE_BIN) $(SCHEMA)
COMMANDS := render-templates test test-catalog test-install test-install-auto fetch-che fetch-schema clean

.PHONY: $(COMMANDS)

$(VENV):
	$(PY) -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --upgrade pip
	$(VENV)/bin/pip install --quiet pytest pytest-xdist pyyaml jsonschema

##[>] Docs [genai-include]
#[what] render *.ontoRepo.tpl onto the repo (the per-package CI matrix)
render-templates:
	che render tpl -f templates/2-data/install-matrix.gitlab-ci.yml.ontoRepo.tpl > .gitlab/ci/install-matrix.gitlab-ci.yml
##[<] Docs

##[>] Test [genai-include]
#[what] every test: catalog validation plus the full install matrix (needs docker)
test: test-catalog test-install

#[what] fast catalog validation: json schema, method resolution, verify derivation, manpage parsing
test-catalog: $(VENV) $(SCHEMA)
	PACKAGES_SCHEMA=$(CURDIR)/$(SCHEMA) $(PYTEST) tests/test_catalog.py

#[what] install tests, filtered by PACKAGE= and METHOD=, on TARGET_OS=/TARGET_ARCH= (needs docker and a che binary)
test-install: $(VENV) $(CHE_BIN)
	CHE_BIN=$(CURDIR)/$(CHE_BIN) TARGET_OS=$(TARGET_OS) TARGET_ARCH=$(TARGET_ARCH) $(PYTEST) tests/test_install.py \
		$(if $(PACKAGE),--package=$(PACKAGE)) $(if $(METHOD),--method=$(METHOD))

#[what] the automatic tier only: the first CHE_E2E_AUTO_PER_METHOD packages of each method
#[why] -n: each case is an isolated container, so they parallelise cleanly. Sequentially the
#   auto tier took over 20 minutes of mostly-idle waiting on registry downloads
test-install-auto: $(VENV) $(CHE_BIN)
	CHE_BIN=$(CURDIR)/$(CHE_BIN) TARGET_OS=$(TARGET_OS) TARGET_ARCH=$(TARGET_ARCH) $(PYTEST) tests/test_install.py --tier=auto -n $(INSTALL_JOBS)
##[<] Test

##[>] Tools [genai-include]
#[what] download the packages schema che generates from its Go models
fetch-schema: $(SCHEMA)

$(SCHEMA): che-pin.env $(RESOLVED_PIN)
	mkdir -p .user
	curl -fsSL "$(SCHEMA_URL)" -o $(SCHEMA)

#[what] download the linux che binary the install tests drive into .user/bin
fetch-che: $(CHE_BIN)

#[why] the resolved pin is a prerequisite, not just an existence check: a cached binary from a run
#   at a different version is the wrong binary, and silently driving it proves nothing
$(CHE_BIN): che-pin.env $(RESOLVED_PIN)
	mkdir -p .user/bin
	curl -fsSL "$(CHE_PKG_URL)/$(CHE_VERSION)/che_$(CHE_VERSION)_linux_$(TARGET_ARCH).tar.gz" \
		| tar -xz -C .user/bin che
	chmod +x $(CHE_BIN)
	#[why] tar restores the archive's mtime, which predates the prerequisites: without this the
	#   binary looks stale on every run and re-downloads ~100MB each time
	touch $(CHE_BIN)

#[what] drop the venv and downloaded binaries
clean:
	rm -rf $(VENV) .user/bin $(SCHEMA)
##[<] Tools
##[<] 🤖🤖
