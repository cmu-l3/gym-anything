#!/bin/bash
set -e
echo "=== Exporting create_crm_salesperson results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Use Python to query Odoo XML-RPC and extract rich verification data
# We prefer XML-RPC over raw SQL here to inspect group memberships and effective permissions accurately
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
pwd = "admin"

result = {
    "user_found": False,
    "user_data": {},
    "groups": [],
    "team_member": False,
    "team_name": "",
    "timestamp_valid": False,
    "task_start_ts": int("${TASK_START}"),
    "initial_user_count": int("${INITIAL_USER_COUNT}"),
    "current_user_count": 0
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Get current user count
    result['current_user_count'] = models.execute_kw(db, uid, pwd, 'res.users', 'search_count', [[['active', '=', True]]])

    # 2. Search for the target user
    # Search by login (preferred) or name
    target_login = "sarah.johnson@yourcompany.example.com"
    target_name = "Sarah Johnson"
    
    user_ids = models.execute_kw(db, uid, pwd, 'res.users', 'search', 
        [[['login', '=', target_login], ['active', '=', True]]])
    
    if not user_ids:
        # Fallback search by name
        user_ids = models.execute_kw(db, uid, pwd, 'res.users', 'search', 
            [[['name', '=', target_name], ['active', '=', True]]])

    if user_ids:
        u_id = user_ids[0]
        result['user_found'] = True
        
        # Get User Details
        user_data = models.execute_kw(db, uid, pwd, 'res.users', 'read', 
            [[u_id]], {'fields': ['name', 'login', 'create_date', 'groups_id']})[0]
        
        result['user_data'] = {
            'name': user_data.get('name'),
            'login': user_data.get('login'),
            'create_date': user_data.get('create_date')
        }

        # Check creation time against task start
        # Odoo returns date strings like '2023-10-25 10:00:00' (UTC)
        try:
            create_dt = datetime.datetime.strptime(user_data['create_date'], "%Y-%m-%d %H:%M:%S")
            # Simple conversion to epoch (assuming Odoo server is UTC)
            create_ts = create_dt.replace(tzinfo=datetime.timezone.utc).timestamp()
            
            # Allow some clock skew or timezone mismatch (timestamps in containers can be tricky)
            # If created after task start (minus buffer), it's valid
            if create_ts > (result['task_start_ts'] - 60):
                result['timestamp_valid'] = True
        except Exception as e:
            print(f"Timestamp parsing error: {e}", file=sys.stderr)

        # 3. Check Group Memberships (Access Rights)
        # Fetch xml_ids for the user's groups
        # groups_id is a list of IDs
        if user_data.get('groups_id'):
            group_ids = user_data['groups_id']
            # We need to find the XML IDs for these groups to be robust
            # Join res_groups with ir_model_data
            groups_data = models.execute_kw(db, uid, pwd, 'res.groups', 'read', 
                [group_ids], {'fields': ['name']})
            
            # Manual check for specific sales groups by XML ID is harder via read
            # Let's search if the user is in the specific groups we care about
            
            # Check for Sales / User: Own Documents Only (sales_team.group_sale_salesman)
            is_salesman = models.execute_kw(db, uid, pwd, 'res.users', 'has_group', [u_id, 'sales_team.group_sale_salesman'])
            if is_salesman:
                result['groups'].append('sales_team.group_sale_salesman')

            # Check for Sales / Administrator (sales_team.group_sale_manager)
            is_manager = models.execute_kw(db, uid, pwd, 'res.users', 'has_group', [u_id, 'sales_team.group_sale_manager'])
            if is_manager:
                result['groups'].append('sales_team.group_sale_manager')

        # 4. Check Team Membership
        # Search crm.team.member model
        member_ids = models.execute_kw(db, uid, pwd, 'crm.team.member', 'search',
            [[['user_id', '=', u_id]]])
        
        if member_ids:
            members = models.execute_kw(db, uid, pwd, 'crm.team.member', 'read',
                [member_ids], {'fields': ['crm_team_id']})
            for m in members:
                if m.get('crm_team_id'):
                    team_name = m['crm_team_id'][1] # [id, name]
                    if "Direct Sales" in team_name:
                        result['team_member'] = True
                        result['team_name'] = team_name
                        break

except Exception as e:
    result['error'] = str(e)
    print(f"RPC Error: {e}", file=sys.stderr)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Adjust permissions for extraction
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="