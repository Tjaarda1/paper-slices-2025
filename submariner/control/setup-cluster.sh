CLUSTER_NAME=control
DIRECTORY=$(pwd)/submariner/$(CLUSTER_NAME)
KUBECONFIG=$(DIRECTORY)/kubeconfig
kind create cluster --kubeconfig $KUBECONFIG --config $(DIRECTORY)/cluster.yaml

wget -q https://github.com/containernetworking/plugins/releases/download/v1.6.0/cni-plugins-linux-amd64-v1.6.0.tgz
mkdir -p plugins/bin
tar -xf cni-plugins-linux-amd64-v1.6.0.tgz -C plugins/bin
rm cni-plugins-linux-amd64-v1.6.0.tgz

# copy necessary plugins into all nodes
docker cp ./plugins/bin/. sub-$(CLUSTER_NAME)-control-plane:/opt/cni/bin
docker cp ./plugins/bin/. sub-$(CLUSTER_NAME)-worker:/opt/cni/bin
docker cp ./plugins/bin/. sub-$(CLUSTER_NAME)-worker2:/opt/cni/bin
docker exec -it sub-$(CLUSTER_NAME)-control-plane modprobe br_netfilter
docker exec -it sub-$(CLUSTER_NAME)-worker modprobe br_netfilter
docker exec -it sub-$(CLUSTER_NAME)-worker2 modprobe br_netfilter

docker exec -it sub-$(CLUSTER_NAME)-control-plane sysctl -p /etc/sysctl.conf
docker exec -it sub-$(CLUSTER_NAME)-worker sysctl -p /etc/sysctl.conf
docker exec -it sub-$(CLUSTER_NAME)-worker2 sysctl -p /etc/sysctl.conf


kubectl --kubeconfig $KUBECONFIG apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl --kubeconfig $KUBECONFIG wait --for=condition=Ready pods -n kube-flannel -l app=flannel --timeout=300s

