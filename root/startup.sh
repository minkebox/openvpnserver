#! /bin/sh

PROTO=udp
DDNS_DOMAIN=minkebox.net
PRIVATE_HOSTNAME=${__GLOBALID}

ROOT=/etc/openvpn
SERVER_CONFIG_TAP=${ROOT}/minke-server.ovpn
SERVER_CONFIG_TUN=${ROOT}/minke-server-tun.ovpn
CLIENT_CONFIG_TAP=${ROOT}/minke-client.ovpn
CLIENT_CONFIG_TUN=${ROOT}/minke-client-tun.ovpn
ORIGINAL_CLIENT_CONFIG_TAP=/etc/config-alt.ovpn
ORIGINAL_CLIENT_CONFIG_TUN=/etc/config.ovpn
TTL=600 # 10 minutes
TTL2=300 # TTL/2
SERVER_NETWORK_TUN=10.224.76.0
SERVER_BRIDGE=

NAT_IP=$(ip addr show dev ${__NAT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
BRIDGE_IP=$(ip addr show dev ${__DEFAULT_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
BRIDGE_IP_ROOT=$(echo ${BRIDGE_IP} | sed "s/^\(\d\+.\d\+.\d\+\).*$/\1/")
if [ "${__DEFAULT_INTERFACE}" = "${__INTERNAL_INTERFACE}" ]; then
  SERVER_BRIDGE="${BRIDGE_IP} 255.255.255.0 ${BRIDGE_IP_ROOT}.238 ${BRIDGE_IP_ROOT}.254"
fi

PATH=$PATH:/usr/share/easy-rsa

export EASYRSA_VARS_FILE=/etc/easyrsa.vars

# Generate server config
if [ ! -e ${ROOT}/config-done ]; then
  cd ${ROOT}
  rm -rf pki
  easyrsa init-pki
  EASYRSA_BATCH=1 easyrsa build-ca nopass
  easyrsa gen-dh
  openvpn --genkey --secret pki/ta.key
  easyrsa build-server-full minke-simple-vpn nopass
  easyrsa gen-crl
  touch config-done
  cd /
fi

if [ ! -e ${CLIENT_CONFIG_TAP} ]; then
  PORT_TUN=${SELECTED_PORT}
  PORT_TAP=$((${PORT_TUN} + 1))
  # Generate the client config
  cd ${ROOT}
  easyrsa build-client-full minke-client nopass
  cd /
  echo "#
# OPENVPN configuration:
#  Host: ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN}
#  Port ${PORT_TAP}
#  Protocol: UDP
#
client
nobind
dev tap
persist-key
persist-tun
remote-cert-tls server
remote ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN} ${PORT_TAP} ${PROTO}
key-direction 1
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
push-peer-info
<key>
$(cat ${ROOT}/pki/private/minke-client.key)
</key>
<cert>
$(cat ${ROOT}/pki/issued/minke-client.crt)
</cert>
<ca>
$(cat ${ROOT}/pki/ca.crt)
</ca>
<tls-auth>
$(cat ${ROOT}/pki/ta.key)
</tls-auth>" > ${CLIENT_CONFIG_TAP}
fi

if [ ! -e ${CLIENT_CONFIG_TUN} ]; then
  echo "#
# OPENVPN configuration:
#  Host: ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN}
#  Port ${PORT_TUN}
#  Protocol: UDP
#
client
nobind
dev tun
persist-key
persist-tun
remote-cert-tls server
remote ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN} ${PORT_TUN} ${PROTO}
key-direction 1
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
push-peer-info
<key>
$(cat ${ROOT}/pki/private/minke-client.key)
</key>
<cert>
$(cat ${ROOT}/pki/issued/minke-client.crt)
</cert>
<ca>
$(cat ${ROOT}/pki/ca.crt)
</ca>
<tls-auth>
$(cat ${ROOT}/pki/ta.key)
</tls-auth>" > ${CLIENT_CONFIG_TUN}
fi

# Make them retrievable
cat ${CLIENT_CONFIG_TAP} > ${ORIGINAL_CLIENT_CONFIG_TAP}
cat ${CLIENT_CONFIG_TUN} > ${ORIGINAL_CLIENT_CONFIG_TUN}

# Extract port from client config
PORT_TAP=$(grep "^remote " ${CLIENT_CONFIG_TAP} | sed "s/^remote .* \(\d\+\) .*/\1/")
PORT_TUN=$(grep "^remote " ${CLIENT_CONFIG_TUN} | sed "s/^remote .* \(\d\+\) .*/\1/")

# Always generate the server config (in case the network changed so SERVER_BRIDGE has changed)
echo "server-bridge ${SERVER_BRIDGE}
port ${PORT_TAP}
proto ${PROTO}
dev tap0
key-direction 0
persist-key
persist-tun
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
duplicate-cn
client-to-client
explicit-exit-notify 1
keepalive 10 60
txqueuelen 1000
fast-io
<ca>
$(cat ${ROOT}/pki/ca.crt)
</ca>
<cert>
$(cat ${ROOT}/pki/issued/minke-simple-vpn.crt)
</cert>
<key>
$(cat ${ROOT}/pki/private/minke-simple-vpn.key)
</key>
<tls-auth>
$(cat ${ROOT}/pki/ta.key)
</tls-auth>
<dh>
$(cat ${ROOT}/pki/dh.pem)
</dh>" > ${SERVER_CONFIG_TAP}

echo "server ${SERVER_NETWORK_TUN} 255.255.255.0
port ${PORT_TUN}
proto ${PROTO}
dev tun0
key-direction 0
persist-key
persist-tun
push \"route ${BRIDGE_IP_ROOT}.0 255.255.255.0\"
push \"dhcp-option DNS ${__DNSSERVER}\"
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
duplicate-cn
client-to-client
explicit-exit-notify 1
keepalive 10 60
txqueuelen 1000
fast-io
<ca>
$(cat ${ROOT}/pki/ca.crt)
</ca>
<cert>
$(cat ${ROOT}/pki/issued/minke-simple-vpn.crt)
</cert>
<key>
$(cat ${ROOT}/pki/private/minke-simple-vpn.key)
</key>
<tls-auth>
$(cat ${ROOT}/pki/ta.key)
</tls-auth>
<dh>
$(cat ${ROOT}/pki/dh.pem)
</dh>" > ${SERVER_CONFIG_TUN}

trap "killall sleep openvpn; exit" TERM INT

# Premake devices
openvpn --mktun --dev tap0
openvpn --mktun --dev tun0

# Replace default monitoring
iptables -D OUTPUT -j TX
iptables -D INPUT -j RX
iptables -I OUTPUT -o tap0 -j TX
iptables -I INPUT -i tap0 -j RX
iptables -I OUTPUT -o tun0 -j TX
iptables -I INPUT -i tun0 -j RX

# Bridge the TAP vpn
brctl addbr br0
ifconfig ${__DEFAULT_INTERFACE} 0.0.0.0 up
ifconfig tap0 0.0.0.0 up
ifconfig br0 ${BRIDGE_IP} netmask 255.255.255.0 up
# Bridge inherits "main" network mac address
/sbin/ip link set br0 address $(cat /sys/class/net/${__DEFAULT_INTERFACE}/address)
brctl addif br0 ${__DEFAULT_INTERFACE}
brctl addif br0 tap0
ip route add default via ${__GATEWAY} dev br0

# Masquarade the TUN vpn
iptables -t nat -I POSTROUTING -o br0 -s ${SERVER_NETWORK_TUN}/24 -j MASQUERADE

openvpn --daemon --config ${SERVER_CONFIG_TAP}
openvpn --daemon --config ${SERVER_CONFIG_TUN}

sleep 2147483647d &
wait "$!"
