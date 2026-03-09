#!/bin/bash
echo "=== Exporting restrict_wfs_transactions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# FUNCTIONAL TESTS (The core verification)
# We run these inside the container to verify the security rules actually work.
# ==============================================================================

GS_URL="http://localhost:8080/geoserver"
TEST_LAYER="ne:ne_countries"

# 1. TEST PUBLIC READ (GetFeature)
# Expectation: HTTP 200 (Success)
echo "Testing Public Read Access..."
READ_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${GS_URL}/wfs?service=WFS&version=1.0.0&request=GetFeature&typeName=${TEST_LAYER}&maxFeatures=1")
echo "Public Read Status: $READ_STATUS"

# 2. TEST PUBLIC WRITE (Transaction)
# Expectation: HTTP 401 or 403 (Blocked)
# We construct a dummy transaction. It doesn't need to be valid data, just a valid WFS Transaction request structure.
cat > /tmp/wfs_transaction.xml <<EOF
<wfs:Transaction service="WFS" version="1.0.0"
  xmlns:wfs="http://www.opengis.net/wfs"
  xmlns:ne="http://naturalearthdata.com"
  xmlns:ogc="http://www.opengis.net/ogc">
  <wfs:Insert>
    <ne:ne_countries>
      <ne:NAME>SecurityTest</ne:NAME>
    </ne:ne_countries>
  </wfs:Insert>
</wfs:Transaction>
EOF

echo "Testing Public Write Access..."
WRITE_STATUS_ANON=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: text/xml" \
    -d @/tmp/wfs_transaction.xml \
    "${GS_URL}/wfs")
echo "Public Write Status: $WRITE_STATUS_ANON"

# 3. TEST ADMIN WRITE (Transaction)
# Expectation: HTTP 200 (Allowed) or 400 (Bad Request if schema fails), but NOT 401/403
echo "Testing Admin Write Access..."
WRITE_STATUS_ADMIN=$(curl -s -o /dev/null -w "%{http_code}" -u admin:Admin123! -X POST \
    -H "Content-Type: text/xml" \
    -d @/tmp/wfs_transaction.xml \
    "${GS_URL}/wfs")
echo "Admin Write Status: $WRITE_STATUS_ADMIN"

# ==============================================================================
# CONFIGURATION CHECK
# Check the services.properties file for explicit rules
# ==============================================================================
SECURITY_DIR="/home/ga/geoserver/data_dir/security"
SERVICES_PROP="$SECURITY_DIR/services.properties"

CONFIG_HAS_TRANSACTION_RULE="false"
CONFIG_HAS_GETFEATURE_RULE="false"
CONFIG_HAS_ADMIN_ROLE="false"

if [ -f "$SERVICES_PROP" ]; then
    CONTENT=$(cat "$SERVICES_PROP")
    
    # Check for wfs.Transaction rule
    if echo "$CONTENT" | grep -i "wfs.Transaction"; then
        CONFIG_HAS_TRANSACTION_RULE="true"
        # Check if it assigns ADMIN role
        if echo "$CONTENT" | grep -i "wfs.Transaction" | grep -i "ADMIN"; then
            CONFIG_HAS_ADMIN_ROLE="true"
        fi
    fi
    
    # Check for wfs.GetFeature rule OR a wildcard wfs.* rule allowing anonymous
    if echo "$CONTENT" | grep -i "wfs.GetFeature\|wfs.\*"; then
        CONFIG_HAS_GETFEATURE_RULE="true"
    fi
fi

# ==============================================================================
# GUI INTERACTION CHECK
# ==============================================================================
GUI_INTERACTION=$(check_gui_interaction)

# ==============================================================================
# JSON EXPORT
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "public_read_status": $READ_STATUS,
    "public_write_status": $WRITE_STATUS_ANON,
    "admin_write_status": $WRITE_STATUS_ADMIN,
    "config_has_transaction_rule": $CONFIG_HAS_TRANSACTION_RULE,
    "config_has_admin_role": $CONFIG_HAS_ADMIN_ROLE,
    "config_has_getfeature_rule": $CONFIG_HAS_GETFEATURE_RULE,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/restrict_wfs_transactions_result.json"
rm -f /tmp/wfs_transaction.xml

echo "=== Export complete ==="