#!/bin/bash

set -ex

export CONNECTED_CLUSTER_NAME=""
export RESOURCE_GROUP=""
export LAW_NAME=""

if [[ -z "${CONNECTED_CLUSTER_NAME}" || -z "${RESOURCE_GROUP}" || -z "${LAW_NAME}" ]]; then
  echo "Please ensure the exported variables in the 'setup' script are defined."
  exit 1
fi

./azure-monitor-setup.sh
./flux-setup.sh
