#!/usr/bin/env python3
"""Verifier for cmdb_asset_metadata_integration task."""
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _find_template(templates_raw, api_data, expected_template):
    template_lower = expected_template.lower()
    
    # Check DB raw text
    if templates_raw and template_lower in templates_raw.lower():
        return True
    
    # Check API response
    if api_data:
        text = json.dumps(api_data).lower()
        if template_lower in text:
            return True
            
    return False


def _find_custom_fields(cf_raw, expected_fields):
    found = []
    if cf_raw:
        text = cf_raw.lower()
        for f in expected_fields:
            if f.lower() in text:
                found.append(f)
    return found


def _check_device_template(device_api, props_raw, expected_template):
    template_lower = expected_template.lower()
    
    # API check: specifically check the 'type' or 'category' of 127.0.0.1
    if device_api:
        device_data = device_api.get("data", device_api)
        if isinstance(device_data, dict):
            t = str(device_data.get("type", "")).lower()
            if t == template_lower:
                return True
            
            # Or if it appears prominently in the JSON payload for the device
            if template_lower in json.dumps(device_data).lower():
                return True

    # DB check: 'managedobject' table should show the new type
    if props_raw and template_lower in props_raw.lower():
        return True

    return False


def _check_device_custom_field(device_api, cf_raw, expected_value):
    val_lower = expected_value.lower()
    
    # API check: 127.0.0.1 device JSON should contain the unique value
    if device_api:
        text = json.dumps(device_api).lower()
        if val_lower in text:
            return True

    # DB check: The custom fields/user fields table will persist the value uniquely
    if cf_raw and val_lower in cf_raw.lower():
        return True

    return False


def verify_cmdb_asset_metadata_integration(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', '/tmp/cmdb_integration_result.json')
    local_path = '/tmp/cmdb_integration_verify_result.json'

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check that export_result.sh ran successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    score = 0
    details = []

    device_api = data.get("device_api", {})
    templates_db = data.get("templates_db_raw", "")
    customfields_db = data.get("customfields_db_raw", "")
    props_db = data.get("device_props_db_raw", "")

    metadata = task_info.get('metadata', {})
    expected_template = metadata.get("expected_template", "Management-Appliance")
    expected_fields = metadata.get("expected_fields", ["CostCenter", "AssetOwner", "ComplianceScope"])
    expected_values = metadata.get("expected_values", {
      "CostCenter": "CC-90210",
      "AssetOwner": "sec-ops-team",
      "ComplianceScope": "PCI-DSS"
    })

    # 1. Template Created (20 pts)
    if _find_template(templates_db, device_api, expected_template):
        score += 20
        details.append(f"PASS: Device template '{expected_template}' found (+20)")
    else:
        details.append(f"FAIL: Device template '{expected_template}' not found (0/20)")

    # 2. Custom Fields Created (20 pts)
    found_fields = _find_custom_fields(customfields_db, expected_fields)
    if len(found_fields) == len(expected_fields):
        score += 20
        details.append(f"PASS: All {len(expected_fields)} custom fields found (+20)")
    elif len(found_fields) > 0:
        pts = int(20 * (len(found_fields) / len(expected_fields)))
        score += pts
        details.append(f"PARTIAL: {len(found_fields)}/{len(expected_fields)} custom fields found (+{pts})")
    else:
        details.append(f"FAIL: No custom fields found (0/20)")

    # 3. Template Applied to Device (20 pts)
    if _check_device_template(device_api, props_db, expected_template):
        score += 20
        details.append(f"PASS: Device template '{expected_template}' applied to 127.0.0.1 (+20)")
    else:
        details.append(f"FAIL: Device template '{expected_template}' not applied to 127.0.0.1 (0/20)")

    # 4. Custom Field Values Applied (13, 13, 14 pts)
    val1 = expected_values["CostCenter"]
    if _check_device_custom_field(device_api, customfields_db, val1):
        score += 13
        details.append(f"PASS: CostCenter value '{val1}' applied to 127.0.0.1 (+13)")
    else:
        details.append(f"FAIL: CostCenter value '{val1}' not applied (0/13)")

    val2 = expected_values["AssetOwner"]
    if _check_device_custom_field(device_api, customfields_db, val2):
        score += 13
        details.append(f"PASS: AssetOwner value '{val2}' applied to 127.0.0.1 (+13)")
    else:
        details.append(f"FAIL: AssetOwner value '{val2}' not applied (0/13)")

    val3 = expected_values["ComplianceScope"]
    if _check_device_custom_field(device_api, customfields_db, val3):
        score += 14
        details.append(f"PASS: ComplianceScope value '{val3}' applied to 127.0.0.1 (+14)")
    else:
        details.append(f"FAIL: ComplianceScope value '{val3}' not applied (0/14)")

    # Strict requirement: To pass overall, must cross 60 points AND have applied at least one custom field value.
    has_values_applied = (
        _check_device_custom_field(device_api, customfields_db, val1) or
        _check_device_custom_field(device_api, customfields_db, val2) or
        _check_device_custom_field(device_api, customfields_db, val3)
    )
    
    passed = score >= 60 and has_values_applied

    if score >= 60 and not passed:
        details.append("FAIL: Reached 60 points but NO custom field values were actually applied to the device.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }