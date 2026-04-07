#!/bin/bash
echo "=== Exporting oomkilled_quota_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/oomkilled_remediation_end.png

# Fetch objects in the data-processing namespace
docker exec rancher kubectl get deploy,rs,po,quota -n data-processing -o json > /tmp/dp_objects.json 2>/dev/null || echo '{"items":[]}' > /tmp/dp_objects.json

# Parse the cluster state via Python
python3 << 'EOF'
import json

def parse_mi(val):
    if not val: return 0
    val = str(val).strip()
    if val.endswith('Gi'): return float(val[:-2]) * 1024
    if val.endswith('Mi'): return float(val[:-2])
    if val.endswith('G'): return float(val[:-1]) * 1024
    if val.endswith('M'): return float(val[:-1])
    try:
        return float(val) / (1024 * 1024)
    except Exception:
        return 0

try:
    with open('/tmp/dp_objects.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {"items": []}

result = {
    "batch_analyzer": {},
    "stream_router": {},
    "quota": {}
}

for item in data.get('items', []):
    kind = item.get('kind')
    name = item.get('metadata', {}).get('name', '')

    if kind == 'Deployment' and name == 'batch-analyzer':
        containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
        if containers:
            c = containers[0]
            result["batch_analyzer"]["container_spec_str"] = json.dumps(c)
            mem_limit = c.get('resources', {}).get('limits', {}).get('memory', '0')
            result["batch_analyzer"]["limit_mi"] = parse_mi(mem_limit)

    elif kind == 'Deployment' and name == 'stream-router':
        containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
        result["stream_router"]["replicas"] = item.get('spec', {}).get('replicas', 0)
        if containers:
            c = containers[0]
            mem_limit = c.get('resources', {}).get('limits', {}).get('memory', '0')
            result["stream_router"]["limit_mi"] = parse_mi(mem_limit)

    elif kind == 'ResourceQuota' and name == 'processing-quota':
        mem_limit = item.get('spec', {}).get('hard', {}).get('limits.memory', '0')
        result["quota"]["limit_mi"] = parse_mi(mem_limit)

    elif kind == 'Pod':
        labels = item.get('metadata', {}).get('labels', {})
        phase = item.get('status', {}).get('phase', '')
        if labels.get('app') == 'batch-analyzer':
            if 'running_pods' not in result["batch_analyzer"]:
                result["batch_analyzer"]["running_pods"] = 0
            if phase == 'Running':
                result["batch_analyzer"]["running_pods"] += 1

with open('/tmp/oomkilled_remediation_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure file is globally readable for the python verifier
chmod 666 /tmp/oomkilled_remediation_result.json 2>/dev/null || sudo chmod 666 /tmp/oomkilled_remediation_result.json 2>/dev/null || true

echo "Result exported to /tmp/oomkilled_remediation_result.json"
cat /tmp/oomkilled_remediation_result.json
echo "=== Export Complete ==="