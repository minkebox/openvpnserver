#! /bin/sh

# INTERNAL_INTERFACE <-> EXTERNAL_INTERFACE
# UPnP traffic handled locally
iptables -t nat -A PREROUTING -p udp --dport 1900 -j ACCEPT -i ${INTERNAL_INTERFACE}
iptables -t nat -A PREROUTING -p tcp --dport 1900 -j ACCEPT -i ${INTERNAL_INTERFACE}
# mDNS traffic handled locally
iptables -t nat -A PREROUTING -p udp --dport 5353 -j ACCEPT -i ${INTERNAL_INTERFACE}
iptables -A INPUT -p udp --dport 5353 -j ACCEPT -i ${EXTERNAL_INTERFACE}
# Everything else we forward
iptables -t nat -A PREROUTING  -j DNAT --to-destination ${EXTERNAL_REMOTE_IP} -i ${INTERNAL_INTERFACE}
iptables -t nat -A POSTROUTING -j MASQUERADE -o ${EXTERNAL_INTERFACE}
iptables -t nat -A POSTROUTING -j MASQUERADE -o ${INTERNAL_INTERFACE}
# And we drop anything incoming we don't have a rule for
#iptables -A INPUT -j DROP -i ${EXTERNAL_INTERFACE}

# UPNP
iptables -t nat -N MINIUPNPD
iptables -t nat -A PREROUTING -i ${EXTERNAL_INTERFACE} -j MINIUPNPD
echo "
ext_ifname=${EXTERNAL_INTERFACE}
listening_ip=${INTERNAL_INTERFACE}
http_port=1900
enable_natpmp=no
enable_upnp=yes
min_lifetime=120
max_lifetime=86400
secure_mode=no
notify_interval=60
allow 0-65535 172.0.0.0/8 0-65535
deny 0-65535 0.0.0.0/0 0-65535
" > /etc/miniupnpd.conf
miniupnpd -f /etc/miniupnpd.conf

# mDNS reflector
/mDNS/index.js ${EXTERNAL_INTERFACE} ${INTERNAL_INTERFACE} &
