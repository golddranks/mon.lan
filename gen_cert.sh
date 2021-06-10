#!/bin/sh -eu

SERIAL=02

cat << EOF > cert/mon.lan.cfg
subjectAltName = DNS:mon.lan, DNS:mon
EOF
openssl ecparam -genkey -name prime256v1 -out cert/mon.lan.key
openssl req -new -key cert/mon.lan.key -outform PEM -keyform PEM  -sha256 -out cert/mon.lan.csr -subj "/C=JP/ST=Tokyo/O=Pyry Kontio/CN=mon.lan"
openssl x509 -req -in cert/mon.lan.csr -sha256 -CA cert/inca.pem -CAkey cert/inca.key -set_serial "0x${SERIAL}2" -days 730 -extfile cert/mon.lan.cfg -out cert/mon.lan.pem
cat cert/mon.lan.pem > cert/mon.lan.chain.pem
cat cert/inca.pem >> cert/mon.lan.chain.pem
cat cert/rootca.pem >> cert/mon.lan.chain.pem