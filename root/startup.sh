#! /bin/sh

HOME_INTERFACE=${__HOME_INTERFACE}
PRIVATE_INTERFACE=${__PRIVATE_INTERFACE}
PROTO=udp
DDNS_DOMAIN=minkebox.net
PRIVATE_HOSTNAME=${__GLOBALID}

ROOT=/etc/openvpn
SERVER_CONFIG_TAP=${ROOT}/minke-server.ovpn
SERVER_CONFIG_TUN=${ROOT}/minke-server-tun.ovpn
CLIENT_CONFIG_TAP=${ROOT}/minke-client.ovpn
CLIENT_CONFIG_TUN=${ROOT}/minke-client-tun.ovpn
ORIGINAL_CLIENT_CONFIG_TAP=/etc/config.ovpn
ORIGINAL_CLIENT_CONFIG_TUN=/etc/config-alt.ovpn
PORTRANGE_START=41310
PORTRANGE_LEN=256
TTL=600 # 10 minutes
TTL2=300 # TTL/2
SERVER_NETWORK_TUN=10.224.76.0
SERVER_BRIDGE=

HOME_IP=$(ip addr show dev ${HOME_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
if [ "${PRIVATE_INTERFACE}" != "" ]; then
  BRIDGE_IP=$(ip addr show dev ${PRIVATE_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
  BRIDGE_INTERFACE=${PRIVATE_INTERFACE}
  BRIDGE_IP_ROOT=$(echo ${BRIDGE_IP} | sed "s/^\(\d\+.\d\+.\d\+\).*$/\1/")
  SERVER_BRIDGE="${BRIDGE_IP} 255.255.255.0 ${BRIDGE_IP_ROOT}.238 ${BRIDGE_IP_ROOT}.254"
else
  BRIDGE_IP=${HOME_IP}
  BRIDGE_INTERFACE=${HOME_INTERFACE}
  BRIDGE_IP_ROOT=$(echo ${BRIDGE_IP} | sed "s/^\(\d\+.\d\+.\d\+\).*$/\1/")
fi


PATH=$PATH:/usr/share/easy-rsa

export EASYRSA_VARS_FILE=/etc/easyrsa.vars

# Prime random
RANDOM=$(head -1 /dev/urandom | cksum)

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

  # Select an unused port at random from within our standard range avoiding any we see as in use
  active_ports=$(upnpc -u ${__UPNPURL} -m ${HOME_INTERFACE} -L | grep "^ *\d\? UDP\|TCP .*$" | sed "s/^.*:\(\d*\).*$/\1/")
  while true ; do
    PORT_TAP=$((${PORTRANGE_START} + RANDOM % ${PORTRANGE_LEN}))
    PORT_TUN=$((${PORT_TAP} + 1))
    if ! $(echo $active_ports | grep -q ${PORT_TAP}); then
      if ! $(echo $active_ports | grep -q ${PORT_TUN}); then
        break;
      fi
    fi
  done

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

# Extract port from client config
PORT_TAP=$(grep "^remote " ${CLIENT_CONFIG_TAP} | sed "s/^remote .* \(\d\+\) .*/\1/")
PORT_TUN=$((${PORT_TAP} + 1))

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

trap "upnpc -u ${__UPNPURL} -d ${PORT_TAP} ${PROTO}; upnpc -u ${__UPNPURL} -d ${PORT_TUN} ${PROTO}; killall sleep openvpn; exit" TERM INT

# Premake devices
openvpn --mktun --dev tap0
openvpn --mktun --dev tun0

# Bridge the TAP vpn
brctl addbr br0
ifconfig ${BRIDGE_INTERFACE} 0.0.0.0 up
ifconfig tap0 0.0.0.0 up
ifconfig br0 ${BRIDGE_IP} netmask 255.255.255.0 up
# Bridge inherits "main" network mac address
/sbin/ip link set br0 address $(cat /sys/class/net/${BRIDGE_INTERFACE}/address)
brctl addif br0 ${BRIDGE_INTERFACE}
brctl addif br0 tap0
route add default gw ${__GATEWAY}

# Masquarade the TUN vpn
iptables -t nat -I POSTROUTING -o br0 -s ${SERVER_NETWORK_TUN}/24 -j MASQUERADE

openvpn --daemon --config ${SERVER_CONFIG_TAP}
openvpn --daemon --config ${SERVER_CONFIG_TUN}

# Open the NAT
sleep 1 &
while wait "$!"; do
  upnpc -u ${__UPNPURL} -e ${HOSTNAME}_tap -a ${HOME_IP} ${PORT_TAP} ${PORT_TAP} ${PROTO} ${TTL}
  upnpc -u ${__UPNPURL} -e ${HOSTNAME}_tun -a ${HOME_IP} ${PORT_TUN} ${PORT_TUN} ${PROTO} ${TTL}
  if [ "${__HOSTIP6}" != "" ]; then
    upnpc -u ${__UPNPURL} -e ${HOSTNAME}_tap6 -6 -A "" 0 ${__HOSTIP6} ${PORT_TAP} ${PROTO} ${TTL}
    upnpc -u ${__UPNPURL} -e ${HOSTNAME}_tun6 -6 -A "" 0 ${__HOSTIP6} ${PORT_TUN} ${PROTO} ${TTL}
  fi
  sleep ${TTL2} &
done
upnpc -u ${__UPNPURL} -d ${PORT_TAP} ${PROTO}
upnpc -u ${__UPNPURL} -d ${PORT_TUN} ${PROTO}
