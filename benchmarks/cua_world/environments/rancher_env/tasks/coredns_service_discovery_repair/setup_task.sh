#!/bin/bash
# Setup script for coredns_service_discovery_repair task
# Injects 4 failures into CoreDNS:
#   1. Deployment replicas scaled to 0
#   2. Corefile cluster domain changed to cluster.broken
#   3. Corefile forward directive points to 10.0.0.1
#   4. kube-dns Service port changed to 5353

echo "=== Setting up coredns_service_discovery_repair task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# ── Deploy a background workload to ensure cluster has observable resources ─
docker exec rancher kubectl create namespace staging 2>/dev/null || true
docker exec rancher kubectl create deployment nginx-web --image=nginx:alpine -n staging 2>/dev/null || true

# ── Python script to safely patch CoreDNS objects ───────────────────────────
cat << 'EOF' > /tmp/inject_dns_failures.py
import json
import subprocess
import re
import sys
import time

def run(cmd):
    return subprocess.check_output(cmd, text=True)

try:
    print("Fetching coredns ConfigMap...")
    cm_json = run(['docker', 'exec', 'rancher', 'kubectl', 'get', 'cm', 'coredns', '-n', 'kube-system', '-o', 'json'])
    cm = json.loads(cm_json)
    corefile = cm['data']['Corefile']
    
    # Inject Failure 2: Wrong cluster domain
    corefile = corefile.replace('cluster.local', 'cluster.broken')
    
    # Inject Failure 3: Wrong upstream forwarder
    # Default is usually "forward . /etc/resolv.conf"
    corefile = re.sub(r'forward \. .*', 'forward . 10.0.0.1', corefile)
    
    cm['data']['Corefile'] = corefile
    
    with open('/tmp/patched_cm.json', 'w') as f:
        json.dump(cm, f)
    run(['docker', 'cp', '/tmp/patched_cm.json', 'rancher:/tmp/patched_cm.json'])
    print("Applying corrupted ConfigMap...")
    run(['docker', 'exec', 'rancher', 'kubectl', 'apply', '-f', '/tmp/patched_cm.json'])

    print("Fetching kube-dns Service...")
    svc_json = run(['docker', 'exec', 'rancher', 'kubectl', 'get', 'svc', 'kube-dns', '-n', 'kube-system', '-o', 'json'])
    svc = json.loads(svc_json)
    
    # Inject Failure 4: Wrong ports
    for p in svc['spec']['ports']:
        if p.get('port') == 53: p['port'] = 5353
        if p.get('targetPort') == 53: p['targetPort'] = 5353
        
    with open('/tmp/patched_svc.json', 'w') as f:
        json.dump(svc, f)
    run(['docker', 'cp', '/tmp/patched_svc.json', 'rancher:/tmp/patched_svc.json'])
    print("Applying corrupted Service...")
    run(['docker', 'exec', 'rancher', 'kubectl', 'apply', '-f', '/tmp/patched_svc.json'])

except Exception as e:
    print(f"Error injecting failures: {e}")
    sys.exit(1)
EOF

echo "Running failure injection script..."
python3 /tmp/inject_dns_failures.py

# ── Inject Failure 1: Scale deployment to 0 ─────────────────────────────────
echo "Scaling CoreDNS to 0 replicas..."
docker exec rancher kubectl scale deployment coredns -n kube-system --replicas=0

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
sleep 10

# ── Record Baseline ─────────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="