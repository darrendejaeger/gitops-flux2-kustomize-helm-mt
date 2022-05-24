#!/bin/bash

set -ex

RESOURCE_GROUP="${RESOURCE_GROUP:-}"
CONNECTED_CLUSTER_NAME="${CONNECTED_CLUSTER_NAME:-}"

flux_config_prov_state="$(az k8s-configuration flux show -g ${RESOURCE_GROUP} --cluster-name ${CONNECTED_CLUSTER_NAME} --cluster-type connectedClusters --name cluster-config -o tsv --query provisioningState || true)"
if [ -z "$flux_config_prov_state" ]; then
    az k8s-configuration flux create \
    -g "${RESOURCE_GROUP}" \
    -c "${CONNECTED_CLUSTER_NAME}" \
    -n cluster-config \
    --namespace cluster-config \
    -t connectedClusters \
    --scope cluster \
    -u https://github.com/darrendejaeger/gitops-flux2-kustomize-helm-mt \
    --branch main \
    --kustomization name=infra path=./infrastructure prune=true --kustomization name=apps path=./apps/staging prune=true dependsOn=["infra"]
fi
