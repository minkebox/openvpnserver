#! /bin/sh

HOME_INTERFACE=$1
GLOBAL_HOSTNAME=$2
DDNS_URL="https://minkebox.net/update"

last_ip=""

sleep 0 &
while wait "$!"; do
  IP=$(upnpc -m ${HOME_INTERFACE} -s | grep ExternalIPAddress | sed "s/^.*= //")
  if [ "${IP}" != "${last_ip}" ]; then
    wget --no-check-certificate -q -O - "${DDNS_URL}?host=${GLOBAL_HOSTNAME}&ip=${IP}"
    last_ip="${IP}"
  fi
  sleep 3600 &
done
