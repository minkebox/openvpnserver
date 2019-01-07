FROM alpine:edge

RUN apk --no-cache add openvpn easy-rsa miniupnpd avahi ;\
    rm -f /etc/openvpn/* /etc/miniupnpd/* /etc/avahi/services/*.service /etc/avahi/avahi-daemon.conf

COPY root/ /

VOLUME /etc/openvpn

EXPOSE 1194/tcp 1194/udp

ENTRYPOINT ["/startup.sh"]
