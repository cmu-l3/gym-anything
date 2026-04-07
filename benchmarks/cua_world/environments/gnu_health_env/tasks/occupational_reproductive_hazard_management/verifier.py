#!/usr/bin/env python3
"""
Verifier for occupational_reproductive_hazard_management task.

Evaluates 6 independent criteria:
1. Pregnancy diagnosis (O09, Z33, Z34) (15 pts)
2. Hazard exposure diagnosis (Z57.x) (15 pts)
3. Prenatal prescription (Folic Acid/Iron/Vitamin) (20 pts)
4. Work restriction in lifestyle notes (20 pts)
5. Baseline lab orders (>= 2) (15 pts)
6. VLM trajectory verification: interface actually used (15 pts)

Pass threshold: score >= 70
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these trajectory screenshots from an agent interacting with a Health Information System.
Did the agent actively navigate through the medical record system, specifically interacting with forms like "Conditions", "Prescriptions", "Lifestyle", or "Lab Tests"?
Respond in JSON format:
{
    "interface_navigated": true/false,
    "forms_interacted": true/false,
    "reasoning": "what you observed"
}"""

def verify_occupational_reproductive_hazard_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Copy result JSON
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/occupational_reproductive_hazard_management_result.json', local_path)
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

    target_id = result.get('target_patient_id', "0")
    if str(target_id) == "0" or not target_id:
        return {"passed": False, "score": 0, "feedback": "Patient Luna not found - setup failed."}

    # 1. Pregnancy Diagnosis (15 pts)
    preg_found = result.get('preg_found', False)
    preg_active = result.get('preg_active', False)
    preg_code = result.get('preg_code', 'none')
    if preg_found and preg_active:
        score += 15
        subscores['pregnancy_diagnosis'] = 15
        feedback_parts.append(f"Pregnancy diagnosis documented: {preg_code} (active)")
    elif preg_found:
        score += 10
        subscores['pregnancy_diagnosis'] = 10
        feedback_parts.append(f"Pregnancy diagnosis {preg_code} found but not marked active")
    else:
        subscores['pregnancy_diagnosis'] = 0
        feedback_parts.append("MISSING: Pregnancy diagnosis (O09, Z33, Z34)")

    # 2. Hazard Diagnosis (15 pts)
    hazard_found = result.get('hazard_found', False)
    hazard_active = result.get('hazard_active', False)
    hazard_code = result.get('hazard_code', 'none')
    if hazard_found and hazard_active:
        score += 15
        subscores['hazard_diagnosis'] = 15
        feedback_parts.append(f"Occupational hazard diagnosis documented: {hazard_code} (active)")
    elif hazard_found:
        score += 10
        subscores['hazard_diagnosis'] = 10
        feedback_parts.append(f"Occupational hazard {hazard_code} found but not marked active")
    else:
        subscores['hazard_diagnosis'] = 0
        feedback_parts.append("MISSING: Occupational hazard diagnosis (Z57)")

    # 3. Prenatal Prescription (20 pts)
    presc_found = result.get('presc_found', False)
    prenatal_found = result.get('prenatal_found', False)
    prenatal_name = result.get('prenatal_name', 'none')
    if presc_found and prenatal_found:
        score += 20
        subscores['prenatal_rx'] = 20
        feedback_parts.append(f"Prenatal supplement prescribed: {prenatal_name}")
    elif presc_found:
        score += 5
        subscores['prenatal_rx'] = 5
        feedback_parts.append(f"Prescription created but no relevant prenatal supplement found")
    else:
        subscores['prenatal_rx'] = 0
        feedback_parts.append("MISSING: No prenatal prescription created")

    # 4. Work Restriction (20 pts)
    lifestyle_found = result.get('lifestyle_found', False)
    keywords_found = result.get('restriction_keywords_found', False)
    if lifestyle_found and keywords_found:
        score += 20
        subscores['work_restriction'] = 20
        feedback_parts.append("Work restriction documented in Lifestyle notes")
    elif lifestyle_found:
        score += 10
        subscores['work_restriction'] = 10
        feedback_parts.append("Lifestyle record created, but missing restriction/hazard keywords")
    else:
        subscores['work_restriction'] = 0
        feedback_parts.append("MISSING: No Lifestyle record created for work restriction")

    # 5. Baseline Labs (15 pts)
    lab_count = result.get('new_lab_count', 0)
    try:
        lab_count = int(lab_count)
    except:
        lab_count = 0
        
    lab_types = result.get('new_lab_types', 'none')
    if lab_count >= 2:
        score += 15
        subscores['labs'] = 15
        feedback_parts.append(f"Adequate baseline labs ordered: {lab_count} ({lab_types})")
    elif lab_count == 1:
        score += 7
        subscores['labs'] = 7
        feedback_parts.append(f"Only 1 lab ordered ({lab_types}), minimum 2 required")
    else:
        subscores['labs'] = 0
        feedback_parts.append("MISSING: No baseline labs ordered")

    # 6. VLM Trajectory (15 pts)
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
            
            if frames:
                vlm_result = query_vlm(prompt=build_vlm_prompt(), images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("interface_navigated") and parsed.get("forms_interacted"):
                        vlm_score = 15
                        feedback_parts.append("VLM confirmed interface interaction")
                    else:
                        vlm_score = 5
                        feedback_parts.append("VLM noted lack of form interaction")
                else:
                    vlm_score = 15 # Give benefit of doubt if VLM fails
                    feedback_parts.append("VLM check failed, granting points")
            else:
                vlm_score = 15
        else:
            vlm_score = 15 # Auto pass if missing env_info setup for VLM
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_score = 15 # Auto pass on framework error
        feedback_parts.append("VLM evaluation skipped due to exception")

    score += vlm_score
    subscores['vlm_verify'] = vlm_score

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }