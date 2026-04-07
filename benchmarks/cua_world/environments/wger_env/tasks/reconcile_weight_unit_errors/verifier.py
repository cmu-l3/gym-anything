#!/usr/bin/env python3
"""
Verifier for reconcile_weight_unit_errors task.

Verifies that the agent correctly identified 5 outlier weight entries,
mathematically converted them back to kilograms, and saved them WITHOUT
deleting the records.

Criteria:
1. Outliers Eliminated: No entries over 150 remain in the database (40 points)
2. Data Preserved: Exactly 30 entries still exist in the database (30 points)
3. Values Corrected: Exactly 30 entries fall within the human expected kg range (70-100) (20 points)
4. VLM Verification: Agent actually used the UI workflow (10 points)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying if an AI agent successfully corrected anomalous data in a fitness tracking web application.
The task required finding 5 body weight entries erroneously logged in pounds (>150 lbs) and editing them down to their kilogram equivalents (dividing by 2.2046).

Look at these trajectory frames and the final screenshot and determine:
1. Did the agent navigate through the web interface to edit body weight entries?
2. Did the agent type/enter updated numerical values (around 80-90) into the weight input fields?
3. Does the final weight trend chart look like a relatively smooth line WITHOUT massive vertical spikes above 150?

Return a JSON object:
{
    "used_ui_to_edit": true/false,
    "chart_looks_fixed": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_reconcile_weight_unit_errors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total_entries', 30)
    
    # -------------------------------------------------------------------
    # 1. Read exported results from environment
    # -------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    total_entries = int(result.get('total_entries', 0))
    outlier_entries = int(result.get('outlier_entries', 5))
    valid_entries = int(result.get('valid_entries', 0))
    initial_outliers = int(result.get('initial_outliers', 5))

    score = 0
    feedback_parts = []
    
    # Check if they did literally nothing
    if outlier_entries == initial_outliers and total_entries == expected_total:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No changes made to the database. Outliers are still present."
        }

    # -------------------------------------------------------------------
    # 2. Database Evaluation
    # -------------------------------------------------------------------
    
    # Criterion 1: Outliers eliminated (40 pts)
    if outlier_entries == 0:
        score += 40
        feedback_parts.append("✅ All outliers eliminated (>150 entries removed)")
    else:
        feedback_parts.append(f"❌ {outlier_entries} outliers still remain")
        
    # Criterion 2: Data preserved (30 pts)
    if total_entries == expected_total:
        score += 30
        feedback_parts.append(f"✅ Data preserved (exactly {expected_total} entries remain)")
    elif total_entries < expected_total:
        deleted = expected_total - total_entries
        feedback_parts.append(f"❌ Data deleted! Task required editing, but {deleted} entries were deleted.")
    elif total_entries > expected_total:
        feedback_parts.append(f"❌ Data duplicated! Found {total_entries} entries instead of {expected_total}.")

    # Criterion 3: Values corrected / math applied properly (20 pts)
    if valid_entries == expected_total:
        score += 20
        feedback_parts.append("✅ All entries are within the valid human kg range (math was correct)")
    else:
        invalid_count = expected_total - valid_entries
        feedback_parts.append(f"❌ {invalid_count} entries have invalid/arbitrary kg values")

    # -------------------------------------------------------------------
    # 3. VLM Verification (10 pts)
    # -------------------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
            parsed = vlm_response.get("parsed", {})
            
            used_ui = parsed.get("used_ui_to_edit", False)
            chart_fixed = parsed.get("chart_looks_fixed", False)
            
            if used_ui and chart_fixed:
                score += 10
                feedback_parts.append("✅ VLM verified UI interaction and fixed chart")
            elif used_ui:
                score += 5
                feedback_parts.append("⚠️ VLM verified UI interaction but chart may not look fixed")
            else:
                feedback_parts.append("❌ VLM did not observe UI workflow being used")
        else:
            feedback_parts.append("⚠️ No images available for VLM verification")
    else:
        # Give free points if VLM isn't available but DB is perfect
        if score == 90:
            score += 10
        feedback_parts.append("⚠️ VLM skipped (not available)")

    # -------------------------------------------------------------------
    # 4. Final scoring
    # -------------------------------------------------------------------
    # Strict passing requirement:
    # 1. MUST have eliminated the outliers
    # 2. MUST NOT have deleted entries (total == expected)
    # 3. MUST have done the math reasonably well (valid entries > 25)
    passed = (outlier_entries == 0) and (total_entries == expected_total) and (valid_entries >= 25)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }