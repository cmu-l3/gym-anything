#!/usr/bin/env python3
"""
Verifier for create_pipeline_report task.

Checks:
1. Report exists in DB with correct name
2. Report targets the Opportunities module
3. Report has fields configured
4. Report has grouping configured
5. Anti-gaming: Record was created during task and counts increased
6. VLM Trajectory: Agent navigated Reports UI
"""

import os
import json
import tempfile
import logging
import time

# Import VLM utilities
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    pass  # Allow local execution if VLM not available

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pipeline_report(traj, env_info, task_info):
    """Verify report creation via database query and VLM trajectory analysis."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_module = metadata.get('expected_module', 'Opportunities')
    min_fields = metadata.get('min_expected_fields', 2)
    min_groups = metadata.get('min_expected_groupings', 1)

    # 1. Copy result JSON from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_pipeline_report_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []

    report_found = result.get('report_found', False)
    report_module = result.get('report_module', '')
    field_count = result.get('field_count', 0)
    group_count = result.get('group_count', 0)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    # 2. Database checks
    if report_found:
        score += 25
        feedback_parts.append("Report 'Weekly Pipeline by Stage' found")
        
        # Check target module
        if report_module == expected_module:
            score += 20
            feedback_parts.append("Target module is Opportunities")
        else:
            feedback_parts.append(f"Incorrect module: {report_module} (Expected: {expected_module})")

        # Check fields
        if field_count >= min_fields:
            score += 15
            feedback_parts.append(f"Fields correctly added ({field_count})")
        else:
            feedback_parts.append(f"Insufficient fields added: {field_count}")

        # Check grouping
        if group_count >= min_groups:
            score += 15
            feedback_parts.append("Grouping configured correctly")
        else:
            feedback_parts.append("Grouping not configured")
    else:
        feedback_parts.append("Report not found in database")

    # Anti-gaming: Check if overall report count increased
    if current_count > initial_count:
        score += 5
        feedback_parts.append("Report count increased")
    elif report_found:
        feedback_parts.append("Warning: Report found but overall count did not increase (possible pre-existing overwrite)")

    # 3. VLM Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        if frames and final_frame:
            all_frames = frames + [final_frame]
            prompt = (
                "You are evaluating a UI automation agent. The agent's task is to create a report "
                "in SuiteCRM's Reports module.\n"
                "Look closely at these trajectory screenshots. Answer these questions based on visual evidence:\n"
                "1. Did the agent navigate to the Reports module?\n"
                "2. Did the agent interact with the report builder (adding fields, setting modules, choosing grouping)?\n"
                "3. Does the final screen show a saved report or the Reports list confirming completion?\n"
                "Respond in JSON format with boolean keys: 'reports_module_visited', 'builder_used', 'completion_shown'."
            )
            vlm_response = query_vlm(images=all_frames, prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('reports_module_visited', False): vlm_score += 5
            if parsed.get('builder_used', False): vlm_score += 10
            if parsed.get('completion_shown', False): vlm_score += 5
            
            score += vlm_score
            feedback_parts.append(f"VLM trajectory score: {vlm_score}/20")
        else:
            feedback_parts.append("Could not run VLM verification (missing screenshots)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped")

    # Pass threshold: Must have found the report (min 25) + met total threshold of 60
    key_criteria_met = report_found and (report_module == expected_module)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }