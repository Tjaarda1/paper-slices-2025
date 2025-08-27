go run ./local/bin/l2sm-md/test --test-network-create

kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-1.yaml apply -f experiments/multicast/l2sm/server.yaml -n l2sm-system 
kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-2.yaml apply -f experiments/multicast/l2sm/sub-1.yaml -n l2sm-system 
kubectl --kubeconfig local/configs/k8s/kubeconfig-l2sm-managed-2.yaml apply -f experiments/multicast/l2sm/sub-2.yaml -n l2sm-system 
