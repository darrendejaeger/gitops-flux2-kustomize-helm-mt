#!/bin/bash

set -ex

RESOURCE_GROUP="${RESOURCE_GROUP:-}"
CONNECTED_CLUSTER_NAME="${CONNECTED_CLUSTER_NAME:-}"
LAW_NAME="${LAW_NAME:-}"

# Ensure the LAW exists. If not, create it.
law_resource_id="$(az monitor log-analytics workspace show -g ${RESOURCE_GROUP} -n ${LAW_NAME} -o tsv --query id || true)"
if [ -z "$law_resource_id" ]; then
  law_resource_id="$(az monitor log-analytics workspace create \
    -n ${LAW_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --sku PerGB2018 \
    --retention-time 30 \
    -o tsv --query id)"
fi

# Enable the Azure Monitor extension on the Arc connected cluster
mon_extension_prov_state="$(az k8s-extension show -g ${RESOURCE_GROUP} --cluster-name ${CONNECTED_CLUSTER_NAME} --cluster-type connectedClusters --name azuremonitor-containers -o tsv --query provisioningState || true)"
if [ -z "$mon_extension_prov_state" ]; then
  az k8s-extension create --name azuremonitor-containers \
    --cluster-name "${CONNECTED_CLUSTER_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-type connectedClusters \
    --extension-type Microsoft.AzureMonitor.Containers \
    --configuration-settings logAnalyticsWorkspaceResourceID="$law_resource_id"
fi

# Deploy the workbook to the LAW if it's not already there
workbook_name="jd-nginx-workbook"
nginx_workbook_dg="$(az deployment group show -g ${RESOURCE_GROUP} --name ${workbook_name} -o tsv --query 'properties.provisioningState' || true )"
if [ -z "$nginx_workbook_dg" ]; then
    az deployment group create --no-prompt --no-wait \
      --name ${workbook_name} \
      --resource-group "${RESOURCE_GROUP}" \
      --template-file nginx-workbook.json \
      --parameters workspaceLAW="${LAW_NAME}"
    az deployment group wait --created \
      --name ${workbook_name} \
      --resource-group "${RESOURCE_GROUP}" \
      --interval 10 --timeout 120
fi

# Create the configmap in the cluster that will pick up on the nginx metrics service that will come in via Flux
cat <<EOF > azm-cm.yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: container-azm-ms-agentconfig
  namespace: kube-system
data:
  schema-version:
    #string.used by agent to parse config. supported versions are {v1}. Configs with other schema versions will be rejected by the agent.
    v1
  config-version:
    #string.used by customer to keep track of this config file's version in their source control/repository (max allowed 10 chars, other chars will be truncated)
    ver1
  prometheus-data-collection-settings: |-
    [prometheus_data_collection_settings.cluster]
        interval = "1m"
        # Pod monitoring leverages prometheus scrape annotations
        monitor_kubernetes_pods = true
        # Additional service monitoring endpoints
        kubernetes_services = [
          "http://nginx-ingress-controller-metrics.nginx.svc.cluster.local:9913/metrics"
        ]

EOF
kubectl apply -f azm-cm.yaml
