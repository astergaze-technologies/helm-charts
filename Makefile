# Packaging and publishing, in the repo that owns the charts. `build/` is the
# published Helm repository - packaged .tgz files plus index.yaml - served by
# GitHub Pages straight from this repo, so a version missing from
# build/index.yaml does not exist to any cluster.
#
#   make lint
#   make package      # then commit build/ and push; Pages serves it
#
# helm is not pinned here (the infra repo's mise.toml pins the one it uses).
# Packaging is stable across 3.x, so whatever is on PATH is fine.

CHART_REPO_URL ?= https://astergaze-technologies.github.io/helm-charts/build/
CHARTS         ?= web-service

lint:
	helm lint $(addprefix charts/,$(CHARTS))

# The version comes from Chart.yaml, never a flag someone remembers to pass.
# helm package refuses to overwrite an existing version, so a forgotten bump
# fails here rather than silently shipping different content under an old
# version - which every cluster would have cached.
package: lint
	@mkdir -p build
	@for c in $(CHARTS); do \
	  v=$$(awk '/^version:/{print $$2}' charts/$$c/Chart.yaml); \
	  echo "packaging $$c $$v"; \
	  helm package charts/$$c --version $$v -d build; \
	done
	@# --merge folds the new entry into the existing index. Without it every
	@# previously published version disappears from the catalogue while its
	@# .tgz sits in build/ unreferenced, and any release pinning one breaks.
	helm repo index build --url $(CHART_REPO_URL) --merge build/index.yaml
	@echo
	@echo "Now publish it:"
	@echo "  git add build charts && git commit -m 'publish' && git push"

# What Pages actually serves, which is not always what build/ holds locally.
verify:
	@helm repo add astergaze $(CHART_REPO_URL) >/dev/null 2>&1 || true
	@helm repo update astergaze >/dev/null
	@helm search repo astergaze/ --versions | tail -n +2

.PHONY: lint package verify
