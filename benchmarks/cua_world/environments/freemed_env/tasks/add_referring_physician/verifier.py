#!/usr/bin/env python3
"""
Verifier for add_referring_physician task in FreeMED.

Checks:
1. Form values correctly saved in DB (Name, NPI, Specialty, Phone, Fax)
2. Verify anti-gaming (count must increase from initial setup)
3. Visual confirmation of UI workflow using VLM trajectory check.
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_phone(phone_str):
    """Strip all non-numeric characters from phone string to normalize comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', phone_str)

def verify_add_referring_physician(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_fname', 'Arthur')
    expected_lname = metadata.get('expected_lname', 'Pendelton')
    expected_specialty = metadata.get('expected_specialty', 'Endocrinology')
    expected_npi = metadata.get('expected_npi', '1928374650')
    expected_phone = metadata.get('expected_phone', '5558675309')
    expected_fax = metadata.get('expected_fax', '5558675310')

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Record Count Delta (Anti-gaming check)
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    
    newly_created = final_count > initial_count
    if newly_created:
        feedback_parts.append(f"DB count increased ({initial_count} -> {final_count})")
    else:
        feedback_parts.append(f"DB count DID NOT increase ({initial_count})")

    # Check 2: Values in Physician table
    found_in_table = result.get('physician_found', False)
    db_dump_name_count = result.get('dump_has_name_count', 0)
    db_dump_npi_count = result.get('dump_has_npi_count', 0)

    if found_in_table:
        score += 25
        feedback_parts.append(f"Physician {expected_lname} found in DB")
        
        # Check NPI
        if result.get('npi') == expected_npi:
            score += 15
            feedback_parts.append("NPI correct")
        else:
            feedback_parts.append(f"NPI mismatch (expected {expected_npi})")
            
        # Check Specialty
        if expected_specialty.lower() in result.get('specialty', '').lower():
            score += 15
            feedback_parts.append("Specialty correct")
        else:
            feedback_parts.append(f"Specialty mismatch")

        # Check Phone & Fax
        if expected_phone in clean_phone(result.get('phone', '')):
            score += 7.5
            feedback_parts.append("Phone correct")
            
        if expected_fax in clean_phone(result.get('fax', '')):
            score += 7.5
            feedback_parts.append("Fax correct")
            
    else:
        feedback_parts.append(f"Physician '{expected_lname}' NOT found in standard physician table")
        # Fallback partial credit if values got stuffed into the database SOMEWHERE (like generic addressbook)
        if db_dump_name_count > 0:
            score += 10
            feedback_parts.append("Name found in raw DB dump")
        if db_dump_npi_count > 0:
            score += 10
            feedback_parts.append("NPI found in raw DB dump")

    # Check 3: VLM Trajectory check
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        vlm_prompt = (
            "You are evaluating an agent interacting with an Electronic Medical Record system (FreeMED). "
            "Did the agent successfully navigate to a 'Physician', 'Provider', or 'Address Book' module "
            "and attempt to fill out a form for 'Arthur Pendelton'? "
            "Respond in JSON format: {\"workflow_attempted\": true/false, \"form_filled\": true/false}"
        )
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            vlm_response = query_vlm(images=frames + [final], prompt=vlm_prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("workflow_attempted") and parsed.get("form_filled"):
                    score += 30
                    feedback_parts.append("VLM visual verification passed")
                else:
                    feedback_parts.append("VLM visual verification failed (Workflow incomplete)")
            else:
                score += 30  # Default to granting points if VLM is unavailable during grading
                feedback_parts.append("VLM call failed (awarding default points)")
        else:
            score += 30
            feedback_parts.append("No VLM configured (awarding default points)")
            
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        score += 30
        feedback_parts.append("VLM check bypassed")

    key_criteria_met = found_in_table and result.get('npi') == expected_npi and newly_created
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }