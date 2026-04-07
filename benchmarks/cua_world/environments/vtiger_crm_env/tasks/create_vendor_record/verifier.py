#!/usr/bin/env python3
"""
Verifier for create_vendor_record task in Vtiger CRM.
Programmatically validates that the agent successfully navigated to the
Vendors module, created the record, and correctly filled in details.
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_vendor_record(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    vendor_found = result.get('vendor_found', False)
    vendor = result.get('vendor', {})
    task_start = result.get('task_start_time', 0)
    created_time = vendor.get('created_timestamp', 0)
    
    # 1. Vendor exists & Anti-Gaming Timestamp (25 pts)
    if not vendor_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Vendor 'GreenScape Materials Co.' was not found in the database."
        }
    
    if created_time >= task_start:
        score += 25
        feedback_parts.append("✅ Vendor record created during task (+25)")
    else:
        feedback_parts.append("❌ Vendor record existed prior to task start (Anti-gaming triggered)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Helper function for matching fields
    def check_field(field_name, expected, actual, points, partial_points=0, strip_digits=False):
        nonlocal score, feedback_parts
        if not actual:
            feedback_parts.append(f"❌ {field_name} missing")
            return
            
        actual_comp = str(actual).lower().strip()
        expected_comp = str(expected).lower().strip()
        
        if strip_digits:
            actual_comp = re.sub(r'\D', '', actual_comp)
            expected_comp = re.sub(r'\D', '', expected_comp)

        if expected_comp in actual_comp:
            score += points
            feedback_parts.append(f"✅ {field_name} correct (+{points})")
        else:
            feedback_parts.append(f"❌ {field_name} incorrect (expected '{expected}', got '{actual}')")

    # 2. Basic Info Fields (30 pts)
    check_field("Phone", metadata.get("expected_phone", "5125558734"), vendor.get("phone"), 10, strip_digits=True)
    check_field("Email", metadata.get("expected_email", "orders@greenscapematerials.com"), vendor.get("email"), 10)
    check_field("Website", metadata.get("expected_website", "greenscapematerials.com"), vendor.get("website"), 10)

    # 3. Address Fields (35 pts)
    check_field("Street", metadata.get("expected_street", "4200 Industrial Parkway"), vendor.get("street"), 10)
    check_field("City", metadata.get("expected_city", "Austin"), vendor.get("city"), 10)
    check_field("State", metadata.get("expected_state", "Texas"), vendor.get("state"), 5)
    check_field("Postal Code", metadata.get("expected_postalcode", "78745"), vendor.get("postalcode"), 5)
    check_field("Country", metadata.get("expected_country", "United States"), vendor.get("country"), 5)

    # 4. Description Field (10 pts)
    desc = vendor.get('description', '').lower()
    keywords = ['landscaping', 'mulch', 'stone', 'irrigation', 'net 30']
    matched_keywords = sum(1 for kw in keywords if kw in desc)
    
    if matched_keywords >= 4:
        score += 10
        feedback_parts.append("✅ Description contains key information (+10)")
    elif matched_keywords >= 1:
        score += 5
        feedback_parts.append(f"⚠️ Description partially correct ({matched_keywords}/{len(keywords)} keywords) (+5)")
    else:
        feedback_parts.append("❌ Description missing or incorrect")

    # Determine passing status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }