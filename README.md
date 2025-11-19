# Experimentation Repository

This repository automates the full lifecycle for creating Kubernetes clusters, installing L2S-CES/Submariner, deploying monitoring, and running experiments.
Everything is orchestrated through a **single Makefile workflow** that provisions infrastructure, configures clusters using **Kubespray**, and prepares monitoring endpoints.

---

# Quick Start

## 1. Install Dependencies

All binaries (`terraform`, `go`, `kustomize`) are downloaded locally into `./local/bin`.

```bash
make deps
```

This creates:

```
local/
 ├── bin/           # terraform, go, kustomize, yq, etc.
 └── configs/
      ├── ansible/  # generated inventories
      ├── k8s/      # per-cluster kubeconfigs
      ├── prometheus/
      ├── terraform/
      └── tmp/
```

---

# Build and Configure Clusters

The full cluster lifecycle is:

```
Terraform → Kubespray → Monitoring
```

To execute the entire pipeline:

```bash
make build
```

This performs:

1. **clean** – Remove old state and local configs
2. **deps** – Ensure binaries exist
3. **tf-apply** – Apply Terraform and create VMs
4. **inventory** – Generate Ansible inventories from Terraform outputs
5. **ansible** – Use Kubespray to install Kubernetes on each cluster
6. **monitoring** – Install cAdvisor & node-exporter on workers + deploy Prometheus operator

---

# Individual Commands

### Apply or re-apply infrastructure

```bash
make tf-apply
```

### Generate Kubespray inventories manually

```bash
make inventory
```

### Run Kubespray against inventories

```bash
make ansible
```

### Deploy monitoring stack

(cAdvisor, node_exporter, Prometheus, Grafana)

```bash
make monitoring
```

### Merge generated kubeconfigs

Creates `local/configs/kubeconfig` containing all clusters.

```bash
make kubeconfig
```

---

# Running Experiments

All experiments live in:

```
experiments/<experiment-name>/
```

Each experiment has its own capture scripts, plotting code, and README.

Notable experiment types:

* `cpu_usage` – Resource utilization over time
* `multicast` – Multicast transmission results (L2S-CES / Submariner)
* `pods_tcpdump` – Cross-cluster packet captures
* `setuptime` – Setup-time benchmarks

Results are typically written inside:

```
experiments/<experiment-name>/captures/
experiments/<experiment-name>/<files>.csv
plots (.png, .pdf)
MATLAB and R scripts
```

---

# Installing L2S-CES or Submariner

Installers are located in:

```
installation/l2sces/
installation/submariner/
```

Examples:

```bash
installation/l2sces/install.sh
installation/submariner/install.sh
```

These scripts assume clusters are already provisioned and kubeconfigs exist in:

```
local/configs/k8s/
```

---

# Monitoring Stack

The monitoring pipeline installs:

* **cAdvisor** (port 9101)
* **node_exporter** (port 9102)
* **Prometheus Operator**
* **Grafana**

Prometheus scrape targets are generated from Terraform outputs:

```
local/configs/prometheus/cmmap.yaml
```

Prometheus manifests live in:

```
monitoring/prometheus/
```

