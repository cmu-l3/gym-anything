#!/usr/bin/env python3
"""
Verifier for configure_lost_reasons task.

Checks:
1. Existence of the 3 specific lost reasons in the database.
2. Verification that new records were actually created (count delta).
3. Reasonable task duration (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lost_reasons(traj, env_info, task_info):
    """
    Verify that the user created the 3 required lost reasons in Odoo.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result data
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

    # 2. Extract Data
    current_reasons = result.get('current_reasons', [])
    if isinstance(current_reasons, dict) and "error" in current_reasons:
        return {"passed": False, "score": 0, "feedback": f"Database query failed: {current_reasons['error']}"}

    initial_count = int(result.get('initial_count', 0))
    current_count = len(current_reasons)
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    duration = task_end - task_start

    # Normalize reason names for comparison (lowercase, strip)
    # Map normalized name to actual record
    reason_map = {r['name'].strip().lower(): r for r in current_reasons}
    
    score = 0
    feedback_parts = []
    
    # 3. Verify Specific Reasons (25 points each)
    expected_reasons = task_info.get('metadata', {}).get('expected_reasons', [
        "Chose a Competitor",
        "Project Cancelled",
        "Decision Maker Left Company"
    ])
    
    alt_spellings = task_info.get('metadata', {}).get('alternative_spellings', {
        "Project Cancelled": ["Project Canceled"]
    })

    found_count = 0
    for expected in expected_reasons:
        norm_expected = expected.strip().lower()
        
        # Check exact match first
        if norm_expected in reason_map:
            score += 25
            found_count += 1
            feedback_parts.append(f"✅ Found '{expected}'")
            continue
            
        # Check alternatives
        found_alt = False
        if expected in alt_spellings:
            for alt in alt_spellings[expected]:
                if alt.strip().lower() in reason_map:
                    score += 25
                    found_count += 1
                    feedback_parts.append(f"✅ Found '{alt}' (accepted alternative for '{expected}')")
                    found_alt = True
                    break
        
        if not found_alt:
            feedback_parts.append(f"❌ Missing '{expected}'")

    # 4. Verify Creation Delta (15 points)
    # We expect at least 3 new records.
    # We use a delta check to ensure the agent actually created them and didn't just rename existing ones
    # (though our setup script clears collisions, so this is just a backup sanity check)
    delta = current_count - initial_count
    if delta >= 3:
        score += 15
        feedback_parts.append(f"✅ Created {delta} new records (Target: 3+)")
    elif delta > 0:
        partial_score = int(15 * (delta / 3))
        score += partial_score
        feedback_parts.append(f"⚠️ Created only {delta} new records (Target: 3)")
    else:
        feedback_parts.append(f"❌ No new records created (Count: {initial_count} -> {current_count})")

    # 5. Anti-gaming / Timing (10 points)
    if duration >= 10:
        score += 10
        feedback_parts.append("✅ Reasonable task duration")
    else:
        feedback_parts.append(f"⚠️ Task completed too quickly ({duration}s)")

    # 6. Final Evaluation
    passed = (score >= 70) and (found_count == 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }