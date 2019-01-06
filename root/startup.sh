#! /bin/sh

create_keys() {
  cd /etc/openvpn
  easyrsa init-pki
  easyrsa build-ca nopass
  easyrsa gen-dh
  openvpn --genkey --secret ???/ta.key
  easyrsa build-server-full "???_VN" nopass
  easyrsa gen-crl
  cd /
}

create_conf() {
}

setup() {
  create_keys
  create_conf
}

if [ ! -f /etc/openvpn.conf ]; then
  setup
fi

/usr/sbin/openvpn --config /etc/openvpn/openvpn.conf --daemon

trap "killall openvpn; exit" TRAP INT

sleep 2147483647d
wait "$!"
