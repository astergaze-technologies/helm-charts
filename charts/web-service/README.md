# web-service

One deployable service: Deployment, Service, optional HTTPRoute, ServiceAccount,
optional HPA and ServiceMonitor. Standard Helm conventions — `image.repository`,
`service.port`, `env`, `resources` — so it reads like any other chart.

It deploys **into a namespace that already exists**. It does not create the
namespace, its quota or its network policies, and it does not create databases —
a database is a `cnpg/cluster` release from cloudnative-pg.github.io/charts.

```bash
make -C applications service SVC=hrms-frontend NS=dev VALUES=services/hrms-frontend-dev.yaml
```

## Why this is separate from the tenant chart

| | `charts/web-service` | `cnpg/cluster` |
|---|---|---|
| Scope | one service | one database |
| Creates | Deployment, Service, HTTPRoute | Cluster, Pooler, backups |
| Changes when | you ship code | the data plane changes |

The reason is blast radius. In one combined chart, bumping an image tag
re-renders the PostgreSQL cluster in the same release — a deploy and a database
change become one transaction. Split, a deploy touches a Deployment.

## Naming

Every object is `<release>-web-service`. Release `hamro-hrms-frontend-dev` gives
`hamro-hrms-frontend-dev-web-service`, which is the name your `backendRefs` must
use. Override with `fullnameOverride` if you need something else.

## Values worth knowing

```yaml
image:
  registry: ghcr.io/astergazetech    # split out, so one service can live elsewhere
  repository: hamro-hrms-fe          # required
  tag: "dev"
imagePullSecrets:
  - name: regcred                    # Secret must already exist in the namespace

service:
  port: 3000
  targetPort: 3000                   # must be >= 1024, see below

env:                                 # a plain map,
  TEST: testvalue
# env:                               # or the full Kubernetes list, for
#   - name: STRIPE_KEY               # secretKeyRef and fieldRef
#     valueFrom:
#       secretKeyRef: { name: acme-stripe, key: token }
```

Pods roll automatically when `env` changes — the Deployment carries a checksum
of it. Without that, a ConfigMap edit looks applied and nothing picks it up.

### Routing

```yaml
httpRoute:
  enabled: true
  hostnames: ["hrms.hamrostack.com"]
  rules:
    - matches:
        - path: { type: PathPrefix, value: /api/notifications/stream }
      backendRefs: [{ name: hrms-web-service, port: 3000 }]
      timeouts:
        request: 0s          # no timeout
    - matches:
        - path: { type: PathPrefix, value: / }
      filters:
        - type: ExtensionRef
          extensionRef: { group: traefik.io, kind: Middleware, name: ratelimit }
      backendRefs: [{ name: hrms-web-service, port: 3000 }]
```

Omit `rules` entirely for "everything to this service".

**`timeouts.request: 0s` is not optional for streaming.** Server-sent events,
websockets and long polls outlive the default request timeout, and when it fires
the connection is cut mid-stream — which looks like a client bug.

`filters` is how rate limiting and auth reach the route: Gateway API has no
standard filter for them, so Traefik exposes them as `Middleware` CRDs behind
`extensionRef`. Standard filters like `URLRewrite` work without any of that. The
`Middleware` object is not chart-managed — create it in the namespace.

## Platform constraints this chart already satisfies

Tenant namespaces enforce `pod-security.kubernetes.io/enforce: restricted`. A
violation is rejected at *admission*, so the pod is never created and there is
no crash log to read. The defaults handle it; things to know when overriding:

- **uid 10001, non-root.** An image with a baked-in uid needs
  `podSecurityContext.runAsUser` changed to match.
- **Read-only root filesystem.** Anything the image writes needs its path in
  `writableDirs`, or the container exits at startup. `/tmp` is there by default.
- **`targetPort` must be ≥ 1024.** Binding lower needs `CAP_NET_BIND_SERVICE`,
  which is dropped.
- **`linux/arm64`.** The nodes are Graviton; an amd64 image gives
  `exec format error` in CrashLoopBackOff.
- **ClusterIP only.** Public traffic arrives through the Cloudflare Tunnel;
  there is no LoadBalancer or NodePort anywhere by design.

## What the chart refuses to render

- `httpRoute.enabled` with no `hostnames` — an HTTPRoute with an empty
  `hostnames` matches **every** host on the shared Gateway and would take other
  tenants' traffic.
- `httpRoute.enabled` without `service.enabled` — the route would resolve to
  `BackendNotFound`.
- `autoscaling.enabled` without `resources.requests` — an HPA on CPU or memory
  has nothing to compute a percentage against.

## Probes are off by default

Deliberate: a probe pointed at a path that does not return 200 turns a working
rollout into a CrashLoop. Set both on anything taking real traffic — without
them a rollout reports success before the app can serve.

```yaml
readinessProbe: { httpGet: { path: /healthz, port: http } }
livenessProbe:  { httpGet: { path: /healthz, port: http }, initialDelaySeconds: 10 }
```

`preStopSeconds` (default 5) is separate and always on: it keeps a terminating
pod answering until it has left the Service endpoints. Without it every rollout
drops a few requests as 502/504.
