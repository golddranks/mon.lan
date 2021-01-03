#!/bin/sh -eu

source secrets.sh

scp -q remote.sh root@192.168.1.1:
ssh root@192.168.1.1 "./remote.sh $PPP_ID $PPP_PW $WIFI_PW"
