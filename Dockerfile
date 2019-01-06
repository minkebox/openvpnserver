FROM alpine:edge

RUN apk --no-cache add openvpn easy-rsa

COPY root/ /

VOLUME /etc/openvpn

EXPOSE 1194/tcp 1194/udp

ENTRYPOINT ["/startup.sh"]
