#!/bin/bash
# Setup script for crd_rbac_aggregation_integration task
# Installs a CRD with a status subresource, deploys an operator with missing RBAC,
# and prepares the environment for the agent.

echo "=== Setting up crd_rbac_aggregation_integration task ==="

source /workspace/scripts/task_utils.sh

echo "Waiting for Rancher API..."
if ! wait_for_rancher_api 60; then
    echo "WARNING: Rancher API not ready"
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ── Clean up previous state ───────────────────────────────────────────────────
echo "Cleaning up previous state..."
docker exec rancher kubectl delete namespace data-system --wait=false 2>/dev/null || true
docker exec rancher kubectl delete crd datapipelines.etl.data.com --wait=false 2>/dev/null || true
sleep 10

# ── Deploy CRD ────────────────────────────────────────────────────────────────
echo "Deploying CustomResourceDefinition..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: datapipelines.etl.data.com
spec:
  group: etl.data.com
  names:
    kind: DataPipeline
    plural: datapipelines
    singular: datapipeline
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    subresources:
      status: {}
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            x-kubernetes-preserve-unknown-fields: true
MANIFEST

# Wait for CRD to be established
echo "Waiting for CRD to be established..."
for i in {1..30}; do
    if docker exec rancher kubectl get crd datapipelines.etl.data.com | grep -q "True"; then
        break
    fi
    sleep 2
done

# ── Deploy Operator Namespace and ServiceAccount ─────────────────────────────
echo "Creating operator namespace and service account..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: v1
kind: Namespace
metadata:
  name: data-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipeline-operator
  namespace: data-system
MANIFEST

# ── Deploy Defective ClusterRole and Binding ──────────────────────────────────
# Intentionally missing permissions on datapipelines/status
echo "Creating defective pipeline-operator-role..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pipeline-operator-role
rules:
- apiGroups: ["etl.data.com"]
  resources: ["datapipelines"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pipeline-operator-binding
subjects:
- kind: ServiceAccount
  name: pipeline-operator
  namespace: data-system
roleRef:
  kind: ClusterRole
  name: pipeline-operator-role
  apiGroup: rbac.authorization.k8s.io
MANIFEST

# ── Deploy Operator Pod (Dummy) ───────────────────────────────────────────────
echo "Deploying operator dummy pod..."
docker exec -i rancher kubectl apply -f - <<'MANIFEST'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pipeline-operator
  namespace: data-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pipeline-operator
  template:
    metadata:
      labels:
        app: pipeline-operator
    spec:
      serviceAccountName: pipeline-operator
      containers:
      - name: operator
        image: nginx:alpine
        command: ["sleep", "infinity"]
MANIFEST

# ── Create initial screenshot ─────────────────────────────────────────────────
sleep 5
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="