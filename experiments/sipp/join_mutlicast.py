import socket
import struct
import time

MCAST_GRP = '239.0.0.1'
MCAST_IF_IP = '10.0.0.1' # Your Server net1 IP

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)

# CRITICAL CHANGE: Bind to 8888, NOT 5060
sock.bind((MCAST_GRP, 8888)) 

# This registers the membership for the whole interface
mreq = socket.inet_aton(MCAST_GRP) + socket.inet_aton(MCAST_IF_IP)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

print(f"Joined {MCAST_GRP} on {MCAST_IF_IP}. Holding membership active...")

while True:
    time.sleep(100)