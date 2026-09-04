# helm-charts

Helm charts for the Astergaze platform, served as a Helm repository over GitHub
Pages.

    helm repo add astergaze https://astergaze-technologies.github.io/helm-charts/build/
    helm search repo astergaze/

`charts/` is the source. `build/` is the published repository - packaged `.tgz`
files plus `index.yaml` - and is what the URL above resolves to, so a chart
version missing from `build/index.yaml` does not exist to any cluster.

Publishing is driven from the infra repo, which carries this repo as a
submodule:

    make -C applications chart-package    # package into build/ and reindex
    git -C helm-charts add build && git -C helm-charts commit -m "publish" && git -C helm-charts push

Bump `version:` in the chart's `Chart.yaml` before packaging: Helm refuses to
overwrite an existing version, and the k3s helm-controller resolves
`chart` + `version` straight out of `index.yaml`.
