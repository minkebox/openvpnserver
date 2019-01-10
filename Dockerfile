FROM alpine:edge

RUN apk --no-cache add openvpn easy-rsa miniupnpd nodejs npm ;\
    rm -f /etc/openvpn/* /etc/miniupnpd/*

COPY root/ /

RUN cd /mDNS ; npm install

VOLUME /etc/openvpn

ENTRYPOINT ["/startup.sh"]
