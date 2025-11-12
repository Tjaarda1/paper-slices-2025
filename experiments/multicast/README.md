first enable multicast and broadcast w/ enable-mcast-cni0.sh
deploy workloads: 
./experiments/multicast/sub/deploy_workload.sh
./experiments/multicast/l2sces/deploy_workload.sh

Pre script: 
 kubectl debug $POD --kubeconfig local/configs/kubeconfig --context $CTX  -n $NS  --image=busybox:1.36  -it --   sh -lc 'sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 && cat /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts'

then run the scripts ./experiments/multicast/sub/tcpdumper.sh and ./experiments/multicast/l2sces/tcpdumper.sh
Captures in: ./experiments/multicast/captures/<day>_<time>