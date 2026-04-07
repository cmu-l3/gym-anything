#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Dump all CronJobs in the target namespace to JSON
docker exec rancher kubectl get cronjob -n data-platform -o json > /tmp/cronjobs.json 2>/dev/null || echo '{"items":[]}' > /tmp/cronjobs.json

# Parse necessary fields securely using Python
python3 << 'PYEOF'
import json

try:
    with open('/tmp/cronjobs.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {"items": []}

result = {
    "hourly_backup": {},
    "legacy_export": {}
}

for item in data.get("items", []):
    name = item.get("metadata", {}).get("name")
    spec = item.get("spec", {})
    
    if name == "hourly-backup":
        result["hourly_backup"] = {
            "exists": True,
            "concurrencyPolicy": spec.get("concurrencyPolicy", "Allow"),
            "successfulJobsHistoryLimit": spec.get("successfulJobsHistoryLimit"),
            "failedJobsHistoryLimit": spec.get("failedJobsHistoryLimit"),
            "job_activeDeadlineSeconds": spec.get("jobTemplate", {}).get("spec", {}).get("activeDeadlineSeconds"),
            "pod_activeDeadlineSeconds": spec.get("jobTemplate", {}).get("spec", {}).get("template", {}).get("spec", {}).get("activeDeadlineSeconds")
        }
    elif name == "legacy-export":
        result["legacy_export"] = {
            "exists": True,
            "suspend": spec.get("suspend", False)
        }

with open('/tmp/batch_cronjob_governance_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "Result saved to /tmp/batch_cronjob_governance_result.json"
cat /tmp/batch_cronjob_governance_result.json
echo "=== Export complete ==="