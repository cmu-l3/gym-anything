#!/bin/bash
set -e
echo "=== Setting up password-protected directory task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Determine acmecorp.test web root and create staging directory
# ---------------------------------------------------------------
WEBROOT="/home/acmecorp/public_html"

# Verify acmecorp.test virtual server exists
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test virtual server does not exist!"
    # In a real scenario we might try to create it, but it should be pre-seeded
    exit 1
fi

# Create the staging directory
mkdir -p "${WEBROOT}/staging"

# Create a realistic staging index.html
cat > "${WEBROOT}/staging/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AcmeCorp Website Redesign - Staging Preview</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f4f7fa; color: #333; }
        header { background: linear-gradient(135deg, #1a2a6c, #b21f1f, #fdbb2d); padding: 60px 20px; text-align: center; color: white; }
        header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .container { max-width: 1100px; margin: 40px auto; padding: 0 20px; }
        .card { background: white; border-radius: 12px; padding: 30px; box-shadow: 0 2px 15px rgba(0,0,0,0.08); margin-bottom: 20px; }
        .status { text-align: center; margin: 40px 0; padding: 20px; background: #fff3cd; border-radius: 8px; border: 1px solid #ffc107; }
        footer { text-align: center; padding: 30px; color: #999; font-size: 0.85em; }
    </style>
</head>
<body>
    <header>
        <h1>AcmeCorp 2024 Redesign</h1>
        <p>Staging Environment - For Internal Review Only</p>
    </header>
    <div class="container">
        <div class="status">
            <strong>⚠ CONFIDENTIAL:</strong> This staging preview is for authorized reviewers only. Do not share this URL publicly.
        </div>
        <div class="card">
            <h3>New Brand Identity</h3>
            <p>Updated color palette reflecting AcmeCorp's evolution into enterprise cloud services.</p>
        </div>
    </div>
    <footer>
        <p>AcmeCorp Staging Preview &mdash; Generated 2024-11-15T14:32:00Z</p>
    </footer>
</body>
</html>
HTMLEOF

# Set correct ownership (acmecorp is the unix user for acmecorp.test)
chown -R acmecorp:acmecorp "${WEBROOT}/staging"
chmod 755 "${WEBROOT}/staging"
chmod 644 "${WEBROOT}/staging/index.html"

echo "--- Staging directory created at ${WEBROOT}/staging/ ---"

# ---------------------------------------------------------------
# 2. Ensure AllowOverride is enabled for the document root
# ---------------------------------------------------------------
APACHE_CONF="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$APACHE_CONF" ]; then
    # Ensure AllowOverride is All, not None, to allow .htaccess auth
    sed -i "s/AllowOverride None/AllowOverride All/g" "$APACHE_CONF" 2>/dev/null || true
fi

# Ensure auth modules are enabled
a2enmod auth_basic authn_file authn_core authz_user > /dev/null 2>&1 || true

# Reload Apache
systemctl reload apache2 2>/dev/null || systemctl restart apache2 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Clean any existing auth config (ensure clean starting state)
# ---------------------------------------------------------------
rm -f "${WEBROOT}/staging/.htaccess" 2>/dev/null || true
rm -f "${WEBROOT}/staging/.htpasswd" 2>/dev/null || true
find "${WEBROOT}" -name ".htpasswd" -path "*/staging/*" -delete 2>/dev/null || true

# Remove any Directory block for staging that contains Auth directives from Apache conf
python3 -c "
import re, sys
try:
    with open('$APACHE_CONF', 'r') as f:
        content = f.read()
    # Regex to remove Directory blocks for staging that contain AuthType
    pattern = r'<Directory\s+/home/acmecorp/public_html/staging[^>]*>.*?</Directory>'
    content = re.sub(pattern, '', content, flags=re.DOTALL|re.IGNORECASE)
    with open('$APACHE_CONF', 'w') as f:
        f.write(content)
except:
    pass
" 2>/dev/null || true

systemctl reload apache2 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Verify staging page is currently accessible WITHOUT auth
# ---------------------------------------------------------------
# Ensure DNS resolution
grep -q "acmecorp.test" /etc/hosts 2>/dev/null || echo "127.0.0.1 acmecorp.test" >> /etc/hosts

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: acmecorp.test" \
    --resolve "acmecorp.test:80:127.0.0.1" \
    "http://acmecorp.test/staging/" 2>/dev/null || echo "000")

echo "Current HTTP status for staging: ${HTTP_CODE}"
echo "unprotected" > /tmp/initial_staging_state.txt
echo "$HTTP_CODE" >> /tmp/initial_staging_state.txt

# ---------------------------------------------------------------
# 5. Set up Firefox with Virtualmin
# ---------------------------------------------------------------
ensure_virtualmin_ready

# Navigate to Virtualmin
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/index.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="