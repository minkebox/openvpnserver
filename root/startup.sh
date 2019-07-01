#! /bin/sh

HOME_INTERFACE=${__HOME_INTERFACE}
PRIVATE_INTERFACE=${__PRIVATE_INTERFACE}
EXTERNAL_INTERFACE=tap0
PROTO=udp
DDNS_DOMAIN=minkebox.net
PRIVATE_HOSTNAME=${__GLOBALID}

ROOT=/etc/openvpn
SERVER_CONFIG=${ROOT}/minke-server.ovpn
CLIENT_CONFIG=${ROOT}/minke-client.ovpn
ORIGINAL_CLIENT_CONFIG=/etc/config.ovpn
PORTRANGE_START=41310
PORTRANGE_LEN=256
TTL=600 # 10 minutes
TTL2=300 # TTL/2
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

if [ ! -e ${CLIENT_CONFIG} ]; then

  # Select an unused port at random from within our standard range avoiding any we see as in use
  active_ports=$(upnpc -m ${HOME_INTERFACE} -L | grep "^ *\d\? UDP\|TCP .*$" | sed "s/^.*:\(\d*\).*$/\1/")
  while true ; do
    PORT=$((${PORTRANGE_START} + RANDOM % ${PORTRANGE_LEN}))
    if ! $(echo $active_ports | grep -q ${PORT}); then
      break;
    fi
  done

  # Generate the client config
  cd ${ROOT}
  easyrsa build-client-full minke-client nopass
  cd /
  echo "client
nobind
dev ${EXTERNAL_INTERFACE}
persist-key
persist-tun
remote-cert-tls server
remote ${PRIVATE_HOSTNAME}.${DDNS_DOMAIN} ${PORT} ${PROTO}
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
</tls-auth>" > ${CLIENT_CONFIG}
fi

# Make it retrievable
cat ${CLIENT_CONFIG} > ${ORIGINAL_CLIENT_CONFIG}

# Extract port from client config
PORT=$(grep "^remote " ${CLIENT_CONFIG} | sed "s/^remote .* \(\d\+\) .*/\1/")

# Always generate the server config (in case the network changed so SERVER_BRIDGE has changed)
echo "server-bridge ${SERVER_BRIDGE}
port ${PORT}
proto ${PROTO}
dev ${EXTERNAL_INTERFACE}
key-direction 0
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
</dh>
persist-key
persist-tun
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
duplicate-cn
client-to-client
explicit-exit-notify 1
keepalive 10 60" > ${SERVER_CONFIG}

trap "upnpc -m br0 -d ${PORT} ${PROTO}; killall sleep openvpn; exit" TERM INT

# Bridge
openvpn --mktun --dev ${EXTERNAL_INTERFACE}

brctl addbr br0
ifconfig ${BRIDGE_INTERFACE} 0.0.0.0 up
ifconfig ${EXTERNAL_INTERFACE} 0.0.0.0 up
ifconfig br0 ${BRIDGE_IP} netmask 255.255.255.0 up
brctl addif br0 ${EXTERNAL_INTERFACE}
brctl addif br0 ${BRIDGE_INTERFACE}
route add default gw ${__GATEWAY}

openvpn --daemon --config ${SERVER_CONFIG}

# Open the NAT
sleep 1 &
while wait "$!"; do
  upnpc -e ${HOSTNAME} -a ${HOME_IP} ${PORT} ${PORT} ${PROTO} ${TTL}
  sleep ${TTL2} &
done
upnpc -d ${PORT} ${PROTO}
