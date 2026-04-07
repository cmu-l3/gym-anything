#!/bin/bash
# setup_task.sh — Enterprise SAML SSO Authentication Setup
# Waits for OpManager to be ready, generates a dummy certificate,
# writes the SAML configuration document, and opens the dashboard.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 1. Clear any pre-existing SAML configuration in the DB
# ------------------------------------------------------------
echo "[setup] Clearing any pre-existing SAML configurations..."
# We try to delete from known SAML tables to ensure a clean slate
opmanager_query "DELETE FROM AaaSamlProvider;" 2>/dev/null || true
opmanager_query "DELETE FROM AaaSamlIdpDetails;" 2>/dev/null || true
opmanager_query "DELETE FROM AaaSamlSpDetails;" 2>/dev/null || true
opmanager_query "DELETE FROM SAMLConfiguration;" 2>/dev/null || true

# ------------------------------------------------------------
# 2. Create the dummy certificate
# ------------------------------------------------------------
echo "[setup] Generating dummy Identity Provider X.509 certificate..."
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

CERT_FILE="$DESKTOP_DIR/azure_idp_cert.pem"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /tmp/dummy_idp.key \
    -out "$CERT_FILE" \
    -subj "/C=US/ST=California/L=San Francisco/O=Dummy Corp/CN=login.microsoftonline.com" \
    2>/dev/null

chown ga:ga "$CERT_FILE"
chmod 644 "$CERT_FILE"

# ------------------------------------------------------------
# 3. Write the SAML configuration document
# ------------------------------------------------------------
echo "[setup] Writing SAML Identity Provider configuration document..."
CONFIG_FILE="$DESKTOP_DIR/saml_idp_config.txt"

cat > "$CONFIG_FILE" << 'EOF'
================================================================
IDENTITY PROVIDER (IdP) CONFIGURATION DETAILS
================================================================
Target Platform: ManageEngine OpManager
Migration Phase: Phase 2 (Zero Trust Rollout)
IdP Platform: Microsoft Entra ID (Azure AD)

Please configure SAML Authentication in OpManager using the 
following manual configuration details:

IdP Name: Azure-Entra-ID
IdP Login URL: https://login.microsoftonline.com/dummy-tenant/saml2
IdP Logout URL: https://login.microsoftonline.com/dummy-tenant/saml2/logout
IdP Issuer (Entity ID): https://sts.windows.net/dummy-tenant/
Name ID Format: EmailAddress

Certificate:
An exported X.509 Base64 certificate has been provided on your 
desktop (azure_idp_cert.pem). Please upload this in the SAML settings.

Instructions:
1. Navigate to Settings -> General Settings -> Authentication
2. Select the SAML Authentication tab.
3. Configure manually using the details above.
4. Save the configuration. 

**IMPORTANT**: Do NOT test the connection or try to log in via SAML yet, 
as the networking team has not yet whitelisted the dummy tenant URL.
================================================================
EOF

chown ga:ga "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/saml_sso_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/saml_sso_setup_screenshot.png" || true

echo "[setup] enterprise_saml_sso_authentication_setup setup complete."