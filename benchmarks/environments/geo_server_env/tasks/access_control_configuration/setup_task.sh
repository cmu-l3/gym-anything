#!/bin/bash
# Setup script for access_control_configuration task

echo "=== Setting up access_control_configuration ==="

source /workspace/scripts/task_utils.sh

if ! verify_geoserver_ready 60; then
    echo "ERROR: GeoServer not accessible"
    exit 1
fi

# Record baseline user/role/rule counts
echo "Recording baseline security state..."

USERS_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/usergroup/users.json" 2>/dev/null || echo "{}")
INITIAL_USER_COUNT=$(echo "$USERS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
users = d.get('users', {}).get('user', [])
if not isinstance(users, list): users = [users] if users else []
print(len(users))
" 2>/dev/null || echo "0")

ROLES_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/roles.json" 2>/dev/null || echo "{}")
INITIAL_ROLE_COUNT=$(echo "$ROLES_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
roles = d.get('roles', {}).get('role', [])
if not isinstance(roles, list): roles = [roles] if roles else []
print(len(roles))
" 2>/dev/null || echo "0")

RULES_JSON=$(curl -s -u "admin:Admin123!" \
    "http://localhost:8080/geoserver/rest/security/acl/layers.json" 2>/dev/null || echo "{}")
INITIAL_RULE_COUNT=$(echo "$RULES_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(len(d))
" 2>/dev/null || echo "0")

echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "$INITIAL_ROLE_COUNT" > /tmp/initial_role_count
echo "$INITIAL_RULE_COUNT" > /tmp/initial_rule_count

echo "Baseline: users=$INITIAL_USER_COUNT, roles=$INITIAL_ROLE_COUNT, acl_rules=$INITIAL_RULE_COUNT"

# Clean up pre-existing gis_reader user and ROLE_GIS_READER role if present
echo "Cleaning up pre-existing test entities..."
curl -s -u "admin:Admin123!" -X DELETE \
    "http://localhost:8080/geoserver/rest/security/usergroup/user/gis_reader" 2>/dev/null || true
curl -s -u "admin:Admin123!" -X DELETE \
    "http://localhost:8080/geoserver/rest/security/roles/role/ROLE_GIS_READER" 2>/dev/null || true

# Remove any pre-existing ne.* ACL rules for ROLE_GIS_READER
curl -s -u "admin:Admin123!" -X DELETE \
    "http://localhost:8080/geoserver/rest/security/acl/layers/ne.*.r" 2>/dev/null || true

sleep 1

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
generate_result_nonce
snapshot_access_log

ensure_logged_in
take_screenshot /tmp/access_control_configuration_start.png

echo "=== Setup Complete ==="
echo "Agent must: create user gis_reader, create role ROLE_GIS_READER, assign user to role, add data ACL rule, add service security rule"
