#!/bin/sh -eu

mkdir -p cert


openssl ecparam -genkey -name prime256v1 -out cert/rootca.key
openssl req  -new -x509 -key cert/rootca.key -sha256  -days 1825 -extensions v3_ca -out cert/rootca.pem -subj "/C=JP/ST=Tokyo/O=Pyry Kontio/CN=Pyry Kontio's private root CA 2021"


openssl ecparam -genkey -name prime256v1 -out cert/inca.key
cat << EOF > cert/inca.cnf
[ v3_ca ]
basicConstraints = CA:true, pathlen:0
keyUsage = cRLSign, keyCertSign
nsCertType = sslCA, emailCA
EOF
openssl req -new -key cert/inca.key -sha256 -outform PEM -keyform PEM -out cert/inca.csr -subj "/C=JP/ST=Tokyo/O=Pyry Kontio/CN=Pyry Kontio's private intermediate CA 2021"
openssl x509 -extfile cert/inca.cnf -req -in cert/inca.csr -sha256 -CA cert/rootca.pem -CAkey cert/rootca.key -set_serial 05 -extensions v3_ca -days 1825 -out cert/inca.pem
