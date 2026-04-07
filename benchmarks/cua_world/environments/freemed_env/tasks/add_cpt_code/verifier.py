#!/usr/bin/env python3
"""
Verifier for add_cpt_code task in FreeMED.

Uses a multi-criterion verification approach:
1. Validates that the CPT code was actually created in the database.
2. Checks that internal and external description data correctly matches the requested input.
3. Implements an anti-gaming check by validating the row count increased (preventing 'do nothing' score).
4. Verifies via VLM that actual CPT form navigation and interaction occurred.
"""

import json
import tempfile
import os
import logging

# Check if gym_anything dependencies exist gracefully
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Examine these trajectory screenshots from a task where the agent is interacting with FreeMED EMR software.

Task: Did the agent interact with the CPT code management system to add a new procedure code?

Check for these indicators:
1. Are they navigating a "CPT" or "Billing Codes" or "Support Data" module in FreeMED?
2. Is there visual evidence of a form for adding a CPT code being opened, focused, or filled out?
3. Can you spot references to procedure codes or descriptions like "99214" being typed?

Respond strictly in JSON format:
{
    "cpt_module_accessed": true/false,
    "adding_code_attempted": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief summary of what you see in the screenshots"
}
"""


def verify_add_cpt_code(traj, env_info, task_info):
    """
    Verify that the CPT code 99214 was added successfully to FreeMED.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get('metadata', {})
    expected_cpt_code = metadata.get('cpt_code', '99214')
    int_keyword = metadata.get('internal_name_keyword', 'moderate').lower()
    ext_keyword = metadata.get('external_name_keyword', 'established patient').lower()

    score = 0
    feedback_parts = []
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/add_cpt_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        initial_count = result.get('initial_cpt_count', 0)
        current_count = result.get('current_cpt_count', 0)
        cpt_found = result.get('cpt_found', False)
        cpt = result.get('cpt', {})

        # Criterion 1: CPT Record Exists (30 points)
        if cpt_found and cpt.get('code') == expected_cpt_code:
            score += 30
            feedback_parts.append(f"CPT code '{expected_cpt_code}' found in database")
            
            # Criterion 2: Internal Name Correct (20 points)
            internal_name = cpt.get('internal_name', '').lower()
            if int_keyword in internal_name:
                score += 20
                feedback_parts.append("Internal name matches expected keywords")
            else:
                feedback_parts.append(f"Internal name mismatch: expected to contain '{int_keyword}'")

            # Criterion 3: External Name Correct (20 points)
            external_name = cpt.get('external_name', '').lower()
            if ext_keyword in external_name:
                score += 20
                feedback_parts.append("External name matches expected keywords")
            else:
                feedback_parts.append(f"External name mismatch: expected to contain '{ext_keyword}'")
        else:
            feedback_parts.append(f"CPT code '{expected_cpt_code}' NOT found in database")

        # Criterion 4: Record Count Increased (15 points)
        if current_count > initial_count:
            score += 15
            feedback_parts.append(f"Record count increased (anti-gaming valid)")
        else:
            feedback_parts.append(f"Record count did not increase (Anti-gaming check failed)")

    except Exception as e:
        logger.error(f"Error reading DB results: {e}")
        feedback_parts.append(f"Error checking database: {e}")

    # Criterion 5: VLM UI Confirmation (15 points)
    if query_vlm and VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            images_to_evaluate = frames + [final_frame] if final_frame else frames
            
            prompt = build_vlm_prompt()
            vlm_result = query_vlm(images=images_to_evaluate, prompt=prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("cpt_module_accessed") and parsed.get("adding_code_attempted"):
                    score += 15
                    feedback_parts.append("VLM verified correct UI navigation")
                else:
                    feedback_parts.append("VLM did not detect correct module interaction")
            else:
                feedback_parts.append("VLM verification failed to parse")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM error: {str(e)[:50]}")
    else:
        # If VLM is simply unavailable, we don't penalize the core task success
        feedback_parts.append("VLM unavailable - skipping UI verification")

    # Pass threshold: 50 points and the CPT code MUST exist in the database properly
    cpt_exists = score >= 30 and ("found in database" in feedback_parts[0])
    passed = score >= 50 and cpt_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }