
LOCALBIN ?= $(shell pwd)/local/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

LOCALCONFIG ?= $(shell pwd)/local/configs
$(LOCALCONFIG):
	mkdir -p $(LOCALCONFIG)
	mkdir -p $(LOCALCONFIG)/ansible
	mkdir -p $(LOCALCONFIG)/terraform
	mkdir -p $(LOCALCONFIG)/tmp
	mkdir -p $(LOCALCONFIG)/k8s





SHELL:=/bin/bash

include config.env
export 

TERRAFORM:=$(LOCALBIN)/terraform
GO:=$(LOCALBIN)/go/bin/go
DOCKER?=docker

##@ Dependencies

.PHONY: deps

.PHONY: deps

deps: $(LOCALBIN) $(LOCALCONFIG) ## Check dependencies
	$(info Checking and getting dependencies)

	@if [ ! -f "$(TERRAFORM)" ]; then \
		echo "-> Downloading Terraform..."; \
		curl -sSL https://releases.hashicorp.com/terraform/1.12.2/terraform_1.12.2_linux_amd64.zip -o $(LOCALCONFIG)/tmp/terraform.zip; \
		unzip -qq -o $(LOCALCONFIG)/tmp/terraform.zip -d $(LOCALBIN); \
	else \
		echo "-> Terraform already exists at $(TERRAFORM)"; \
	fi

	@if [ ! -f "$(GO)" ]; then \
		echo "-> Downloading Go..."; \
		curl -sSL https://go.dev/dl/go1.25.0.linux-amd64.tar.gz -o $(LOCALCONFIG)/tmp/go1.25.0.linux-amd64.tar.gz; \
		rm -rf $(LOCALBIN)/go; \
		tar -C $(LOCALBIN) -xzf $(LOCALCONFIG)/tmp/go1.25.0.linux-amd64.tar.gz; \
	else \
		echo "-> Go already exists at $(GO)"; \
	fi


# terraform, ansible kubespray, gt crypt envsubst

##@ Cleanup

.PHONY: clean

clean: ## Cleanup the project folders
	$(info Cleaning up things)
	$(TERRAFORM) -chdir=terraform destroy 
	rm -r ./local/




##@ Building
.PHONY: build tf-apply tf-output inventory ansible clean deps

KUBESPRAY_VERSION ?= v2.28.0
KUBESPRAY_IMAGE   ?= quay.io/kubespray/kubespray:$(KUBESPRAY_VERSION)
OUTPUTS_JSON      ?= $(LOCALCONFIG)/terraform/outputs.json
INVENTORIES        = $(wildcard $(LOCALCONFIG)/ansible/inventory*.ini)

build: clean deps tf-apply inventory ansible      ## Full build (apply + ansible)

tf-apply: deps $(LOCALCONFIG)                                        ## Create/modify infra
	$(info Running terraform apply)
	$(ENVSUBST) < terraform/cloud-init/enable-password.yml.template > terraform/cloud-init/enable-password.yml
	$(TERRAFORM) -chdir=terraform apply -auto-approve -state=$(LOCALCONFIG)/terraform/terraform.tfstate


inventory: tf-apply                           ## Generate Ansible inventories from outputs
	@echo "Generating inventories from $(OUTPUTS_JSON)"
	$(GO) run ansible/generate_inventory.go \
		-input $(LOCALCONFIG)/terraform/terraform.tfstate \
		-outdir $(LOCALCONFIG)/ansible

ansible: inventory                                ## Run Kubespray against inventories
	@for inv in $(wildcard $(LOCALCONFIG)/ansible/inventory-*.ini); do \
	cluster=$$(basename $$inv | sed 's/inventory-\(.*\)\.ini/\1/'); \
	echo "----> Kubespray for $$cluster"; \
	kubeconfig_path="$(LOCALCONFIG)/k8s/"; \
	$(DOCKER) run --rm \
		--mount type=bind,source="$$HOME"/.ssh/id_rsa,dst=/root/.ssh/id_rsa \
		--mount type=bind,source="$(shell pwd)"/ansible/fetch_kubeconfig.yaml,dst=/fetch_kubeconfig.yaml \
		--mount type=bind,source="$$inv",dst=/inventory.ini,readonly \
		--mount type=bind,source="$$kubeconfig_path",dst=/output/ \
		$(KUBESPRAY_IMAGE) \
		bash -c "ansible-playbook \
		-i /inventory.ini \
		--private-key /root/.ssh/id_rsa \
		-e kube_network_plugin=flannel \
		-e enable_multus=true \
		cluster.yml && \
		ansible-playbook -i /inventory.ini -e cluster_name=$$cluster /fetch_kubeconfig.yaml"; \
	done

k8sconfig:                                 ## Run Kubespray against inventories
	@for inv in $(wildcard $(LOCALCONFIG)/ansible/inventory-*.ini); do \
	cluster=$$(basename $$inv | sed 's/inventory-\(.*\)\.ini/\1/'); \
	echo "----> Kubespray for $$cluster"; \
	kubeconfig_path="$(LOCALCONFIG)/k8s/"; \
	$(DOCKER) run --rm \
		--mount type=bind,source="$$HOME"/.ssh/id_rsa,dst=/root/.ssh/id_rsa \
		--mount type=bind,source="$(shell pwd)"/ansible/fetch_kubeconfig.yaml,dst=/fetch_kubeconfig.yaml \
		--mount type=bind,source="$$inv",dst=/inventory.ini,readonly \
		--mount type=bind,source="$$kubeconfig_path",dst=/output/ \
		$(KUBESPRAY_IMAGE) \
		bash -c "ansible-playbook -i /inventory.ini -e cluster_name=$$cluster /fetch_kubeconfig.yaml"; \
	done
prerequisites:
	@for kc in $(wildcard $(LOCALCONFIG)/k8s/kubeconfig-*); do \
	cluster=$$(basename $$kc | sed 's/^kubeconfig-//')


install: prerequisites
# (keep your clean/deps targets as they were)

##@ Helpers

.PHONY: help

help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
