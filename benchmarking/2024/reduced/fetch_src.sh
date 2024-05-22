#!/bin/bash

set -eu

fetch_src() {
  if [ ! -e everythingsreduced/src/main.cpp ]; then
    if ! git clone -b main https://github.com/milthorpe/everythingsreduced; then
      echo
      echo "Failed to fetch source code."
      echo
      exit 1

    fi
  else
    (
      cd everythingsreduced
      # git fetch && git pull
    )
  fi
  export SRC_DIR="$PWD/everythingsreduced"
}
