#!/bin/bash
# Export script for Dataset Funding Attribute Config task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load start time
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00")

# ------------------------------------------------------------------
# Python script to extract complex verification data from API
# ------------------------------------------------------------------
python3 << 'PYEOF' > /tmp/verification_data.json
import json
import requests
import sys
from datetime import datetime

# API Config
AUTH = ('admin', 'district')
BASE_URL = 'http://localhost:8080/api'
TASK_START_ISO = "TASK_START_PLACEHOLDER"

def get_api(endpoint, params=None):
    try:
        r = requests.get(f"{BASE_URL}/{endpoint}", auth=AUTH, params=params)
        return r.json()
    except Exception as e:
        return {}

results = {
    "cat_options_found": False,
    "cat_found": False,
    "cat_combo_found": False,
    "is_attribute": False,
    "dataset_correct": False,
    "data_value_found": False,
    "data_details": {},
    "metadata_timestamps": {}
}

try:
    # 1. Check Category Options
    # Filter by name "Government Fund" and "Donor Fund"
    opt_gov = get_api("categoryOptions", {"filter": "name:eq:Government Fund", "fields": "id,created"})
    opt_don = get_api("categoryOptions", {"filter": "name:eq:Donor Fund", "fields": "id,created"})
    
    gov_exists = len(opt_gov.get('categoryOptions', [])) > 0
    don_exists = len(opt_don.get('categoryOptions', [])) > 0
    results["cat_options_found"] = gov_exists and don_exists

    # 2. Check Category
    cat = get_api("categories", {"filter": "name:eq:Funding Source 2025", "fields": "id,created,categoryOptions[id,name]"})
    cat_list = cat.get('categories', [])
    if cat_list:
        results["cat_found"] = True
        results["metadata_timestamps"]["category"] = cat_list[0].get('created')

    # 3. Check Category Combo
    cc = get_api("categoryCombos", {"filter": "name:eq:Funding Source 2025", "fields": "id,created,dataDimensionType,categories[id]"})
    cc_list = cc.get('categoryCombos', [])
    cc_id = None
    if cc_list:
        cc_obj = cc_list[0]
        results["cat_combo_found"] = True
        results["is_attribute"] = (cc_obj.get('dataDimensionType') == 'ATTRIBUTE')
        results["metadata_timestamps"]["cat_combo"] = cc_obj.get('created')
        cc_id = cc_obj.get('id')

    # 4. Check Dataset Configuration
    # Find "Reproductive Health" dataset
    ds = get_api("dataSets", {"filter": "name:eq:Reproductive Health", "fields": "id,categoryCombo[id,name]"})
    ds_list = ds.get('dataSets', [])
    ds_id = None
    if ds_list:
        ds_obj = ds_list[0]
        assigned_cc_id = ds_obj.get('categoryCombo', {}).get('id')
        ds_id = ds_obj.get('id')
        
        # Verify assignment
        if cc_id and assigned_cc_id == cc_id:
            results["dataset_correct"] = True

    # 5. Check Data Value
    # We need to look for data values in the dataset for 202501
    # We specifically look for entries that use the NEW attributeOptionCombo
    if ds_id and cc_id:
        # Get categoryOptionCombos for our new category combo
        coc_req = get_api(f"categoryCombos/{cc_id}", {"fields": "categoryOptionCombos[id,name]"})
        valid_cocs = [x['id'] for x in coc_req.get('categoryOptionCombos', [])]
        
        # Query data values
        # OrgUnit: Bo Hospital. Need to find its ID first? 
        # Let's search for Bo Hospital ID
        ou_req = get_api("organisationUnits", {"filter": "name:eq:Bo Hospital", "fields": "id"})
        ou_list = ou_req.get('organisationUnits', [])
        
        if ou_list:
            ou_id = ou_list[0]['id']
            # Fetch data values
            dv_params = {
                "dataSet": ds_id,
                "period": "202501",
                "orgUnit": ou_id
            }
            dv_req = get_api("dataValues", dv_params)
            
            data_values = dv_req.get('dataValues', [])
            
            # Check if any data value uses one of our new COCs
            for dv in data_values:
                attr_opt_combo = dv.get('attributeOptionCombo')
                if attr_opt_combo in valid_cocs:
                    results["data_value_found"] = True
                    results["data_details"] = {
                        "value": dv.get('value'),
                        "lastUpdated": dv.get('lastUpdated'),
                        "attributeOptionCombo": attr_opt_combo
                    }
                    break

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results, indent=2))
PYEOF

# Replace placeholder with actual task start ISO
TASK_START_STR=$(cat /tmp/task_start_iso)
sed -i "s/TASK_START_PLACEHOLDER/$TASK_START_STR/g" /tmp/verification_data.json

# Run the python script
python3 /tmp/verification_data.json > /tmp/task_result.json

# Add basic info to result
cat /tmp/task_result.json

echo "=== Export Complete ==="