#!/usr/bin/env python3
"""
Verifier for the owner_operator_certification task.

This verifier uses a hybrid approach:
1. Programmatic Verification (65 points): Parses the extracted Tier II XML data 
   to confirm the presence of specific entities (Owner and Operator) and their 
   associated addresses, phone numbers, DUNS numbers, and certifier details.
2. VLM Trajectory Verification (35 points): Evaluates trajectory frames to ensure
   the agent navigated through the actual Tier2 Submit UI, proving the work was 
   done authentically and not via a direct XML injection/hack.
"""

import json
import os
import re
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify UI interaction
VLM_PROMPT = """You are auditing an agent's completion of an EPA Tier II hazardous chemical report.
Review the provided sequence of screenshots taken during the agent's workflow.

Assess the following:
1. Did the agent navigate to the "Owner/Operator" screen/tab within the Tier II Submit application?
2. Is there visual evidence of the agent entering data for "Gulf Coast Chemical" or "Pelican Chemical"?
3. Did the agent navigate to the "Certification" section/screen?
4. Is there evidence of the agent entering certifier details (e.g. Marcus D. Thibodaux)?

Respond in JSON format:
{
    "visited_owner_operator_screen": true/false,
    "visited_certification_screen": true/false,
    "entered_entity_data": true/false,
    "entered_certification_data": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_owner_operator_certification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', r'C:\Users\Docker\Desktop\owner_operator_certification_result.json')
    pass_threshold = metadata.get('pass_threshold', 65)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()

    try:
        copy_from_env(result_file, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Do-nothing check
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file was not created or saved at the expected path."}

    raw_xml = result.get('raw_xml', '')
    if not raw_xml:
        return {"passed": False, "score": 0, "feedback": "Target file contains no XML submission data."}

    # Normalize XML for robust string matching (ignoring exact tag schema)
    xml_lower = raw_xml.lower()
    # Strip all non-alphanumeric chars to easily find formatted numbers (phones/dates/DUNS)
    xml_no_punct = re.sub(r'[^a-z0-9]', '', xml_lower)

    score = 10  # 10 base points for saving the file properly with XML content
    feedback = ["PASS: Target file saved and contains XML data (+10)"]

    # --- 1. Owner Entity Verification (20 points total) ---
    expected_owner = metadata.get('expected_owner', {})
    if expected_owner.get('name', 'gulf coast chemical').lower() in xml_lower:
        score += 5
        feedback.append("PASS: Owner Company Name found (+5)")
    else:
        feedback.append("FAIL: Owner Company Name missing")

    if expected_owner.get('address', '8500 river road').lower() in xml_lower:
        score += 5
        feedback.append("PASS: Owner Address found (+5)")
    else:
        feedback.append("FAIL: Owner Address missing")

    if expected_owner.get('phone', '2253870142') in xml_no_punct:
        score += 5
        feedback.append("PASS: Owner Phone found (+5)")
    else:
        feedback.append("FAIL: Owner Phone missing")

    if expected_owner.get('duns', '078436291') in xml_no_punct:
        score += 5
        feedback.append("PASS: Owner DUNS found (+5)")
    else:
        feedback.append("FAIL: Owner DUNS missing")

    # --- 2. Operator Entity Verification (20 points total) ---
    expected_operator = metadata.get('expected_operator', {})
    if expected_operator.get('name', 'pelican chemical').lower() in xml_lower:
        score += 5
        feedback.append("PASS: Operator Company Name found (+5)")
    else:
        feedback.append("FAIL: Operator Company Name missing")

    if expected_operator.get('address', 'suite 200').lower() in xml_lower:
        score += 5
        feedback.append("PASS: Operator Address/Suite found (+5)")
    else:
        feedback.append("FAIL: Operator Address/Suite missing")

    if expected_operator.get('phone', '2253870198') in xml_no_punct:
        score += 5
        feedback.append("PASS: Operator Phone found (+5)")
    else:
        feedback.append("FAIL: Operator Phone missing")

    if expected_operator.get('duns', '081527340') in xml_no_punct:
        score += 5
        feedback.append("PASS: Operator DUNS found (+5)")
    else:
        feedback.append("FAIL: Operator DUNS missing")

    # --- 3. Certifier Verification (15 points total) ---
    expected_certifier = metadata.get('expected_certifier', {})
    cert_name = expected_certifier.get('name', 'marcus d thibodaux').replace('.', '').lower()
    if cert_name in xml_no_punct:
        score += 5
        feedback.append("PASS: Certifier Name found (+5)")
    else:
        feedback.append("FAIL: Certifier Name missing")

    if expected_certifier.get('title', 'environmental health and safety manager').lower() in xml_lower:
        score += 5
        feedback.append("PASS: Certifier Title found (+5)")
    else:
        feedback.append("FAIL: Certifier Title missing")

    date_iso = expected_certifier.get('date_iso', '20250301')
    date_us = expected_certifier.get('date_us', '03012025')
    if date_iso in xml_no_punct or date_us in xml_no_punct:
        score += 5
        feedback.append("PASS: Certification Date found (+5)")
    else:
        feedback.append("FAIL: Certification Date missing")

    # --- 4. VLM Trajectory Verification (35 points) ---
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames

            if images:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    vlm_criteria = [
                        parsed.get("visited_owner_operator_screen", False),
                        parsed.get("visited_certification_screen", False),
                        parsed.get("entered_entity_data", False),
                        parsed.get("entered_certification_data", False)
                    ]
                    
                    vlm_points = sum(vlm_criteria) * (35 / 4)
                    score += int(vlm_points)
                    
                    if sum(vlm_criteria) == 4:
                        feedback.append(f"PASS: VLM confirmed full trajectory interaction (+35)")
                    else:
                        feedback.append(f"PARTIAL: VLM confirmed {sum(vlm_criteria)}/4 UI interaction steps (+{int(vlm_points)})")
                else:
                    feedback.append("WARNING: VLM query failed, skipping visual verification points.")
        except Exception as e:
            logger.warning(f"VLM trajectory verification encountered an error: {e}")
            feedback.append("WARNING: VLM Exception, trajectory check failed.")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }