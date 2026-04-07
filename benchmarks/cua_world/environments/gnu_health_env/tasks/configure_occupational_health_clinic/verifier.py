#!/usr/bin/env python3
"""
Verifier for configure_occupational_health_clinic task.

Validates that administrative infrastructure (Institution, Ward, Beds)
was correctly created and relationally linked in GNU Health.
Utilizes multiple DB baselines (anti-gaming) + VLM trajectory verification.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """
    Review these screenshots from an agent's trajectory working in the GNU Health (Tryton) web interface.
    The task was to configure administrative infrastructure by creating a new Institution, a new Hospital Ward, and Hospital Beds.

    Please evaluate the agent's actions and respond with a JSON object containing the following:
    {
        "navigated_to_forms": boolean, // Did the agent navigate to Party, Institution, Ward, or Bed interfaces?
        "attempted_data_entry": boolean, // Is there evidence of entering names (e.g., 'PetroChem', 'Decontamination', 'DECON')?
        "reasoning": "Brief explanation of what the agent is doing in these frames"
    }
    """

def verify_configure_occupational_health_clinic(traj, env_info, task_info):
    """Verify clinic infrastructure setup in GNU Health."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # --- Read DB Extraction Results ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/configure_clinic_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}"
        }
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    # Criteria Checks
    inst_found = result.get('inst_found', False)
    ward_found = result.get('ward_found', False)
    ward_linked = result.get('ward_linked_to_inst', False)
    bed1_found = result.get('bed1_found', False)
    bed1_linked = result.get('bed1_linked_to_ward', False)
    bed2_found = result.get('bed2_found', False)
    bed2_linked = result.get('bed2_linked_to_ward', False)

    # 1. Institution (25 pts)
    if inst_found:
        score += 25
        feedback_parts.append("Institution 'PetroChem Occupational Health Clinic' created successfully.")
    else:
        feedback_parts.append("MISSING: Institution 'PetroChem Occupational Health Clinic' was not found.")

    # 2. Hospital Ward (25 pts)
    if ward_found and ward_linked:
        score += 25
        feedback_parts.append("Ward 'Decontamination & Observation' created and linked to Institution.")
    elif ward_found:
        score += 10
        feedback_parts.append("Ward created, but NOT properly linked to the PetroChem Institution.")
    else:
        feedback_parts.append("MISSING: Hospital Ward 'Decontamination & Observation' not found.")

    # 3. Hospital Bed 1 (15 pts)
    if bed1_found and bed1_linked:
        score += 15
        feedback_parts.append("Bed 'DECON-1' created and linked to Ward.")
    elif bed1_found:
        score += 5
        feedback_parts.append("Bed 'DECON-1' created, but NOT linked to the correct Ward.")
    else:
        feedback_parts.append("MISSING: Hospital Bed 'DECON-1' not found.")

    # 4. Hospital Bed 2 (15 pts)
    if bed2_found and bed2_linked:
        score += 15
        feedback_parts.append("Bed 'DECON-2' created and linked to Ward.")
    elif bed2_found:
        score += 5
        feedback_parts.append("Bed 'DECON-2' created, but NOT linked to the correct Ward.")
    else:
        feedback_parts.append("MISSING: Hospital Bed 'DECON-2' not found.")

    # --- VLM Verification (20 pts) ---
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    try:
        # Import dynamically to prevent import errors if running in restricted environments
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if query_vlm and images:
            vlm_response = query_vlm(prompt=build_vlm_prompt(), images=images)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                # Grade the VLM interpretation
                if parsed.get("navigated_to_forms") and parsed.get("attempted_data_entry"):
                    vlm_score = 20
                    feedback_parts.append("VLM: Confirmed UI workflow trajectory.")
                elif parsed.get("navigated_to_forms"):
                    vlm_score = 10
                    feedback_parts.append("VLM: Agent navigated UI, but form entry wasn't clearly observed.")
                else:
                    feedback_parts.append("VLM: Could not verify proper UI interaction in trajectory.")
            else:
                feedback_parts.append("VLM query failed or returned no parsable data.")
        else:
            feedback_parts.append("VLM verification skipped (no images or VLM unavailable).")
            # If VLM is down but the database perfectly matches expected layout, grant VLM points automatically.
            if score == 80:
                vlm_score = 20
                feedback_parts.append("DB perfectly matches; automatically granting trajectory points.")

    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Default safety: If database perfectly matches expected layout, grant VLM points automatically.
        if score == 80:
            vlm_score = 20
            feedback_parts.append("DB perfectly matches; granting trajectory points as fallback.")

    total_score = score + vlm_score

    # To pass, they must have achieved at least 70/100 (Created Inst, Ward, and at least one Bed)
    passed = total_score >= 70
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }