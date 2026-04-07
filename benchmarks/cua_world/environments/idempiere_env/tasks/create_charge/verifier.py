#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_charge(traj, env_info, task_info):
    """
    Verify the creation of a Charge in iDempiere.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}
        
    # Read result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Metadata
    meta = task_info.get('metadata', {})
    expected_name = meta.get('expected_name', 'Wire Transfer Fee')
    expected_desc_part = meta.get('expected_description_part', 'wire transfer')
    expected_tax = meta.get('expected_tax_category', 'Standard')
    
    score = 0
    feedback = []
    
    # Criterion 1: Record Exists (25 pts)
    # The record is looked up by Value='WTF-001' in export_result.sh
    if result.get('charge_exists'):
        score += 25
        feedback.append("Charge record created successfully")
    else:
        # Check if count increased even if key was wrong
        init_c = int(result.get('initial_count', 0))
        final_c = int(result.get('final_count', 0))
        if final_c > init_c:
             return {"passed": False, "score": 10, "feedback": "A record was created, but with the wrong Search Key (expected WTF-001)"}
        return {"passed": False, "score": 0, "feedback": "No Charge record found with Search Key 'WTF-001'"}
        
    data = result.get('charge_data', {})
    
    # Criterion 2: Name Correct (15 pts)
    actual_name = data.get('name', '').strip()
    if actual_name == expected_name:
        score += 15
        feedback.append(f"Name match: '{actual_name}'")
    else:
        feedback.append(f"Name mismatch: expected '{expected_name}', got '{actual_name}'")

    # Criterion 3: Amount Correct (20 pts)
    try:
        amt = float(data.get('amount', '0'))
        if abs(amt - 25.0) < 0.01:
            score += 20
            feedback.append("Amount match: 25.00")
        else:
            feedback.append(f"Amount mismatch: expected 25.00, got {amt}")
    except:
        feedback.append("Amount invalid format")

    # Criterion 4: Tax Category (15 pts)
    tax = data.get('tax_category', '').lower()
    if expected_tax.lower() in tax:
        score += 15
        feedback.append(f"Tax Category match: {data.get('tax_category')}")
    else:
        feedback.append(f"Tax Category mismatch: expected '{expected_tax}', got '{data.get('tax_category')}'")

    # Criterion 5: Description (10 pts)
    desc = data.get('description', '').lower()
    if expected_desc_part in desc:
        score += 10
        feedback.append("Description contains required text")
    else:
        feedback.append(f"Description missing '{expected_desc_part}'")
        
    # Criterion 6: Active (5 pts)
    if data.get('is_active') == 'Y':
        score += 5
    else:
        feedback.append("Record is not Active")

    # Criterion 7: Created during task (10 pts)
    created_ts = int(data.get('created_ts', 0))
    task_start = int(result.get('task_start', 0))
    
    # Allow 60s tolerance for clock skew if container time drifts slightly, 
    # but generally created should be >= task_start
    if created_ts >= (task_start - 60):
        score += 10
        feedback.append("Verified record creation timestamp")
    else:
        feedback.append("Record timestamp indicates pre-existing data")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }