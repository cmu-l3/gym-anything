#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_configure_school_periods(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent correctly configured the school periods in OpenSIS.
    
    Criteria:
    1. Database must contain exactly 7 periods for school_id=1.
    2. Each period must match the spec (Title, Short Name, Sort Order, Length).
    3. Records must have been created during the task (Anti-gaming via count delta).
    4. Visual check (VLM) confirms UI interaction.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Load expected data from task metadata
    expected_periods = task_info.get('metadata', {}).get('expected_periods', [])
    if not expected_periods:
        return {"passed": False, "score": 0, "feedback": "Task Configuration Error: Missing expected_periods metadata"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract verification data
    actual_periods = result_data.get('periods', [])
    initial_count = result_data.get('initial_count', 0)
    final_count = result_data.get('final_count', 0)
    
    score = 0
    max_score = 100
    feedback = []
    
    # 3. Verify Counts (Anti-Gaming & Basic Success)
    # 15 points for having exactly 7 periods
    if final_count == 7:
        score += 15
        feedback.append("Correct number of periods (7).")
    else:
        feedback.append(f"Incorrect number of periods: Found {final_count}, expected 7.")

    # 5 points for proof of work (delta > 0)
    if final_count > initial_count:
        score += 5
        feedback.append("New records confirmed created during task.")
    else:
        feedback.append("No new records created (Anti-gaming check failed).")

    # 4. Verify Content (75 points total distributed across fields)
    # We match by Sort Order as the primary key for the spec
    # Fields to check: Title, Short Name, Length
    
    # Points per correct field: 
    # 7 periods * 3 fields = 21 checks. 
    # Let's allocate ~3.5 points per correct field check, total ~75.
    
    correct_fields = 0
    total_fields = len(expected_periods) * 3 # title, short_name, length
    
    for expected in expected_periods:
        # Find matching actual period by sort_order
        # Note: sort_order might come back as string from shell script JSON export
        actual = next((p for p in actual_periods if str(p.get('sort_order')) == str(expected['sort_order'])), None)
        
        if not actual:
            feedback.append(f"Missing period for Sort Order {expected['sort_order']}.")
            continue
            
        # Check Title (Case insensitive)
        if actual.get('title', '').strip().lower() == expected['title'].strip().lower():
            correct_fields += 1
        else:
            feedback.append(f"Sort Order {expected['sort_order']}: Expected Title '{expected['title']}', got '{actual.get('title')}'.")
            
        # Check Short Name (Case insensitive)
        if actual.get('short_name', '').strip().lower() == expected['short_name'].strip().lower():
            correct_fields += 1
        else:
            feedback.append(f"Sort Order {expected['sort_order']}: Expected Short Name '{expected['short_name']}', got '{actual.get('short_name')}'.")
            
        # Check Length
        # Note: Database might return "55" or "55.00" or int 55
        try:
            act_len = float(actual.get('length', 0))
            exp_len = float(expected['length'])
            if act_len == exp_len:
                correct_fields += 1
            else:
                feedback.append(f"Sort Order {expected['sort_order']}: Expected Length {expected['length']}, got {actual.get('length')}.")
        except:
            feedback.append(f"Sort Order {expected['sort_order']}: Invalid length format '{actual.get('length')}'.")

    # Calculate content score
    # 75 points max for content
    content_score = int((correct_fields / total_fields) * 75) if total_fields > 0 else 0
    score += content_score
    
    # 5. VLM / Trajectory Verification (5 points)
    # Just checking if we have screenshots is a basic proxy for "agent was active"
    # Detailed VLM could check if the "Periods" page was visited.
    from gym_anything.vlm import get_final_screenshot
    final_img = get_final_screenshot(traj)
    if final_img:
        score += 5
        feedback.append("Visual evidence collected.")
    else:
        feedback.append("No visual evidence found.")

    # 6. Final Verdict
    # Pass if score >= 70 AND count is exactly 7 (Hard requirement)
    passed = (score >= 70) and (final_count == 7)
    
    if passed:
        feedback.insert(0, "SUCCESS: School periods configured correctly.")
    else:
        feedback.insert(0, "FAILURE: Configuration did not meet requirements.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "initial_count": initial_count,
            "final_count": final_count,
            "content_score": content_score,
            "correct_fields": correct_fields,
            "total_fields": total_fields
        }
    }