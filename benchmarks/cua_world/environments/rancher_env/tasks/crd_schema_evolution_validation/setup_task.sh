#!/bin/bash
echo "=== Setting up crd_schema_evolution_validation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Clean up any existing state
docker exec rancher kubectl delete crd databases.platform.local --wait=false 2>/dev/null || true
sleep 5

# 1. Create the initial CRD (without backupRetentionDays)
echo "Creating initial databases.platform.local CRD..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.platform.local
spec:
  group: platform.local
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                engine:
                  type: string
                storage:
                  type: string
  scope: Namespaced
  names:
    plural: databases
    singular: database
    kind: Database
    shortNames:
    - db
MANIFEST

# Wait for CRD to be established
echo "Waiting for CRD to be established..."
docker exec rancher kubectl wait --for condition=established --timeout=30s crd/databases.platform.local 2>/dev/null || true

# 2. Create the ticket describing the task
echo "Creating ticket on desktop..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/TICKET-881.txt << 'TICKET'
TICKET-881: CRD Schema Evolution for Backup Retention
Priority: High

Developers are getting strict decoding errors ("unknown field") when using the new `backupRetentionDays` field in their Database manifests. 

Update the `databases.platform.local` CRD schema to allow this property under `spec`. For compliance, it MUST be an `integer` with a `minimum` value of 7.

The billing team's blocked manifest (at ~/Desktop/billing-db.yaml) requested 3 days, which violates our new policy. I've received their approval to bump it to 30 days instead.

Please update their manifest to use 30 days and apply it to the cluster to unblock them.
TICKET

# 3. Create the blocked developer manifest
echo "Creating blocked developer manifest..."
cat > /home/ga/Desktop/billing-db.yaml << 'MANIFEST'
apiVersion: platform.local/v1
kind: Database
metadata:
  name: billing-db
  namespace: default
spec:
  engine: postgres
  storage: 100Gi
  backupRetentionDays: 3
MANIFEST

# Set permissions so the ga user can read/edit them easily
chown -R ga:ga /home/ga/Desktop

# Maximize and focus Firefox if it's running
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="