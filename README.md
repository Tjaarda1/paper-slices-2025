# Experimentation Repository README

## Initial Setup

1. **Install prerequisites** in each virtual machine environment:

```bash
./common/install_requisites.sh
```

2. **Set up **``** for kubeconfigs**:

From the parent virtual machine, initialize `git-crypt` and export the key:

```bash
git-crypt init
git-crypt export .gitcryptkey
```

If using multiple virtual machines, securely copy the `.gitcryptkey` to each additional machine:

```bash
scp ./paper-slices-2025/.gitcryptkey <user>@<ip>:/home/<user>/paper-slices-2025/.gitcryptkey
```

This allows safe sharing of kubeconfigs via GitHub and simultaneous use across multiple virtual machines.

## Running the Experiments

Run the following commands from the root directory only:

1. **Set up clusters**:

```bash
./common/setup_cluster.sh <l2sces|submariner> <control|managed-n>
```

2. **Install the components**:

```bash
./<l2sces|submariner>/install.sh
```

3. **Execute experiments**:

```bash
./experiments/<experiment-name>/start.sh
```

## Viewing Experiment Results

Results are stored at:

```bash
./experiments/<experiment-name>/<date>
```

Date format: `+%d%m%y_%H%M%S`

Example:

```bash
./experiments/multicast/290725_165543/graph.png
```

## Directory Structure

- `./common`:

  - Contains scripts and templates shared by both L2SM and Submariner experiments, including Prometheus installation, cluster setup scripts, and common templates.

- `./experiments`:

  - Includes experiment-specific scripts for both L2SM and Submariner.
  - Running `./start.sh` initiates an automated pipeline, producing graphs and CSV results.
  - Each experiment iteration is saved in a timestamped subdirectory with relevant documentation.

- `./l2sces | ./submariner`:

  - Contains environment-specific templates and final configurations.
  - `control`, `managed-1`, and `managed-2` directories represent individual clusters with solution-specific templates.

**IMPORTANT:** Always run scripts from the repository's **root directory**. Scripts are not path-independent.



cadvisor: 9101
node exporter: 9102
