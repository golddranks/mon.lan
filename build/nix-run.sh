#!/bin/sh
set -eu

nix shell .#lima --command ./lima-run.sh "$@"
