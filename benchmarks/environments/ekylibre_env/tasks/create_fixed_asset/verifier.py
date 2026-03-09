#!/usr/bin/env python3
"""
Verifier for create_fixed_asset task in Ekylibre.

Verifies:
1. A new fixed asset record exists matching the description.
2. The asset details (amount, date, method) are correct.
3. The asset was created during the task window.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_fixed_asset(traj, env_info, task_info):
    """
    Verify the fixed asset creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_amount = metadata.get('expected_amount', 78500.00)
    expected_date = metadata.get('expected_start_date', '2025-01-15')
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check 1: Record Exists (25 pts)
    record = result.get('record', {})
    if result.get('record_found', False):
        score += 25
        feedback_parts.append("Fixed asset record found")
    else:
        return {"passed": False, "score": 0, "feedback": "No fixed asset record found matching 'John Deere 6120M'"}

    # Check 2: Created during task (Anti-gaming) (10 pts)
    # Check if final count > initial count
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    
    # Also check created_at timestamp if available
    created_during = False
    if final_count > initial_count:
        created_during = True
        score += 10
        feedback_parts.append("New record created during task")
    else:
        feedback_parts.append("No increase in record count (record may have pre-existed)")
        # We penalize but continue checking for partial credit if they edited an existing one
        
    # Check 3: Gross Amount (20 pts)
    # Amount comes as string from DB, e.g., "78500.00"
    amount_val = float(record.get('amount', 0))
    if abs(amount_val - expected_amount) < 0.01:
        score += 20
        feedback_parts.append(f"Amount correct ({amount_val})")
    else:
        feedback_parts.append(f"Amount incorrect: expected {expected_amount}, got {amount_val}")

    # Check 4: Depreciation Method (15 pts)
    method = record.get('depreciation_method', '').lower()
    if method == 'linear':
        score += 15
        feedback_parts.append("Depreciation method correct (linear)")
    else:
        feedback_parts.append(f"Method incorrect: expected linear, got {method}")

    # Check 5: Start Date (10 pts)
    start_date = record.get('started_on', '')
    if start_date == expected_date:
        score += 10
        feedback_parts.append(f"Start date correct ({start_date})")
    else:
        feedback_parts.append(f"Start date incorrect: expected {expected_date}, got {start_date}")

    # Check 6: Duration/End Date (10 pts)
    # Target: 7 years. 
    # stopped_on should be approx 2032-01-14 OR percentage approx 14.28
    stopped_on = record.get('stopped_on', '')
    dep_pct = float(record.get('depreciation_percentage', 0) or 0)
    
    duration_ok = False
    if '2032' in stopped_on:
        duration_ok = True
    elif 14.2 < dep_pct < 14.3:
        duration_ok = True
        
    if duration_ok:
        score += 10
        feedback_parts.append("Duration/End date correct (7 years)")
    else:
        feedback_parts.append(f"Duration incorrect: stopped={stopped_on}, pct={dep_pct}")

    # Check 7: Depreciable Amount (10 pts)
    # Should be same as gross amount
    dep_amt = float(record.get('depreciable_amount', 0) or 0)
    if abs(dep_amt - expected_amount) < 0.01:
        score += 10
        feedback_parts.append("Depreciable amount correct")
    else:
        feedback_parts.append(f"Depreciable amount mismatch ({dep_amt})")

    passed = score >= 70 and result.get('record_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }