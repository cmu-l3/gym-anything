#!/usr/bin/env python3
"""
Verifier for create_custom_enumerations task.

Criteria:
1. IssuePriority "Critical - Safety" exists and is active (25 pts)
2. IssuePriority "Regulatory Deadline" exists and is active (25 pts)
3. TimeEntryActivity "Security Audit" exists and is active (20 pts)
4. Work package "Fix broken checkout on mobile Safari" has priority "Critical - Safety" (30 pts)
5. Anti-gaming: Ensure priorities were actually created (count increased)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_custom_enumerations(traj, env_info, task_info):
    """
    Verify that custom enumerations were created and assigned correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_priorities = metadata.get('expected_priorities', [])
    expected_activities = metadata.get('expected_activities', [])
    target_wp_priority = metadata.get('expected_wp_priority', "Critical - Safety")

    # Load result from container
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

    rails_data = result.get('rails_data', {})
    initial_state = result.get('initial_state', {})
    
    # Check for script errors
    if rails_data.get('error'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification script error: {rails_data['error']}"
        }

    score = 0
    feedback_parts = []
    
    # --- Criterion 1 & 2: Work Package Priorities (50 pts total) ---
    priorities_data = rails_data.get('priorities', {})
    
    for expected in expected_priorities:
        name = expected['name']
        p_data = priorities_data.get(name, {})
        
        if p_data.get('exists'):
            if p_data.get('active'):
                score += 25
                feedback_parts.append(f"[PASS] Priority '{name}' exists and is active (+25)")
                
                # Bonus check: instructions said NOT to make default
                if p_data.get('is_default'):
                    feedback_parts.append(f"[WARN] Priority '{name}' was set as default (instructions said No)")
            else:
                score += 10
                feedback_parts.append(f"[PARTIAL] Priority '{name}' exists but is inactive (+10)")
        else:
            feedback_parts.append(f"[FAIL] Priority '{name}' not found (+0)")

    # --- Criterion 3: Time Tracking Activity (20 pts) ---
    activities_data = rails_data.get('activities', {})
    
    for expected in expected_activities:
        name = expected['name']
        a_data = activities_data.get(name, {})
        
        if a_data.get('exists'):
            if a_data.get('active'):
                score += 20
                feedback_parts.append(f"[PASS] Activity '{name}' exists and is active (+20)")
            else:
                score += 8
                feedback_parts.append(f"[PARTIAL] Activity '{name}' exists but is inactive (+8)")
        else:
            feedback_parts.append(f"[FAIL] Activity '{name}' not found (+0)")

    # --- Criterion 4: Work Package Assignment (30 pts) ---
    wp_data = rails_data.get('work_package', {})
    
    if not wp_data.get('found'):
        feedback_parts.append("[FAIL] Target work package not found in system (+0)")
    else:
        actual_priority = wp_data.get('priority_name')
        if actual_priority == target_wp_priority:
            score += 30
            feedback_parts.append(f"[PASS] Work package priority updated to '{target_wp_priority}' (+30)")
        else:
            feedback_parts.append(f"[FAIL] Work package priority is '{actual_priority}', expected '{target_wp_priority}' (+0)")

    # --- Anti-Gaming Checks ---
    # 1. Check if priorities count actually increased
    init_p_count = initial_state.get('priority_count', 0)
    final_p_count = rails_data.get('counts', {}).get('priorities', 0)
    
    if final_p_count <= init_p_count and score > 0:
        feedback_parts.append(f"[WARN] Priority count did not increase ({init_p_count} -> {final_p_count}). Did you overwrite existing priorities?")
    
    # 2. Check if WP priority changed from initial
    init_wp_priority = initial_state.get('wp_priority', '')
    if init_wp_priority == target_wp_priority and score > 0:
         feedback_parts.append(f"[WARN] Work package already had priority '{target_wp_priority}' at start. Verification may be compromised.")

    passed = score >= 50 and any("Work package priority updated" in f for f in feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }