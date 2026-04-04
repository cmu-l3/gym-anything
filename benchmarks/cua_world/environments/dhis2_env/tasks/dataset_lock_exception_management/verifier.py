#!/usr/bin/env python3
"""
Verifier for dataset_lock_exception_management task.

Scoring (100 points total):
1. Dataset Expiry Configured (40 pts): 'Child Health' expiryDays == 15
2. Lock Exception Created (40 pts): Exception exists for Ngelehun CHC, Child Health, Jan 2023
3. Configuration Updated Recently (20 pts): Changes made after task start

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_dataset_lock_exception(traj, env_info, task_info):
    """Verify dataset expiry settings and lock exception creation."""
    
    # 1. Setup Result Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/dataset_lock_exception_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # 2. Parse Results
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    task_start_iso = result.get('task_start_iso', '')
    
    # ---------------------------------------------------------
    # CRITERION 1: Dataset Expiry Config (40 pts)
    # ---------------------------------------------------------
    ds_config = result.get('dataset_config', {})
    expiry_days = ds_config.get('expiry_days')
    
    if expiry_days == 15:
        score += 40
        feedback_parts.append("Dataset expiry correctly set to 15 days (+40)")
    else:
        feedback_parts.append(f"Dataset expiry incorrect. Expected 15, got {expiry_days}")

    # ---------------------------------------------------------
    # CRITERION 2: Lock Exception Existence (40 pts)
    # ---------------------------------------------------------
    le_info = result.get('lock_exception', {})
    found_le = le_info.get('found', False)
    le_details = le_info.get('details', {})
    
    if found_le:
        score += 40
        feedback_parts.append("Lock exception for Ngelehun CHC created (+40)")
    else:
        feedback_parts.append("Lock exception for Ngelehun CHC/Child Health/Jan 2023 not found")

    # ---------------------------------------------------------
    # CRITERION 3: Timing / Anti-Gaming (20 pts)
    # ---------------------------------------------------------
    # We verify that either the dataset was updated recently OR the lock exception was created recently
    # Ideally both, but at least one proves activity.
    
    def parse_time(t_str):
        if not t_str: return None
        # Handle various ISO formats (DHIS2 sometimes omits TZ or uses Z)
        t_str = t_str.replace('Z', '+00:00')
        try:
            return datetime.fromisoformat(t_str)
        except:
            return None

    start_time = parse_time(task_start_iso)
    ds_updated = parse_time(ds_config.get('last_updated'))
    le_created = parse_time(le_details.get('created'))
    
    timing_ok = False
    
    if start_time:
        if ds_updated and ds_updated > start_time:
            timing_ok = True
        if le_created and le_created > start_time:
            timing_ok = True
            
    if timing_ok:
        score += 20
        feedback_parts.append("Modifications verified as new (+20)")
    elif start_time is None:
        # Fallback if start time capture failed (rare)
        feedback_parts.append("Could not verify timing (system error)")
    else:
        # If score > 0 but timing failed, it might be stale data
        if score > 0:
            feedback_parts.append("Warning: Changes detected but timestamps appear old (pre-task state?)")
            score = 0 # Penalize for not doing it *now*

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }