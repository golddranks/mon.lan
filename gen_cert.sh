#!/bin/sh -eu

cat << EOF > mon.lan.conf
[req]
distinguished_name  = req_distinguished_name
x509_extensions     = v3_req
prompt              = no
string_mask         = utf8only

[req_distinguished_name]
C                   = JP
L                   = Tokyo
CN                  = mon.lan

[v3_req]
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth
subjectAltName      = @alt_names

[alt_names]
DNS.1               = mon.lan
IP.1                = 192.168.1.1
EOF

openssl req -x509 -nodes -days 730 -newkey rsa:2048 -keyout mon.lan.key -out mon.lan.crt -config mon.lan.conf
