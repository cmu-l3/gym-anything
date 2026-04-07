#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_patients(traj, env_info, task_info):
    """
    Verify that duplicate patient records were merged correctly.
    
    Criteria:
    1. Only ONE record remains (20 pts)
    2. Data is merged correctly (Hyphenated name, Address, Phone) (35 pts)
    3. Duplicate record is deleted (20 pts)
    4. Audit report created with correct info (20 pts)
    5. Anti-gaming (timestamps) (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_phone = metadata.get('expected_phone', '0145678901')
    expected_city = metadata.get('expected_city', 'Paris')
    guid_a = metadata.get('guid_a', 'DUP-MERGE-AAA-001')
    guid_b = metadata.get('guid_b', 'DUP-MERGE-BBB-002')

    score = 0
    feedback_parts = []
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Single Record Check (20 pts)
    survivor_count = int(result.get('survivor_count', -1))
    if survivor_count == 1:
        score += 20
        feedback_parts.append("Correctly consolidated to single record")
    elif survivor_count == 0:
        feedback_parts.append("FAIL: All records deleted")
    else:
        feedback_parts.append(f"FAIL: {survivor_count} records remain (expected 1)")

    # 2. Merged Data Quality (35 pts)
    # raw format: "NOM|Adresse|Ville|Tel|SSN"
    raw_data = result.get('survivor_data_raw', "")
    firstname = result.get('survivor_firstname', "")
    
    data_parts = raw_data.split('|') if raw_data else []
    
    # Check Name (Hyphenated preferred)
    if "Marie-Claire" in firstname:
        score += 10
        feedback_parts.append("Name format correct (hyphenated)")
    elif "Marie Claire" in firstname:
        score += 5 # Partial credit for keeping name but losing hyphen
        feedback_parts.append("Name format acceptable but hyphen lost")
    else:
        feedback_parts.append(f"Name incorrect: {firstname}")

    if len(data_parts) >= 4:
        # Check Address/City
        if expected_city.lower() in data_parts[2].lower() and len(data_parts[1]) > 5:
            score += 10
            feedback_parts.append("Address merged")
        else:
            feedback_parts.append("Address missing/incorrect")

        # Check Phone
        # clean phone string for comparison
        phone_in_db = data_parts[3].replace('.', '').replace(' ', '')
        if expected_phone in phone_in_db:
            score += 15
            feedback_parts.append("Phone merged")
        else:
            feedback_parts.append(f"Phone missing/incorrect (found '{data_parts[3]}')")
    else:
        feedback_parts.append("Surviving record data incomplete")

    # 3. Duplicate Deletion (20 pts)
    ga_exists = int(result.get('guid_a_exists', 1))
    gb_exists = int(result.get('guid_b_exists', 1))
    
    # We expect exactly one to exist, or neither (if a new one was created)
    # But strictly, one should be deleted.
    if (ga_exists == 0 and gb_exists == 1) or (ga_exists == 1 and gb_exists == 0):
        score += 20
        feedback_parts.append("Duplicate GUID successfully removed")
    elif ga_exists == 0 and gb_exists == 0 and survivor_count == 1:
        # Agent created a totally new record and deleted both old ones - acceptable
        score += 20
        feedback_parts.append("Old GUIDs replaced with new record")
    else:
        feedback_parts.append("Duplicate deletion failed or incomplete")

    # 4. Audit Report (20 pts)
    if result.get('report_exists', False):
        score += 10
        content = result.get('report_content', '').lower()
        if guid_a.lower() in content or guid_b.lower() in content:
            score += 10
            feedback_parts.append("Audit report contains GUIDs")
        else:
            feedback_parts.append("Audit report exists but missing GUID details")
    else:
        feedback_parts.append("Audit report missing")

    # 5. Anti-gaming (5 pts)
    if result.get('report_created_during_task', False):
        score += 5
    
    passed = score >= 70 and survivor_count == 1

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }