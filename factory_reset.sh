#!/bin/sh -eu

ssh root@mon.lan -p 222 "firstboot -y && reboot now"
