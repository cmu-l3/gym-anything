#!/bin/bash
# Export script for ingress_ssl_offloading_remediation task

echo "=== Exporting ingress_ssl_offloading_remediation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/task_final.png 2>/dev/null || true

# ── Check Ingress ────────────────────────────────────────────────────────────
INGRESS_JSON=$(docker exec rancher kubectl get ingress -n secure-web -o json 2>/dev/null || echo '{"items":[]}')

# Parse Ingress details
echo "$INGRESS_JSON" | python3 - << 'PYEOF' > /tmp/ingress_parsed.env
import json, sys

try:
    data = json.load(sys.stdin)
except Exception:
    data = {'items': []}

items = data.get('items', [])
tls_secret_name = 'unknown'
tls_host = 'unknown'
backend_port = 'unknown'

for item in items:
    spec = item.get('spec', {})
    rules = spec.get('rules', [])
    for rule in rules:
        # Check if it targets secure.local or portal-svc
        if rule.get('host') == 'secure.local' or rule.get('http', {}).get('paths', [{}])[0].get('backend', {}).get('service', {}).get('name') == 'portal-svc':
            
            tls = spec.get('tls', [{}])
            if len(tls) > 0:
                tls_secret_name = tls[0].get('secretName', 'unknown')
                hosts = tls[0].get('hosts', [])
                if len(hosts) > 0:
                    tls_host = hosts[0]
            
            paths = rule.get('http', {}).get('paths', [])
            if len(paths) > 0:
                backend_port = paths[0].get('backend', {}).get('service', {}).get('port', {}).get('number', 'unknown')
            break

print(f"TLS_SECRET_NAME={tls_secret_name}")
print(f"TLS_HOST={tls_host}")
print(f"BACKEND_PORT={backend_port}")
PYEOF

source /tmp/ingress_parsed.env

# ── Check Secret Type ────────────────────────────────────────────────────────
if [ "$TLS_SECRET_NAME" != "unknown" ]; then
    SECRET_TYPE=$(docker exec rancher kubectl get secret "$TLS_SECRET_NAME" -n secure-web -o jsonpath='{.type}' 2>/dev/null || echo "unknown")
else
    SECRET_TYPE="unknown"
fi

# ── Check End-to-End Routing ─────────────────────────────────────────────────
# 1. Check HTTP response over HTTPS 
HTTP_CODE=$(docker exec rancher curl -k -s -o /dev/null -w "%{http_code}" -H "Host: secure.local" https://127.0.0.1/ 2>/dev/null || echo "000")

# 2. Check the returned certificate subject (extracts the CN to make sure the right cert is being served)
CERT_SUBJECT=$(docker exec rancher sh -c "echo 'Q' | openssl s_client -showcerts -servername secure.local -connect 127.0.0.1:443 2>/dev/null | openssl x509 -inform pem -noout -subject 2>/dev/null" || echo "")

# ── Write to JSON ────────────────────────────────────────────────────────────
cat > /tmp/ingress_task_result.json <<EOF
{
  "secret_type": "$SECRET_TYPE",
  "tls_secret_name": "$TLS_SECRET_NAME",
  "tls_host": "$TLS_HOST",
  "backend_port": "$BACKEND_PORT",
  "http_code": "$HTTP_CODE",
  "cert_subject": "$CERT_SUBJECT"
}
EOF

echo "Result JSON written to /tmp/ingress_task_result.json"
cat /tmp/ingress_task_result.json

echo "=== Export Complete ==="