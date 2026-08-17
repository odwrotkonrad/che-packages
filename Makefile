##[>] 🤖🤖
#[what] che-packages: the catalog plus the pytest suite proving every package installs
SHELL := zsh
.SHELLFLAGS := -c

PY ?= python3
VENV := .user/venv
PYTEST := $(VENV)/bin/pytest
CHE_VERSION ?= latest
CHE_BIN := .user/bin/che
TARGET_ARCH ?= $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,amd64)
CHE_PKG_URL := https://gitlab.com/api/v4/projects/konradodwrot%2Fgo-modules/packages/generic/che

PACKAGE ?=
METHOD ?=

WRAPPERS := $(VENV) $(CHE_BIN)
COMMANDS := render-templates test test-catalog test-install test-install-auto fetch-che clean

.PHONY: $(COMMANDS)

$(VENV):
	$(PY) -m venv $(VENV)
	$(VENV)/bin/pip install --quiet --upgrade pip
	$(VENV)/bin/pip install --quiet pytest pyyaml jsonschema

##[>] Docs [genai-include]
#[what] render *.ontoRepo.tpl onto the repo (the per-package CI matrix)
render-templates:
	che render tpl -f templates/2-data/install-matrix.gitlab-ci.yml.ontoRepo.tpl > .gitlab/ci/install-matrix.gitlab-ci.yml
##[<] Docs

##[>] Test [genai-include]
#[what] every test: catalog validation plus the full install matrix (needs docker)
test: test-catalog test-install

#[what] fast catalog validation: json schema, method resolution, verify derivation, manpage parsing
test-catalog: $(VENV)
	$(PYTEST) tests/test_catalog.py

#[what] install tests, filtered by PACKAGE= and METHOD= (needs docker and a che binary)
test-install: $(VENV) $(CHE_BIN)
	CHE_BIN=$(CURDIR)/$(CHE_BIN) TARGET_ARCH=$(TARGET_ARCH) $(PYTEST) tests/test_install.py \
		$(if $(PACKAGE),--package=$(PACKAGE)) $(if $(METHOD),--method=$(METHOD))

#[what] the automatic tier only: the first CHE_E2E_AUTO_PER_METHOD packages of each method
test-install-auto: $(VENV) $(CHE_BIN)
	CHE_BIN=$(CURDIR)/$(CHE_BIN) TARGET_ARCH=$(TARGET_ARCH) $(PYTEST) tests/test_install.py --tier=auto
##[<] Test

##[>] Tools [genai-include]
#[what] download the linux che binary the install tests drive into .user/bin
fetch-che: $(CHE_BIN)

$(CHE_BIN):
	mkdir -p .user/bin
	curl -fsSL "$(CHE_PKG_URL)/$(CHE_VERSION)/che_$(CHE_VERSION)_linux_$(TARGET_ARCH).tar.gz" \
		| tar -xz -C .user/bin che
	chmod +x $(CHE_BIN)

#[what] drop the venv and downloaded binaries
clean:
	rm -rf $(VENV) .user/bin
##[<] Tools
##[<] 🤖🤖
