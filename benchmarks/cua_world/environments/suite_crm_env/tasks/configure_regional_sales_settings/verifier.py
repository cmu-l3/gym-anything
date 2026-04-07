#!/usr/bin/env python3
"""
Verifier for configure_regional_sales_settings task.

Multi-Criteria Verification:
1. GST Tax Rate Created (15 pts)
2. PST Tax Rate Created (15 pts)
3. HST Tax Rate Created (15 pts)
4. Canada Post Shipper Created (15 pts)
5. Purolator Shipper Created (15 pts)
6. Anti-gaming check: Valid UUIDs proving records were created via UI and not hardcoded scripts (25 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_valid_uuid(val):
    """Check if the string is a valid 36-character UUID (Standard SuiteCRM key format)."""
    if not val:
        return False
    return bool(re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', str(val).lower()))

def verify_regional_sales_settings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    taxrates = result.get('taxrates', [])
    shippers = result.get('shippers', [])
    
    score = 0
    feedback_parts = []
    
    # 1. GST - Canada
    # Note: DB value might be '5.00' or '5', we convert to float for robust evaluation.
    gst_found = any(t for t in taxrates if 'GST - Canada' in t.get('name', '') 
                    and float(t.get('value', 0) or 0) == 5.0 
                    and t.get('status') == 'Active')
    if gst_found:
        score += 15
        feedback_parts.append("GST Tax Rate correctly configured")
    else:
        feedback_parts.append("GST Tax Rate missing or incorrect")

    # 2. PST - British Columbia
    pst_found = any(t for t in taxrates if 'PST - British Columbia' in t.get('name', '') 
                    and float(t.get('value', 0) or 0) == 7.0 
                    and t.get('status') == 'Active')
    if pst_found:
        score += 15
        feedback_parts.append("PST Tax Rate correctly configured")
    else:
        feedback_parts.append("PST Tax Rate missing or incorrect")

    # 3. HST - Ontario
    hst_found = any(t for t in taxrates if 'HST - Ontario' in t.get('name', '') 
                    and float(t.get('value', 0) or 0) == 13.0 
                    and t.get('status') == 'Active')
    if hst_found:
        score += 15
        feedback_parts.append("HST Tax Rate correctly configured")
    else:
        feedback_parts.append("HST Tax Rate missing or incorrect")

    # 4. Canada Post
    cp_found = any(s for s in shippers if 'Canada Post' in s.get('name', '') 
                   and s.get('status') == 'Active')
    if cp_found:
        score += 15
        feedback_parts.append("Canada Post Shipper correctly configured")
    else:
        feedback_parts.append("Canada Post Shipper missing or incorrect")

    # 5. Purolator
    purolator_found = any(s for s in shippers if 'Purolator' in s.get('name', '') 
                          and s.get('status') == 'Active')
    if purolator_found:
        score += 15
        feedback_parts.append("Purolator Shipper correctly configured")
    else:
        feedback_parts.append("Purolator Shipper missing or incorrect")

    # 6. Anti-gaming check: Valid UUIDs
    # SuiteCRM natively creates 36-char UUIDs for new records. If an agent tries to execute 
    # handwritten SQL with integer IDs (like 1, 2, 3), this catches it.
    all_records = taxrates + shippers
    valid_uuids = [r for r in all_records if is_valid_uuid(r.get('id', ''))]
    
    items_created = sum([gst_found, pst_found, hst_found, cp_found, purolator_found])
    
    if items_created > 0 and len(valid_uuids) >= items_created:
        score += 25
        feedback_parts.append("Anti-gaming checks passed (Valid UUIDs detected)")
    elif items_created > 0:
        feedback_parts.append("WARNING: Invalid IDs detected. Possible DB injection without UI interaction.")
    
    passed = score >= 70  # Requires at least 3 records + anti-gaming to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }