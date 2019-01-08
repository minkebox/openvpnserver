#! /bin/sh

HOME_INTERFACE=eth0
INTERNAL_INTERFACE=eth1
EXTERNAL_INTERFACE=tun0
PROTO=udp
GLOBAL_HOSTNAME=157.131.142.82 # XXX FIXME XXX

PATH=$PATH:/usr/share/easy-rsa

if [ "${PORT}" = "" ]; then
  echo "No PORT set"
  exit 1
fi

IP=$(ip addr show dev ${HOME_INTERFACE} | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)

# Firewall setup
route del default

#iptables -P INPUT DROP
#iptables -P FORWARD DROP
#iptables -P OUTPUT ACCEPT

# Localhost okay
#iptables -A INPUT -i lo -j ACCEPT
#iptables -A OUTPUT -o lo -j ACCEPT

# Only accept incoming traffic if there's an outgoing connection already
#iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Generate server config
if [ ! -e /etc/openvpn/pki/crl.pem ]; then
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

# Generate client config
if [ ! -e /etc/openvpn/minke-client.ovpn ]; then
  cd /etc/openvpn
  easyrsa build-client-full minke-client nopass
  echo "
client
nobind
dev tun
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
$(cat /etc/openvpn/ta.key)
</tls-auth>
" > /etc/openvpn/minke-client.ovpn
  cd /
fi

echo "
port ${PORT}
local ${IP}
proto ${PROTO}
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
" > /etc/openvpn.conf
openvpn --config /etc/openvpn.conf --daemon

# NAT firewall (${INTERNAL_INTERFACE} -> ${EXTERNAL_INTERFACE})
iptables -t nat -A POSTROUTING -o ${EXTERNAL_INTERFACE} -j MASQUERADE
iptables -A FORWARD -i ${EXTERNAL_INTERFACE} -o ${INTERNAL_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i ${INTERNAL_INTERFACE} -o ${EXTERNAL_INTERFACE} -j ACCEPT

# UPNP
echo "
ext_ifname=${EXTERNAL_INTERFACE}
listening_ip=${INTERNAL_INTERFACE}
http_port=0
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
echo "
[server]
allow-interfaces=${EXTERNAL_INTERFACE},${INTERNAL_INTERFACE}
enable-dbus=no
allow-point-to-point=yes
[publish]
disable-publishing=yes
[reflector]
enable-reflector=yes
" > /etc/avahi-daemon.conf
avahi-daemon --no-drop-root --daemonize --file=/etc/avahi-daemon.conf
iptables -A INPUT -i ${EXTERNAL_INTERFACE} -p udp --dport 5353 -j ACCEPT

trap "killall sleep openvpn miniupnpd avahi-daemon; exit" TERM INT

sleep 2147483647d &
wait "$!"
