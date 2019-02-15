FROM alpine:edge

RUN apk --no-cache add openvpn easy-rsa bridge-utils miniupnpc ;\
    rm -f /etc/openvpn/*

COPY root/ /

VOLUME /etc/openvpn

ENTRYPOINT ["/startup.sh"]
