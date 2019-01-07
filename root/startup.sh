#! /bin/sh

HOME_INTERFACE=eth0
INTERNAL_INTERFACE=eth1
EXTERNAL_INTERFACE=tun0
PROTO=udp

if [ "${PORT}" = "" ]; then
  echo "No PORT set"
  exit 1
fi

IP=$(ip addr show dev ${HOME_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)

# Block all in and out traffic (except openvpn) on the ${HOME_INTERFACE}
#iptables -A INPUT -i ${HOME_INTERFACE} -p ${PROTO} --dport ${PORT} -j ACCEPT
#iptables -A OUTPUT -i ${HOME_INTERFACE} -p ${PROTO} --sport ${PORT} -j ACCEPT
#iptables -A INPUT -i ${HOME_INTERFACE} -j DROP
#iptables -A OUTPUT -i ${HOME_INTERFACE} -j DROP
route del default

if [ ! -e /etc/openvpn/pki/crl.pem ]; then
  PATH=$PATH:/usr/share/easy-rsa
  cd /etc/openvpn
  rm -rf pki ta.key
  easyrsa init-pki
  EASYRSA_BATCH=1 easyrsa build-ca nopass
  easyrsa gen-dh
  openvpn --genkey --secret ta.key
  easyrsa build-server-full minke nopass
  easyrsa gen-crl
  cd /
fi

echo "port ${PORT}" > /etc/openvpn.conf
echo "local ${IP}" >> /etc/openvpn.conf
echo "proto ${PROTO}" >> /etc/openvpn.conf
cat >> /etc/openvpn.conf <<__EOF__
dev tun
ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/issued/minke.crt
key /etc/openvpn/pki/private/minke.key
dh /etc/openvpn/pki/dh.pem
tls-auth /etc/openvpn/ta.key 0
topology subnet
server 10.20.30.0 255.255.255.0
persist-tun
persist-key
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
keepalive 10 120
__EOF__
openvpn --config /etc/openvpn.conf --daemon

# NAT firewall (${INTERNAL_INTERFACE} -> ${EXTERNAL_INTERFACE})
iptables -t nat -A POSTROUTING -o ${EXTERNAL_INTERFACE} -j MASQUERADE
iptables -A FORWARD -i ${EXTERNAL_INTERFACE} -o ${INTERNAL_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i ${INTERNAL_INTERFACE} -o ${EXTERNAL_INTERFACE} -j ACCEPT

# UPNP
echo "ext_ifname=${EXTERNAL_INTERFACE}" > /etc/miniupnpd.conf
echo "listening_ip=${INTERNAL_INTERFACE}" >> /etc/miniupnpd.conf
cat >> /etc/miniupnpd.conf <<__EOF__
http_port=0
enable_natpmp=no
enable_upnp=yes
min_lifetime=120
max_lifetime=86400
secure_mode=no
notify_interval=60
allow 0-65535 172.0.0.0/8 0-65535
deny 0-65535 0.0.0.0/0 0-65535
__EOF__
miniupnpd -f /etc/miniupnpd.conf

# mDNS reflector
echo "[server]" > /etc/avahi-daemon.conf
echo "allow-interfaces=${EXTERNAL_INTERFACE},${INTERNAL_INTERFACE}" >> /etc/avahi-daemon.conf
cat >> /etc/avahi-daemon.conf <<__EOF__
enable-dbus=no
allow-point-to-point=yes
[publish]
disable-publishing=yes
[reflector]
enable-reflector=yes
__EOF__
avahi-daemon --no-drop-root --daemonize --file=/etc/avahi-daemon.conf
iptables -A INPUT -i ${EXTERNAL_INTERFACE} -p udp --dport 5353 -j ACCEPT

trap "killall sleep openvpn miniupnpd avahi-daemon; exit" TERM INT

sleep 2147483647d &
wait "$!"
