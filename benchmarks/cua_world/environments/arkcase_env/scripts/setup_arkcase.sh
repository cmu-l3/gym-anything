#!/bin/bash
# post_start hook: Deploy ArkCase via Helm, wait for readiness, configure browser
# NOTE: set -e intentionally NOT used here - many steps can fail gracefully

echo "=== Setting up ArkCase (post_start) ==="

# CRITICAL: Restore iptables FORWARD to ACCEPT so QEMU SSH port forwarding works.
# K3s/flannel from pre_start may have set FORWARD to DROP.
iptables -P FORWARD ACCEPT 2>/dev/null || true
echo "iptables FORWARD policy set to ACCEPT"

# Ensure swap is active
swapon /swapfile 2>/dev/null || true

# ── 0. Ensure kubeconfig is accessible ───────────────────────────────────────
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export HELM_CACHE_HOME=/tmp/helm-cache
export HELM_CONFIG_HOME=/tmp/helm-config
export HELM_DATA_HOME=/tmp/helm-data
mkdir -p /tmp/helm-cache /tmp/helm-config /tmp/helm-data

# Wait for K3s kubeconfig to exist (K3s may still be starting)
echo "Waiting for K3s kubeconfig..."
for i in $(seq 1 90); do
    if [ -f "$KUBECONFIG" ]; then
        echo "Kubeconfig found at $KUBECONFIG"
        break
    fi
    sleep 3
done

# Ensure root .kube is set up
mkdir -p /root/.kube
cp "$KUBECONFIG" /root/.kube/config 2>/dev/null || true

# Ensure ga user has access
mkdir -p /home/ga/.kube
cp "$KUBECONFIG" /home/ga/.kube/config 2>/dev/null || true
chown -R ga:ga /home/ga/.kube 2>/dev/null || true
chmod 600 /home/ga/.kube/config 2>/dev/null || true

ARKCASE_HOST="arkcase.local"
ARKCASE_NAMESPACE="arkcase"

# ── 1. Wait for K3s node to be Ready ─────────────────────────────────────────
echo "Waiting for K3s node to be Ready..."
timeout=240
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
        echo "K3s node is Ready"
        break
    fi
    echo "  K3s not ready yet ($elapsed/${timeout}s)..."
    sleep 5
    elapsed=$((elapsed + 5))
done

echo "=== K3s Nodes ==="
kubectl get nodes 2>/dev/null || echo "kubectl not available yet"
echo "=== K3s System Pods ==="
kubectl get pods -A 2>/dev/null | head -20 || true

# ── 2. Create namespace and pre-create required secrets ───────────────────────
echo "Creating ArkCase namespace..."
kubectl create namespace "$ARKCASE_NAMESPACE" 2>/dev/null || true

# Pre-create Pentaho secrets (required by init-dependencies even when reports disabled)
# These are referenced as environment variables in core and ldap init containers
echo "Pre-creating Pentaho placeholder secrets..."

# arkcase-reports-admin: needs username, password, group, url keys
# IMPORTANT: group must NOT conflict with Samba built-in SAMAccountNames.
# "Administrator" conflicts (built-in user), use "PentahoAdmin" instead.
kubectl create secret generic arkcase-reports-admin \
    --namespace "$ARKCASE_NAMESPACE" \
    --from-literal=username=pentaho-admin \
    --from-literal=password=PentahoAdmin123 \
    --from-literal=group=PentahoAdmin \
    --from-literal=url=http://localhost:8080/pentaho \
    2>/dev/null || kubectl patch secret arkcase-reports-admin \
        --namespace "$ARKCASE_NAMESPACE" \
        --type=merge \
        -p '{"stringData":{"username":"pentaho-admin","password":"PentahoAdmin123","group":"PentahoAdmin","url":"http://localhost:8080/pentaho"}}' \
        2>/dev/null || true

# arkcase-reports-main: needs username, password, url keys
kubectl create secret generic arkcase-reports-main \
    --namespace "$ARKCASE_NAMESPACE" \
    --from-literal=username=pentaho \
    --from-literal=password=PentahoUser123 \
    --from-literal=url=http://localhost:8080/pentaho \
    2>/dev/null || kubectl patch secret arkcase-reports-main \
        --namespace "$ARKCASE_NAMESPACE" \
        --type=merge \
        -p '{"stringData":{"username":"pentaho","password":"PentahoUser123","url":"http://localhost:8080/pentaho"}}' \
        2>/dev/null || true

echo "Pentaho placeholder secrets created."

# ── 3. Add ArkCase Helm repo ──────────────────────────────────────────────────
echo "Adding ArkCase Helm repo..."
helm repo add arkcase https://arkcase.github.io/ark_helm_charts/ 2>&1 || true
helm repo update 2>&1 || true
helm repo list 2>/dev/null || true

# Show available charts
echo "=== Available ArkCase charts ==="
helm search repo arkcase 2>/dev/null | head -20 || true

# ── 4. Deploy ArkCase via Helm ────────────────────────────────────────────────
echo "=== Deploying ArkCase via Helm ==="
echo "This may take 25-40 minutes for image pulls and initialization..."

# Try chart name variations
CHART_NAME="arkcase/app"
if ! helm show chart "$CHART_NAME" 2>/dev/null | grep -q "name"; then
    CHART_NAME=$(helm search repo arkcase --output json 2>/dev/null | \
        python3 -c "import sys,json; charts=json.load(sys.stdin); print(charts[0]['name'] if charts else 'arkcase/app')" 2>/dev/null || echo "arkcase/app")
fi
echo "Using chart: $CHART_NAME"

helm upgrade --install arkcase "$CHART_NAME" \
    --namespace "$ARKCASE_NAMESPACE" \
    --create-namespace \
    -f /workspace/config/arkcase-values.yaml \
    --timeout 40m \
    --wait 2>&1 | tee /home/ga/helm_install.log || {
        HELM_EXIT=$?
        echo "Helm install exited with code $HELM_EXIT - checking status..."
        kubectl get pods -n "$ARKCASE_NAMESPACE" 2>/dev/null || true
        echo "Continuing despite helm exit code..."
    }

echo "=== Pod Status After Helm Install ==="
kubectl get pods -n "$ARKCASE_NAMESPACE" 2>/dev/null || true
kubectl get svc -n "$ARKCASE_NAMESPACE" 2>/dev/null || true

# ── 5. Fix LDAP crash loop if needed ─────────────────────────────────────────
# The Samba AD container fails on restart if PVC has partial provisioning data.
# Strategy: if ldap pod is crash-looping, delete PVC and force fresh provisioning.
echo "Checking LDAP health..."
LDAP_RESTARTS=$(kubectl get pod arkcase-ldap-0 -n "$ARKCASE_NAMESPACE" \
    --no-headers 2>/dev/null | awk '{print $4}' || echo "0")
LDAP_STATUS=$(kubectl get pod arkcase-ldap-0 -n "$ARKCASE_NAMESPACE" \
    --no-headers 2>/dev/null | awk '{print $3}' || echo "Unknown")

echo "LDAP pod status: $LDAP_STATUS, restarts: $LDAP_RESTARTS"

if [ "$LDAP_RESTARTS" -ge 3 ] 2>/dev/null; then
    echo "LDAP is crash-looping ($LDAP_RESTARTS restarts). Attempting PVC reset..."
    # Delete the LDAP pod first
    kubectl delete pod arkcase-ldap-0 -n "$ARKCASE_NAMESPACE" --grace-period=0 --force 2>/dev/null || true
    sleep 5
    # Delete the LDAP PVC to allow fresh Samba AD provisioning
    LDAP_PVC=$(kubectl get pvc -n "$ARKCASE_NAMESPACE" --no-headers 2>/dev/null | \
        grep -i ldap | awk '{print $1}' | head -1)
    if [ -n "$LDAP_PVC" ]; then
        echo "Deleting LDAP PVC: $LDAP_PVC"
        kubectl delete pvc "$LDAP_PVC" -n "$ARKCASE_NAMESPACE" --grace-period=0 2>/dev/null || true
        sleep 10
        # Re-apply helm to recreate the pod and PVC
        helm upgrade --install arkcase "$CHART_NAME" \
            --namespace "$ARKCASE_NAMESPACE" \
            -f /workspace/config/arkcase-values.yaml \
            --timeout 40m \
            --wait 2>&1 | tee -a /home/ga/helm_install.log || true
    fi
fi

# ── 6. Wait for core pods to be Running ───────────────────────────────────────
echo "Waiting for ArkCase core pods to be Running..."
timeout=1800  # 30 minutes for full startup
elapsed=0
while [ $elapsed -lt $timeout ]; do
    CORE_STATUS=$(kubectl get pod arkcase-core-0 -n "$ARKCASE_NAMESPACE" \
        --no-headers 2>/dev/null | awk '{print $3}' || echo "Pending")
    LDAP_STATUS=$(kubectl get pod arkcase-ldap-0 -n "$ARKCASE_NAMESPACE" \
        --no-headers 2>/dev/null | awk '{print $3}' || echo "Pending")
    echo "  Core: $CORE_STATUS | LDAP: $LDAP_STATUS ($elapsed/${timeout}s)"

    if [ "$CORE_STATUS" = "Running" ]; then
        echo "ArkCase core pod is Running!"
        break
    fi

    # Check for LDAP crash loop and fix
    LDAP_RESTARTS=$(kubectl get pod arkcase-ldap-0 -n "$ARKCASE_NAMESPACE" \
        --no-headers 2>/dev/null | awk '{print $4}' || echo "0")
    if [ "$LDAP_RESTARTS" -ge 5 ] 2>/dev/null && [ "$elapsed" -ge 300 ]; then
        echo "LDAP still crash-looping after 5 restarts. Forcing PVC reset..."
        kubectl delete pod arkcase-ldap-0 -n "$ARKCASE_NAMESPACE" --grace-period=0 --force 2>/dev/null || true
        sleep 5
        LDAP_PVC=$(kubectl get pvc -n "$ARKCASE_NAMESPACE" --no-headers 2>/dev/null | \
            grep -i ldap | awk '{print $1}' | head -1)
        if [ -n "$LDAP_PVC" ]; then
            kubectl delete pvc "$LDAP_PVC" -n "$ARKCASE_NAMESPACE" 2>/dev/null || true
            sleep 30
        fi
        elapsed=$((elapsed + 30))
    fi

    sleep 30
    elapsed=$((elapsed + 30))
done

echo "=== Final Pod Status ==="
kubectl get pods -n "$ARKCASE_NAMESPACE" 2>/dev/null || true
kubectl get svc -n "$ARKCASE_NAMESPACE" 2>/dev/null || true

# ── 7. Set up port-forwarding ─────────────────────────────────────────────────
echo "Setting up port forwarding to ArkCase..."

# IMPORTANT: Use pod/arkcase-core-0 NOT svc/core.
# The core service uses haproxy which returns 503 when forwarded via kubectl port-forward.
# Direct pod port-forward bypasses haproxy and works correctly.
# Use port 9443 (not 8443) to avoid conflicts with app-proxy or other services.
# Run via tmux for persistence (nohup/disown don't survive).
SVC_PORT="9443"  # external port, maps to pod's 8443
POD_PORT="8443"  # ArkCase Tomcat internal port

# Kill any existing port-forward and tmux session
pkill -f "kubectl port-forward" 2>/dev/null || true
tmux kill-session -t arkcase 2>/dev/null || true
sleep 2

# Start persistent port-forward via tmux with auto-restart loop
# The port-forward dies after each connection if not using a loop
tmux new-session -d -s arkcase \
    "while true; do KUBECONFIG=${KUBECONFIG} kubectl port-forward -n ${ARKCASE_NAMESPACE} pod/arkcase-core-0 ${SVC_PORT}:${POD_PORT} --address 0.0.0.0 2>&1; sleep 2; done"
sleep 5
echo "Port-forward started via tmux (session: arkcase)"

# ── 8. Configure /etc/hosts ───────────────────────────────────────────────────
grep -q "$ARKCASE_HOST" /etc/hosts || echo "127.0.0.1 $ARKCASE_HOST" >> /etc/hosts

# ── 9. Wait for ArkCase HTTP endpoint ────────────────────────────────────────
echo "Waiting for ArkCase web endpoint to respond..."
ARKCASE_BASE_URL="https://localhost:${SVC_PORT}/arkcase"
timeout=600
elapsed=0
while [ $elapsed -lt $timeout ]; do
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 15 "${ARKCASE_BASE_URL}/" 2>/dev/null || echo "000")
    if echo "$HTTP_CODE" | grep -qE "^[2-4][0-9][0-9]$"; then
        echo "ArkCase is responding! HTTP $HTTP_CODE"
        break
    fi
    echo "  ArkCase not ready yet (HTTP $HTTP_CODE, $elapsed/${timeout}s)..."
    sleep 15
    elapsed=$((elapsed + 15))
done

echo "=== ArkCase final URL: ${ARKCASE_BASE_URL}/ ==="

# ── 10. Reset admin password in LDAP for reliable login ───────────────────────
# ArkCase generates random LDAP passwords; reset to known value for tasks
echo "Setting up admin password..."
ADMIN_PASSWORD="ArkCase1234!"
kubectl exec -n "$ARKCASE_NAMESPACE" arkcase-ldap-0 -- \
    bash -c "samba-tool user setpassword arkcase-admin --newpassword='${ADMIN_PASSWORD}' 2>&1" \
    2>/dev/null || echo "WARNING: Could not reset admin password (may already be set)"
echo "Admin credentials: arkcase-admin@dev.arkcase.com / ${ADMIN_PASSWORD}"

# ── 11. Configure Firefox snap profile with SSL cert trust ─────────────────────
echo "Configuring Firefox profile..."

# Find Firefox snap profile (snap Firefox uses different path than standard)
FIREFOX_SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")

if [ -n "$FIREFOX_SNAP_PROFILE" ]; then
    echo "Found Firefox snap profile: $FIREFOX_SNAP_PROFILE"
    # Write user.js to disable SSL warnings and set homepage
    cat > "$FIREFOX_SNAP_PROFILE/user.js" << FIREFOXEOF
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "${ARKCASE_BASE_URL}/login");
user_pref("security.cert_pinning.enforcement_level", 0);
user_pref("browser.ssl_override_behavior", 2);
user_pref("security.tls.insecure_fallback_hosts", "localhost");
FIREFOXEOF

    # Extract ArkCase self-signed cert and import into Firefox NSS database
    openssl s_client -connect "localhost:${SVC_PORT}" \
        </dev/null 2>/dev/null | openssl x509 -outform PEM > /tmp/arkcase.crt 2>/dev/null || true
    if [ -s /tmp/arkcase.crt ]; then
        certutil -d sql:"$FIREFOX_SNAP_PROFILE" -N --empty-password 2>/dev/null || true
        certutil -A -n "ArkCase-localhost" -t "CT,C,C" -i /tmp/arkcase.crt \
            -d sql:"$FIREFOX_SNAP_PROFILE" 2>/dev/null || true
        echo "ArkCase cert imported into Firefox NSS database"

        # Also generate cert_override.txt (most reliable Firefox bypass for self-signed certs)
        # This permanently accepts the certificate without the interstitial warning
        CERT_HASH=$(openssl x509 -in /tmp/arkcase.crt -fingerprint -sha256 -noout 2>/dev/null | \
            sed 's/.*=//; s/://g')
        if [ -n "$CERT_HASH" ]; then
            # Format: host:port\tOID.2.16.840.1.101.3.4.2.1\thash\tflags
            # MU = Mismatch + Untrusted override
            echo "localhost:${SVC_PORT}	OID.2.16.840.1.101.3.4.2.1	${CERT_HASH}	MU" \
                > "$FIREFOX_SNAP_PROFILE/cert_override.txt"
            echo "cert_override.txt created for localhost:${SVC_PORT}"
        fi
    else
        echo "WARNING: Could not extract cert (port-forward may not be active yet)"
        echo "Will rely on handle_ssl_warning() at task time"
    fi
    chown -R ga:ga "$(dirname "$FIREFOX_SNAP_PROFILE")" 2>/dev/null || true
else
    echo "WARNING: Firefox snap profile not found. Browser may show SSL warning on first launch."
fi

# ── 12. Launch Firefox ─────────────────────────────────────────────────────────
echo "Launching Firefox on ArkCase login page..."
sleep 5

if [ -n "$FIREFOX_SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox -profile '$FIREFOX_SNAP_PROFILE' '${ARKCASE_BASE_URL}/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox '${ARKCASE_BASE_URL}/login' &>/dev/null &" &
fi

sleep 20

# Maximize Firefox
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== ArkCase setup complete ==="
echo "URL: ${ARKCASE_BASE_URL}/login"
echo "Admin: arkcase-admin@dev.arkcase.com / ArkCase1234!"
kubectl get pods -n "$ARKCASE_NAMESPACE" 2>/dev/null | head -30 || true
