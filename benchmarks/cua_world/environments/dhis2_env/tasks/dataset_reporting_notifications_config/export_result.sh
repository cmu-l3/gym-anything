#!/bin/bash
# Export script for Dataset Reporting Notifications task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00")

# 1. Check User Group "Ebola Response Team"
echo "Checking User Group..."
UG_JSON=$(dhis2_api "userGroups?filter=name:ilike:Ebola+Response+Team&fields=id,name,created,users[id,username]&paging=false" 2>/dev/null)

# 2. Check Dataset "Ebola Emergency Reporting"
echo "Checking Dataset..."
DS_JSON=$(dhis2_api "dataSets?filter=name:ilike:Ebola+Emergency+Reporting&fields=id,name,created,periodType,dataSetElements[dataElement],organisationUnits[id,name]&paging=false" 2>/dev/null)

# Extract Dataset ID for notification check
DS_ID=$(echo "$DS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataSets'][0]['id']) if d.get('dataSets') else print('')")

# 3. Check Notification Templates linked to this Dataset
NT_JSON="{}"
if [ -n "$DS_ID" ]; then
    echo "Checking Notifications for Dataset $DS_ID..."
    # We query all notification templates and filter for the one linked to our dataset
    # Note: dataSetNotificationTemplates usually link to a dataSet via 'dataSet' field
    NT_JSON=$(dhis2_api "dataSetNotificationTemplates?filter=dataSet.id:eq:$DS_ID&fields=id,name,created,dataSet[id],recipientUserGroup[id,name],messageTemplate,notificationTrigger,deliveryChannels&paging=false" 2>/dev/null)
fi

# 4. Verify Org Unit "Bo" assignment
# We need to know if 'Bo' (or its ID) is in the organisationUnits list of the dataset
BO_ID_CHECK=$(dhis2_api "organisationUnits?filter=name:ilike:Bo&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['organisationUnits'][0]['id']) if d.get('organisationUnits') else print('')")

# 5. Compile Result JSON
python3 -c "
import json
import sys
from datetime import datetime

try:
    task_start_iso = '$TASK_START_ISO'
    bo_id_ref = '$BO_ID_CHECK'

    # Parse inputs
    ug_data = json.loads('''$UG_JSON''')
    ds_data = json.loads('''$DS_JSON''')
    nt_data = json.loads('''$NT_JSON''')

    result = {
        'user_group_found': False,
        'user_group_valid': False,
        'dataset_found': False,
        'dataset_valid': False,
        'notification_found': False,
        'notification_valid': False,
        'details': {}
    }

    # Analyze User Group
    ugs = ug_data.get('userGroups', [])
    if ugs:
        ug = ugs[0]
        result['user_group_found'] = True
        users = ug.get('users', [])
        has_admin = any(u.get('username') == 'admin' for u in users)
        result['details']['user_group'] = {
            'name': ug.get('name'),
            'id': ug.get('id'),
            'has_admin': has_admin,
            'user_count': len(users)
        }
        if has_admin:
            result['user_group_valid'] = True
    
    # Analyze Dataset
    dss = ds_data.get('dataSets', [])
    if dss:
        ds = dss[0]
        result['dataset_found'] = True
        
        # Check period type
        period = ds.get('periodType', '')
        
        # Check elements
        elements = ds.get('dataSetElements', [])
        element_count = len(elements)
        
        # Check org units
        org_units = ds.get('organisationUnits', [])
        # Check if Bo ID is in the list
        has_bo = False
        if bo_id_ref:
            has_bo = any(ou.get('id') == bo_id_ref for ou in org_units)
        # Fallback: check names if ID lookup failed or complicated
        if not has_bo:
            has_bo = any('Bo' in ou.get('name', '') for ou in org_units)

        result['details']['dataset'] = {
            'name': ds.get('name'),
            'periodType': period,
            'element_count': element_count,
            'has_bo_org_unit': has_bo
        }
        
        if period == 'Monthly' and element_count >= 2 and has_bo:
            result['dataset_valid'] = True

    # Analyze Notification
    nts = nt_data.get('dataSetNotificationTemplates', [])
    if nts:
        nt = nts[0] # Assuming the first one found for this dataset is the relevant one
        result['notification_found'] = True
        
        trigger = nt.get('notificationTrigger', '')
        recipient_group = nt.get('recipientUserGroup', {}).get('name', '')
        channels = nt.get('deliveryChannels', [])
        msg_template = nt.get('messageTemplate', '')
        
        valid_trigger = trigger == 'COMPLETE'
        valid_recipient = 'Ebola Response Team' in recipient_group
        # Check for variable usage (basic check)
        valid_template = '{' in msg_template and '}' in msg_template
        
        result['details']['notification'] = {
            'name': nt.get('name'),
            'trigger': trigger,
            'recipient': recipient_group,
            'channels': channels,
            'template_has_vars': valid_template
        }
        
        if valid_trigger and valid_recipient and valid_template:
            result['notification_valid'] = True

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/notification_config_result.json

chmod 666 /tmp/notification_config_result.json 2>/dev/null || true
cat /tmp/notification_config_result.json
echo "=== Export Complete ==="