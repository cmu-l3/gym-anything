#!/bin/bash
# setup_task.sh — AD Auth & Password Policy Hardening

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
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

# Write security hardening spec to desktop
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/security_hardening_spec.txt" << 'SPEC_EOF'
OpManager Security Hardening Specification
Version: 1.1
Effective Date: 2024-03-01

SECTION 1: ACTIVE DIRECTORY INTEGRATION
----------------------------------------
To ensure centralized access revocation, OpManager must be integrated with the
corporate Active Directory domain.

Please configure the following under Settings > General Settings > Authentication
(or the applicable AD/LDAP configuration area):

  - Domain Name: CORP-HQ.INTERNAL
  - Domain Controller: dc01.corp-hq.internal
  - Port: 636
  - SSL/TLS: Enabled (or secure connection checked)
  - Username / Bind DN: opmanager_bind_svc
  - Password: SuperSecureBind2024!

SECTION 2: LOCAL ACCOUNT SECURITY POLICIES
-------------------------------------------
Fallback local accounts (like 'admin') must be protected by strict password and
lockout policies.

Please configure the following under Settings > General Settings > Security Settings
(or the applicable Password Policy / Account Lockout area):

  Password Policy:
  - Minimum Length: 14 characters
  - Complexity: Require uppercase, lowercase, numeric, and special characters.

  Account Lockout Policy:
  - Invalid login threshold (Lockout limit): 5 attempts

Ensure all settings are saved successfully.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/security_hardening_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/security_hardening_spec.txt"

# Record task start timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/ad_security_task_start.txt
echo "[setup] Task start time recorded."

# Ensure Firefox is open on OpManager dashboard
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/ad_security_setup_screenshot.png" || true

echo "[setup] ad_auth_password_policy_hardening setup complete."