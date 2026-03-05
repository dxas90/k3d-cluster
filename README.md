# K3d Local Kubernetes Cluster

![Apache2](https://img.shields.io/github/license/dxas90/k3d-cluster)

A fully-automated local Kubernetes cluster using [k3d](https://k3d.io/), bootstrapped with [Flux CD](https://fluxcd.io/) for GitOps, [cert-manager](https://cert-manager.io/) for TLS, [SOPS](https://getsops.io/) + [age](https://age-encryption.org/) for secret encryption, and the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs pre-installed.

## Table of Contents

- [Description](#description)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [Quickstart](#quickstart)
- [Available Tasks](#available-tasks)
- [Cluster Details](#cluster-details)
- [Secret Management](#secret-management)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Description

This repository provisions a local K3s cluster (via k3d) with a production-like GitOps stack, suitable for local development, testing, and homelab use. All tooling is managed through [mise](https://mise.jdx.dev/), which installs and pins every CLI dependency automatically.

**Installed stack (via bootstrap):**

- [Flux CD v2.7.5](https://fluxcd.io/) — GitOps controllers (source, kustomize, helm, notification)
- [cert-manager v1.19.1](https://cert-manager.io/) — Automatic TLS certificate management
- [Gateway API v1.4.0](https://gateway-api.sigs.k8s.io/) — Next-generation Kubernetes ingress/routing CRDs
- [Prometheus Operator CRDs v0.86.1](https://prometheus-operator.dev/) — Monitoring custom resource definitions

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│  Host Machine                                           │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  k3d Cluster (Docker)                            │   │
│  │                                                  │   │
│  │  ┌─────────────┐  ┌───────────┐  ┌───────────┐   │   │
│  │  │  server:0   │  │ agent:0   │  │ agent:1   │   │   │
│  │  │  (control   │  │           │  │           │   │   │
│  │  │   plane)    │  │           │  │           │   │   │
│  │  └─────────────┘  └───────────┘  └───────────┘   │   │
│  │                                                  │   │
│  │  ┌───────────────────────────────────────────┐   │   │
│  │  │  Load Balancer                            │   │   │
│  │  │  :3080 → NodePort 30080 (HTTP)            │   │   │
│  │  │  :3443 → NodePort 30443 (HTTPS)           │   │   │
│  │  └───────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  API Server: ${CURRENT_IP}:6443                         │
│  Shared volume: ${SHARED_PATH} → /mnt/shared            │
└─────────────────────────────────────────────────────────┘
```

## Requirements

Only two host-level dependencies are needed — `mise` manages everything else.

| Tool | Purpose | Install |
|------|---------|---------|
| **Docker** | Container runtime for k3d nodes | [docs.docker.com](https://docs.docker.com/engine/install/ubuntu/) |
| **mise** | Tool version manager (bootstraps all CLIs) | Bundled as `./mise` script |

The following tools are automatically installed and pinned by `mise`:

| Tool | Version | Purpose |
|------|---------|---------|
| `age` | latest | Encryption key generation |
| `direnv` | latest | Directory-scoped environment variables |
| `flux2` | latest | GitOps operator CLI |
| `k3d` | latest | K3s-in-Docker cluster manager |
| `kubectl` | latest | Kubernetes CLI |
| `sops` | latest | Secret encryption/decryption |
| `task` | latest | Task runner |
| `uv` | latest | Python package manager |

## Configuration

Key environment variables (auto-populated by `mise`):

| Variable | Description | Default |
|----------|-------------|---------|
| `CLUSTER_NAME` | k3d cluster name | `default` |
| `CURRENT_IP` | Host IP used for the kube API server | Auto-detected |
| `CURRENT_EXTERNAL_IP` | Public IP added to TLS SANs | Auto-detected via `ipinfo.io` |
| `K3S_VERSION` | K3s image tag | Latest release (auto-fetched) |
| `SHARED_PATH` | Host path mounted to `/mnt/shared` on all nodes | `~/projects` |
| `SOPS_AGE_KEY_FILE` | Path to your age private key | `~/.config/sops/age/keys.txt` |
| `SOPS_AGE_RECIPIENTS` | Age public key for encrypting secrets | Read from `.sops.pub.asc` |
| `ISSUER_EMAIL` | Email for cert-manager ACME issuers | `yourname@gmail.com` |

Override any variable in a local `.env` file (gitignored) or by editing `mise.toml`.

## Quickstart

```bash
# 1. Bootstrap mise and all tools
./mise install

# 2. (Optional) Configure your SOPS age key
#    Generate a new key:
age-keygen -o ~/.config/sops/age/keys.txt
#    Or copy an existing key to ~/.config/sops/age/keys.txt

# 3. Create the k3d cluster
./mise run create-cluster

# 4. Bootstrap core infrastructure (Flux, cert-manager, Gateway API CRDs)
./mise run bootstrap

# 5. Verify everything is running
kubectl get pods -A
flux check
```

## Available Tasks

| Task | Alias | Description |
|------|-------|-------------|
| `./mise run create-cluster` | `cc` | Create the k3d cluster and `infrastructure` namespace |
| `./mise run bootstrap` | `bt` | Apply bootstrap kustomization (Flux, cert-manager, CRDs) and SOPS age secret |
| `./mise run delete-cluster` | `dc` | Destroy the k3d cluster |

Run `./mise tasks` to see all available tasks.

## Cluster Details

**Topology:** 1 server (control plane) + 2 agents

**Disabled K3s components** (managed externally or not needed for local dev):

- `traefik` — replace with your own ingress/gateway
- `servicelb` — replace with MetalLB or similar
- `metrics-server` — install via Flux if needed

**Port forwards (host → cluster load balancer):**

| Host Port | Cluster NodePort | Protocol |
|-----------|-----------------|----------|
| `3080` | `30080` | HTTP |
| `3443` | `30443` | HTTPS |
| `6443` | `6443` | Kubernetes API |

**TLS SANs** automatically include both `CURRENT_IP` and `CURRENT_EXTERNAL_IP` so the API server is reachable from the host and externally.

**Shared volume:** `${SHARED_PATH}` is mounted at `/mnt/shared` on all nodes, useful for `local-path` persistent volumes.

## Secret Management

Secrets are encrypted with [SOPS](https://getsops.io/) using [age](https://age-encryption.org/). The encryption rules are defined in [.sops.yaml](.sops.yaml):

- Files matching `*.sops.yaml` / `*.sops.yml` are encrypted
- Only the fields `data`, `stringData`, `externalName`, `tls`, `rules`, `value`, `key` are encrypted (metadata remains in plaintext)
- The recipient public key is stored in [.sops.pub.asc](.sops.pub.asc)

```bash
# Encrypt a new secret file
sops --encrypt --in-place path/to/secret.sops.yaml

# Edit an encrypted file
sops path/to/secret.sops.yaml

# Decrypt to stdout (never commit decrypted secrets)
sops --decrypt path/to/secret.sops.yaml
```

The `bootstrap/sops-age.sops.yaml` secret is applied during bootstrap to give Flux access to your age private key for decrypting secrets in the cluster.

### Scripts

| Script | Description |
|--------|-------------|
| `scripts/find-unencrypted-secrets.sh` | Detects any secret files that were committed without SOPS encryption |
| `scripts/install_git_hooks.sh` | Installs pre-commit hooks to prevent accidental secret commits |
| `scripts/validate.sh` | Validates YAML manifests for correctness |

Install the git hooks once after cloning:

```bash
./scripts/install_git_hooks.sh
```

## Troubleshooting

**Cluster fails to start:**

```bash
# Check k3d logs
k3d cluster list
docker logs k3d-default-server-0

# Re-create with debug output
k3d cluster delete default
./mise run create-cluster
```

**kubectl cannot reach the API server:**

```bash
# Verify the kubeconfig was updated
kubectl config current-context
kubectl cluster-info

# Check current IP matches what's in your kubeconfig
echo $CURRENT_IP
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```

**Flux controllers not healthy:**

```bash
flux check
kubectl get pods -n flux-system
kubectl get events -n flux-system --sort-by='.lastTimestamp'
```

**SOPS decryption errors:**

```bash
# Verify age key is present
ls ~/.config/sops/age/keys.txt
# Verify key matches the recipient in .sops.pub.asc
cat .sops.pub.asc
age-keygen -y ~/.config/sops/age/keys.txt  # prints the public key
```

## License

Apache 2.0 — see [LICENSE](LICENSE).
