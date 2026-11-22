#!/bin/zsh
set -eu
cd -- "${0:A:h}"
make build
open "build/MacAgentDisplay.app"
