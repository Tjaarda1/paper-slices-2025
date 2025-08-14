package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type TFState struct {
	Outputs struct {
		ClusterIPs struct {
			Value map[string]NodeInfo `json:"value"`
		} `json:"cluster_ips"`
	} `json:"outputs"`
}

type NodeInfo struct {
	Cluster string `json:"cluster"`
	IP      string `json:"ip"`
	Role    string `json:"role"` // e.g. "control-node" | "worker-node"
}

func main() {
	// Inputs / outputs
	in := flag.String("i", "./locals/config/terraform/terraform.tfstate", "path to terraform tfstate (JSON)")
	out := flag.String("o", "-", "output path for the generated ConfigMap YAML (use '-' for stdout)")
	ns := flag.String("namespace", "prometheus", "ConfigMap namespace")
	cmName := flag.String("cm-name", "prometheus-config", "ConfigMap name")

	// Ports
	nodePort := flag.Int("node-port", 9100, "node_exporter port")
	cadvPort := flag.Int("cadvisor-port", 8080, "cAdvisor port")

	// Optional extra job "prometheus" static targets (comma-separated list)
	promTargetsCSV := flag.String("prom-targets", "", "comma-separated list of additional targets for 'prometheus' job (e.g. '1.2.3.4:9090,5.6.7.8:9090'). If empty, the job is omitted.")

	flag.Parse()

	// Read tfstate
	raw, err := os.ReadFile(*in)
	dieIf(err, "reading input tfstate")

	var st TFState
	dieIf(json.Unmarshal(raw, &st), "parsing tfstate JSON")

	if len(st.Outputs.ClusterIPs.Value) == 0 {
		die("no outputs.cluster_ips.value found in tfstate")
	}

	// Collect IPs (stable, deduped)
	ipsSet := map[string]struct{}{}
	for _, v := range st.Outputs.ClusterIPs.Value {
		if v.IP == "" {
			continue
		}
		ipsSet[v.IP] = struct{}{}
	}
	ips := make([]string, 0, len(ipsSet))
	for ip := range ipsSet {
		ips = append(ips, ip)
	}
	sort.Strings(ips)

	// Build targets
	nodeTargets := make([]string, 0, len(ips))
	cadvTargets := make([]string, 0, len(ips))
	for _, ip := range ips {
		nodeTargets = append(nodeTargets, fmt.Sprintf("%s:%d", ip, *nodePort))
		cadvTargets = append(cadvTargets, fmt.Sprintf("%s:%d", ip, *cadvPort))
	}

	// Extra 'prometheus' job targets (optional)
	promTargets := []string{}
	if strings.TrimSpace(*promTargetsCSV) != "" {
		for _, t := range strings.Split(*promTargetsCSV, ",") {
			t = strings.TrimSpace(t)
			if t != "" {
				promTargets = append(promTargets, t)
			}
		}
		// Stabilize order
		sort.Strings(promTargets)
	}

	// Render ConfigMap YAML
	yaml := renderConfigMap(*ns, *cmName, promTargets, nodeTargets, cadvTargets)

	// Write
	if *out == "-" {
		fmt.Print(yaml)
		return
	}
	dieIf(os.MkdirAll(filepath.Dir(*out), 0o755), "creating output directory")
	dieIf(os.WriteFile(*out, []byte(yaml), 0o644), "writing output file")
	fmt.Printf("✓ wrote ConfigMap to %s\n", *out)
}

func renderConfigMap(namespace, name string, promTargets, nodeTargets, cadvTargets []string) string {
	var b strings.Builder

	// Header
	fmt.Fprintf(&b, "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: %s\n  namespace: %s\n", name, namespace)
	b.WriteString("data:\n  prometheus.yml: |-\n")
	// prometheus.yml content
	b.WriteString("    global:\n")
	b.WriteString("      scrape_interval: 15s\n")
	b.WriteString("      evaluation_interval: 15s\n\n")
	b.WriteString("    scrape_configs:\n")

	// Optional 'prometheus' job
	if len(promTargets) > 0 {
		b.WriteString("      - job_name: 'prometheus'\n")
		b.WriteString("        static_configs:\n")
		b.WriteString("          - targets:\n")
		for _, t := range promTargets {
			fmt.Fprintf(&b, "            - \"%s\"\n", t)
		}
	}

	// node-exporter job
	b.WriteString("      - job_name: 'node-exporter'\n")
	b.WriteString("        static_configs:\n")
	b.WriteString("          - targets:\n")
	for _, t := range nodeTargets {
		fmt.Fprintf(&b, "            - \"%s\"\n", t)
	}

	// cadvisor job
	b.WriteString("      - job_name: 'cadvisor'\n")
	b.WriteString("        static_configs:\n")
	b.WriteString("          - targets:\n")
	for _, t := range cadvTargets {
		fmt.Fprintf(&b, "            - \"%s\"\n", t)
	}

	return b.String()
}

func dieIf(err error, ctx string) {
	if err != nil {
		die(fmt.Sprintf("%s: %v", ctx, err))
	}
}

func die(msg string) {
	fmt.Fprintln(os.Stderr, "error:", msg)
	os.Exit(1)
}
