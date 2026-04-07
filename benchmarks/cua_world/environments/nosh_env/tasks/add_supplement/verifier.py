#!/usr/bin/env python3
"""
Verifier for add_supplement task (NOSH ChartingSystem).
Verifies that a Vitamin D supplement was correctly added to the patient's chart.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_supplement(traj, env_info, task_info):
    """
    Verify the add_supplement task.
    
    Criteria:
    1. Database record count for supplements increased (35 pts)
    2. Supplement name contains 'Vitamin D', 'D3', or 'Cholecalciferol' (25 pts)
    3. Dosage contains '2000' (15 pts)
    4. Reason contains 'deficiency' (15 pts)
    5. Record creation timestamp is valid (after task start) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    latest = result.get('latest_record', {})
    task_start = int(result.get('task_start_timestamp', 0))
    
    # Check 1: Record exists
    if current_count > initial_count:
        score += 35
        feedback_parts.append(f"Supplement record added (count: {initial_count} -> {current_count})")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new supplement record found in database."
        }
        
    # Check 2: Name Correctness
    name = latest.get('name', '').lower()
    if any(x in name for x in ['vitamin d', 'd3', 'cholecalciferol']):
        score += 25
        feedback_parts.append("Supplement name correct")
    else:
        feedback_parts.append(f"Supplement name incorrect/missing (found: '{latest.get('name')}')")
        
    # Check 3: Dosage
    dosage = latest.get('dosage', '')
    instructions = latest.get('instructions', '')
    if '2000' in dosage or '2000' in instructions:
        score += 15
        feedback_parts.append("Dosage correct (2000 IU)")
    else:
        feedback_parts.append(f"Dosage incorrect (expected 2000, found: '{dosage}')")
        
    # Check 4: Reason
    reason = latest.get('reason', '').lower()
    if 'deficiency' in reason or 'deficiency' in instructions.lower():
        score += 15
        feedback_parts.append("Reason documented correctly")
    else:
        feedback_parts.append(f"Reason incorrect (expected mention of deficiency, found: '{latest.get('reason')}')")

    # Check 5: Timestamp (Anti-gaming)
    record_ts = int(latest.get('timestamp', 0))
    if record_ts >= task_start:
        score += 10
        feedback_parts.append("Record created during task")
    else:
        feedback_parts.append(f"Warning: Record timestamp {record_ts} predates task start {task_start}")
        # We don't fail immediately but penalty applies

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }