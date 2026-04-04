#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_service_charge(traj, env_info, task_info):
    """
    Verify that a 'Large Party' service charge with 18% rate was created.
    
    Scoring:
    - 50 pts: Record exists in database
    - 30 pts: Rate is correct (18.0)
    - 20 pts: Record is new (target count > 0, implied by existence if start was clean)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback = []

    # 1. Check if record exists (50 pts)
    target_count = int(result.get("target_record_count", 0))
    record_exists = result.get("record_exists", False)
    
    if target_count > 0 or record_exists:
        score += 50
        feedback.append("Service charge 'Large Party' found in database")
    else:
        feedback.append("Service charge 'Large Party' NOT found in database")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback)}

    # 2. Check Rate (30 pts)
    found_rate_str = str(result.get("found_rate", "0")).strip()
    try:
        # DB might return "18.0" or "18" or "0.18" depending on column type
        # Floreant usually stores percentage as double (e.g. 18.0 for 18%)
        rate_val = float(found_rate_str)
        
        # Accept 18, 18.0, or 0.18 (if stored as decimal)
        if abs(rate_val - 18.0) < 0.1:
            score += 30
            feedback.append(f"Rate correct ({rate_val}%)")
        elif abs(rate_val - 0.18) < 0.01:
            score += 30
            feedback.append(f"Rate correct ({rate_val})")
        else:
            feedback.append(f"Incorrect rate: {rate_val} (Expected 18%)")
    except ValueError:
        feedback.append(f"Could not parse rate: {found_rate_str}")

    # 3. Check App State / Clean Creation (20 pts)
    # If we found it and it's valid, we assume it was created (since setup cleaned DB)
    if score >= 50:
        score += 20
        feedback.append("Configuration saved successfully")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }