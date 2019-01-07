#! /bin/sh

INTERNAL_INTERFACE=eth0
EXTERNAL_INTERFACE=tun0


if [ ! -e /etc/openvpn/pki ]; then
  EASYRSA=/usr/share/easy-rsa/easyrsa
  cd /etc/openvpn
  ${EASYRSA} init-pki
  EASYRSA_BATCH=1 ${EASYRSA} build-ca nopass
  ${EASYRSA} gen-dh
  openvpn --genkey --secret ta.key
  ${EASYRSA} build-server-full minke nopass
  ${EASYRSA} gen-crl
  cd /
fi

cat > /etc/openvpn.conf <<__EOF__
port 1194
proto udp
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
/usr/sbin/openvpn --config /etc/openvpn.conf --daemon

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
allow 0-65535 172.17.0.0/16 0-65535
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
