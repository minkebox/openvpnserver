#! /bin/sh

HOME_INTERFACE=eth0
INTERNAL_INTERFACE=eth1
EXTERNAL_INTERFACE=tun0
PROTO=udp
GLOBAL_HOSTNAME=157.131.142.82 # XXX FIXME XXX

# EXTERNAL_INTERFACE
EXTERNAL_NET=10.20.30.0
EXTERNAL_MASK=255.255.255.248
EXTERNAL_LOCAL_IP=10.20.30.1
EXTERNAL_REMOTE_IP=10.20.30.2

PATH=$PATH:/usr/share/easy-rsa

if [ "${PORT}" = "" ]; then
  echo "No PORT set"
  exit 1
fi

HOME_IP=$(ip addr show dev ${HOME_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
INTERNAL_IP=$(ip addr show dev ${INTERNAL_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)


# Firewall setup
route del default

# HOME_INTERFACE
# Allow traffic in and out if we've started a connection out
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT -i ${HOME_INTERFACE}
# Allow OpenVPN traffic in and out (tcp or udp)
iptables -A INPUT  -p ${PROTO} --dport ${PORT} -j ACCEPT -i ${HOME_INTERFACE}
iptables -A OUTPUT -p ${PROTO} --sport ${PORT} -j ACCEPT -o ${HOME_INTERFACE}
# Allow DHCP traffic in and out
iptables -A INPUT  -p udp --dport 68 -j ACCEPT -i ${HOME_INTERFACE}
iptables -A OUTPUT -p udp --sport 68 -j ACCEPT -o ${HOME_INTERFACE}
# Allow UPnP traffic in and out
iptables -A INPUT  -p udp --sport 1900 -j ACCEPT -i ${HOME_INTERFACE}
iptables -A OUTPUT -p udp --dport 1900 -j ACCEPT -o ${HOME_INTERFACE}
# Block all other outgoing UDP traffic
iptables -A OUTPUT -p udp -j DROP -o ${HOME_INTERFACE}
# Drop anything else incoming
iptables -A INPUT  -j DROP -i ${HOME_INTERFACE}


# Generate server config
if [ ! -e /etc/openvpn/pki/crl.pem ]; then
  cd /etc/openvpn
  rm -rf pki
  easyrsa init-pki
  EASYRSA_BATCH=1 easyrsa build-ca nopass
  easyrsa gen-dh
  openvpn --genkey --secret pki/ta.key
  easyrsa build-server-full minke nopass
  easyrsa gen-crl
  cd /
fi

# Generate client config
if [ ! -e /etc/openvpn/minke-client.ovpn ]; then
  cd /etc/openvpn
  easyrsa build-client-full minke-client nopass
  echo "
client
nobind
dev ${EXTERNAL_INTERFACE}
persist-tun
persist-key
remote-cert-tls server
remote ${GLOBAL_HOSTNAME} ${PORT} ${PROTO}
key-direction 1
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
<key>
$(cat /etc/openvpn/pki/private/minke-client.key)
</key>
<cert>
$(cat /etc/openvpn/pki/issued/minke-client.crt)
</cert>
<ca>
$(cat /etc/openvpn/pki/ca.crt)
</ca>
<tls-auth>
$(cat /etc/openvpn/pki/ta.key)
</tls-auth>
" > /etc/openvpn/minke-client.ovpn
  cd /
fi

echo "
port ${PORT}
local ${HOME_IP}
proto ${PROTO}
dev ${EXTERNAL_INTERFACE}
key-direction 0
<ca>
$(cat /etc/openvpn/pki/ca.crt)
</ca>
<cert>
$(cat /etc/openvpn/pki/issued/minke.crt)
</cert>
<key>
$(cat /etc/openvpn/pki/private/minke.key)
</key>
<tls-auth>
$(cat /etc/openvpn/pki/ta.key)
</tls-auth>
<dh>
$(cat /etc/openvpn/pki/dh.pem)
</dh>
topology subnet
server ${EXTERNAL_NET} ${EXTERNAL_MASK}
persist-tun
persist-key
cipher AES-256-CBC
auth SHA256
ncp-ciphers AES-256-GCM
keepalive 10 120
" > /etc/openvpn/minke-server.ovpn
openvpn --config /etc/openvpn/minke-server.ovpn --daemon --script-security 2 --up "/usr/bin/env EXTERNAL_INTERFACE=${EXTERNAL_INTERFACE} INTERNAL_INTERFACE=${INTERNAL_INTERFACE} EXTERNAL_REMOTE_IP=${EXTERNAL_REMOTE_IP} /vpn-up.sh"

trap "killall sleep openvpn miniupnpd node; exit" TERM INT

sleep 2147483647d &
wait "$!"
