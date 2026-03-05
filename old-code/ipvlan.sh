#! /usr/bin/bash
export DEFAULT_IFACE=$(ip route | grep "default" | head -n 1 | awk '{print $5}')
export DEFAULT_GATEWAY=$(ip route | grep "default" | head -n 1 | awk '{print $3}')
export CURRENT_IP=$(ip addr show ${DEFAULT_IFACE} | grep "inet " | awk '{print $2}' | cut -d '/' -f 1 | tr -d ' ' | head -n 1)
export VLAN="89"

(docker container rm -f network_test > /dev/null 2>&1 ; docker network rm ipvlan_network > /dev/null 2>&1)

DRIVER="ipvlan" # macvlan
FLAGS="--subnet=10.${VLAN}.${VLAN}.0/24 --ip-range=10.${VLAN}.${VLAN}.64/26 --gateway=10.${VLAN}.${VLAN}.1 -o parent=${DEFAULT_IFACE}.${VLAN}"

if ! docker network inspect ipvlan_network > /dev/null 2>&1; then
    docker network create -d ${DRIVER} ${FLAGS} -o ipvlan_mode=l2 ipvlan_network
fi

docker container inspect network_test > /dev/null 2>&1 || docker run -itd --rm --network ipvlan_network --ip 10.${VLAN}.${VLAN}.${VLAN} --name network_test nicolaka/netshoot
# docker exec network_test ip address show
# docker exec network_test ip route show
docker exec network_test ping -c 3 8.8.8.8
# docker exec network_test nslookup www.google.com
