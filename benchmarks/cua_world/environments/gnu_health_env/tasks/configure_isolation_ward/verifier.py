#!/usr/bin/env python3
"""
Verifier for configure_isolation_ward task.

This task verifies the agent's ability to configure relational hospital infrastructure.

Scoring breakdown (100 points total):
  - 30 pts: Ward created with exact name "Airborne Infection Isolation Ward"
  - 20 pts: Bed 1 ("AIIR-01") created
  - 20 pts: Bed 2 ("AIIR-02") created
  - 15 pts: Bed 1 correctly linked to the new Ward
  - 15 pts: Bed 2 correctly linked to the new Ward

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def build_vlm_prompt():
    """Build VLM prompt to verify trajectory indicates configuration workflow."""
    return """Examine these screenshots from a user's session in GNU Health.
Did the user navigate to the 'Wards' or 'Beds' configuration modules and attempt to create new records?

Look for:
- Menus showing Health -> Configuration -> Institutions
- Forms titled 'Ward' or 'Bed'
- Fields being filled out with 'Airborne' or 'AIIR'

Respond in JSON format:
{
    "navigated_to_institutions": true/false,
    "attempted_creation": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_configure_isolation_ward(traj, env_info, task_info):
    """Verify that the isolation ward and beds were correctly configured."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    expected_ward_name = metadata.get('expected_ward_name', "Airborne Infection Isolation Ward")
    
    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/configure_isolation_ward_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    # --- Extract Results ---
    ward_found = result.get('ward_found', False)
    ward_id = result.get('ward_id', 'null')
    ward_name = result.get('ward_name', '')
    any_new_wards = int(result.get('any_new_wards_count', 0))

    bed1_found = result.get('bed1_found', False)
    bed1_ward_id = result.get('bed1_ward_id', 'null')
    
    bed2_found = result.get('bed2_found', False)
    bed2_ward_id = result.get('bed2_ward_id', 'null')
    
    any_new_beds = int(result.get('any_new_beds_count', 0))

    # --- VLM Trajectory Verification ---
    vlm_confirmed = False
    if env_info.get('vlm'):
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = env_info['vlm'](prompt=build_vlm_prompt(), images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_confirmed = parsed.get('attempted_creation', False)
                if vlm_confirmed:
                    logger.info("VLM confirmed creation workflow.")

    # --- Criterion 1: Ward Creation (30 pts) ---
    if ward_found and expected_ward_name.lower() in ward_name.lower():
        score += 30
        subscores['ward_created'] = 30
        feedback_parts.append(f"Ward successfully created: '{ward_name}' (ID: {ward_id})")
    elif any_new_wards > 0:
        score += 10
        subscores['ward_created'] = 10
        feedback_parts.append(f"A new ward was created, but name did not match expected '{expected_ward_name}'")
    else:
        subscores['ward_created'] = 0
        feedback_parts.append(f"MISSING: Expected ward '{expected_ward_name}' was not created")

    # --- Criterion 2 & 3: Bed Creation (20 pts each) ---
    if bed1_found:
        score += 20
        subscores['bed1_created'] = 20
        feedback_parts.append("Bed AIIR-01 created")
    else:
        subscores['bed1_created'] = 0
        feedback_parts.append("MISSING: Bed AIIR-01 not found")

    if bed2_found:
        score += 20
        subscores['bed2_created'] = 20
        feedback_parts.append("Bed AIIR-02 created")
    else:
        subscores['bed2_created'] = 0
        feedback_parts.append("MISSING: Bed AIIR-02 not found")

    if not bed1_found and not bed2_found and any_new_beds > 0:
        score += 10  # Partial credit for figuring out how to make a bed but messing up names
        feedback_parts.append(f"{any_new_beds} new bed(s) created, but names did not match AIIR-01/AIIR-02")

    # --- Criterion 4 & 5: Relational Integrity (15 pts each) ---
    # Only applicable if the target ward was actually created
    if ward_found and ward_id != 'null':
        if bed1_found and str(bed1_ward_id) == str(ward_id):
            score += 15
            subscores['bed1_linked'] = 15
            feedback_parts.append("Bed AIIR-01 correctly linked to the new Ward")
        elif bed1_found:
            subscores['bed1_linked'] = 0
            feedback_parts.append(f"Bed AIIR-01 is NOT linked to the new Ward (Linked to {bed1_ward_id} instead of {ward_id})")
        else:
            subscores['bed1_linked'] = 0

        if bed2_found and str(bed2_ward_id) == str(ward_id):
            score += 15
            subscores['bed2_linked'] = 15
            feedback_parts.append("Bed AIIR-02 correctly linked to the new Ward")
        elif bed2_found:
            subscores['bed2_linked'] = 0
            feedback_parts.append(f"Bed AIIR-02 is NOT linked to the new Ward (Linked to {bed2_ward_id} instead of {ward_id})")
        else:
            subscores['bed2_linked'] = 0
    else:
        subscores['bed1_linked'] = 0
        subscores['bed2_linked'] = 0
        if bed1_found or bed2_found:
            feedback_parts.append("Cannot verify Bed -> Ward linkages because the target Ward was not successfully created")

    # Combine feedback and determine pass
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }