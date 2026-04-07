#!/bin/bash
# Export script for ephemeral_storage_eviction_remediation task

echo "=== Exporting ephemeral_storage_eviction_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot for VLM / debugging
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Dump the relevant K8s API states to JSON
echo "Gathering Deployment state..."
docker exec rancher kubectl get deploy ml-inference -n ml-workloads -o json > /tmp/deploy.json 2>/dev/null || echo "{}" > /tmp/deploy.json

echo "Gathering ResourceQuota state..."
docker exec rancher kubectl get resourcequota -n ml-workloads -o json > /tmp/quotas.json 2>/dev/null || echo '{"items":[]}' > /tmp/quotas.json

echo "Gathering Pod states..."
docker exec rancher kubectl get pods -n ml-workloads -l app=ml-inference -o json > /tmp/pods.json 2>/dev/null || echo '{"items":[]}' > /tmp/pods.json

# Combine into a single result JSON file using Python
python3 -c '
import json, sys

try:
    with open("/tmp/deploy.json") as f: deploy = json.load(f)
except Exception: 
    deploy = {}

try:
    with open("/tmp/quotas.json") as f: quotas = json.load(f)
except Exception: 
    quotas = {"items":[]}

try:
    with open("/tmp/pods.json") as f: pods = json.load(f)
except Exception: 
    pods = {"items":[]}

result = {
    "deploy": deploy,
    "quotas": quotas,
    "pods": pods
}

with open("/tmp/ephemeral_storage_eviction_result.json", "w") as f:
    json.dump(result, f)
'

# Ensure the file has appropriate permissions to be copied by the verifier
chmod 666 /tmp/ephemeral_storage_eviction_result.json

echo "Result JSON written to /tmp/ephemeral_storage_eviction_result.json"
echo "=== Export Complete ==="