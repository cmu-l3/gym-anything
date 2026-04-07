#!/bin/bash
# Export script for secrets_lifecycle_management task
# Gathers all required secrets as JSON objects and exports them for verification

echo "=== Exporting secrets_lifecycle_management result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to fetch a secret as JSON, returning empty object `{}` if missing
fetch_secret() {
    local name=$1
    local ns=$2
    docker exec rancher kubectl get secret "$name" -n "$ns" -o json 2>/dev/null || echo "{}"
}

# Fetch all relevant secrets
echo "Fetching secret states from Kubernetes..."
PAYMENT_DB=$(fetch_secret "payment-db-credentials" "payment")
STRIPE_PAYMENT=$(fetch_secret "stripe-api-keys" "payment")
STRIPE_DEFAULT=$(fetch_secret "stripe-api-keys" "default")
TLS_WEB=$(fetch_secret "frontend-tls" "web")
TOKEN_PAYMENT=$(fetch_secret "inter-service-token" "payment")
TOKEN_WEB=$(fetch_secret "inter-service-token" "web")

# Create JSON result structure
TEMP_JSON=$(mktemp /tmp/secrets_result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "secrets": {
    "payment_db": $PAYMENT_DB,
    "stripe_payment": $STRIPE_PAYMENT,
    "stripe_default": $STRIPE_DEFAULT,
    "tls_web": $TLS_WEB,
    "token_payment": $TOKEN_PAYMENT,
    "token_web": $TOKEN_WEB
  }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export Complete ==="