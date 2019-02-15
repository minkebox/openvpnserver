#! /bin/sh

HOME_INTERFACE=$1
GLOBAL_HOSTNAME=$2
DOMAIN=$3
DDNS_URL="http://dynamicdns.park-your-domain.com/update"
PASSWORD=10e6e53e63f4433e986bf4641d4d4cc9

last_ip=""

sleep 0 &
while wait "$!"; do
  IP=$(upnpc -m ${HOME_INTERFACE} -s | grep ExternalIPAddress | sed "s/^.*= //")
  if [ "${IP}" != "${last_ip}" ]; then
    wget -q -O - "${DDNS_URL}?host=${GLOBAL_HOSTNAME}&domain=${DOMAIN}&password=${PASSWORD}&ip=${IP}"
    last_ip="${IP}"
  fi
  sleep 3600 &
done
