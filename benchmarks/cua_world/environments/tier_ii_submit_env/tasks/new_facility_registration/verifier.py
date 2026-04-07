#!/usr/bin/env python3
"""
Verifier for New Facility Registration task (EPA Tier2 Submit).

Verification Strategy:
1. File Existence & Timestamps (Anti-gaming check)
2. Content Verification (Parses the exported .t2s file content for exact required values)
3. VLM Verification (Validates workflow progression and specific UI checkboxes via trajectory)
"""

import os
import json
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Verification Prompt ---
VLM_PROMPT = """You are analyzing an AI agent performing a regulatory data entry task in EPA Tier2 Submit.
The agent was asked to create a new facility named 'Eastport Chemical Distribution Center' and fill out its details.

Review the chronological screenshots from the agent's trajectory.
Please check for the following indicators of successful task execution:
1. Did the agent navigate through multiple facility data tabs (e.g., Facility Identification, Owner/Operator, Emergency Contact)?
2. In the regulatory designations (usually at the bottom or on a specific tab), did the agent check the box for "Subject to EPCRA Section 302"?
3. Is there visual evidence that "Eastport Chemical Distribution Center" was entered as the facility name?

Respond in JSON format:
{
    "navigated_multiple_tabs": true/false,
    "epcra_302_checked": true/false,
    "facility_name_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def extract_text_from_t2s(file_path):
    """
    Tier2 Submit (.t2s) files are typically ZIP archives containing XML/JSON.
    This extracts all textual data from the file for robust substring searching,
    bypassing strict schema parsing which might break across software versions.
    """
    extracted_text = ""
    try:
        if zipfile.is_zipfile(file_path):
            with zipfile.ZipFile(file_path, 'r') as zf:
                for filename in zf.namelist():
                    with zf.open(filename) as f:
                        extracted_text += f.read().decode('utf-8', errors='ignore') + " "
        else:
            # Fallback if it's not a ZIP (e.g., pure XML/JSON)
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                extracted_text = f.read()
    except Exception as e:
        logger.error(f"Error reading .t2s file: {e}")
        
    return extracted_text.lower()

def verify_new_facility_registration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_vals = metadata.get("expected_values", {})
    result_json_path = metadata.get("result_json", "C:\\Users\\Docker\\Desktop\\new_facility_registration_result.json")
    result_t2s_path = metadata.get("result_t2s", "C:\\Users\\Docker\\Desktop\\Eastport_CDC.t2s")
    
    score = 0
    feedback_parts = []
    max_score = 100

    # 1. Retrieve metadata JSON
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    
    result_data = {}
    try:
        copy_from_env(result_json_path, tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Check File Existence & Timestamp (13 points total)
    if not result_data.get("output_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file Eastport_CDC.t2s was not created or saved to the correct directory."
        }
    
    score += 8
    feedback_parts.append("File exists (+8)")

    if result_data.get("file_created_during_task", False):
        score += 5
        feedback_parts.append("File created/modified during task (+5)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might have been created before the task start.")

    # 3. Retrieve and Parse .t2s File Content (80 points total for data fields)
    extracted_text = ""
    try:
        copy_from_env(result_t2s_path, tmp_t2s.name)
        extracted_text = extract_text_from_t2s(tmp_t2s.name)
    except Exception as e:
        feedback_parts.append(f"Error retrieving/parsing .t2s file: {e}")
    finally:
        if os.path.exists(tmp_t2s.name):
            os.unlink(tmp_t2s.name)

    if extracted_text:
        # Check specific fields via string matching
        checks = [
            ("facility_name", 10, "Facility Name"),
            ("address", 7, "Street Address"),
            ("city", 4, "City"),
            ("state", 2, "State"),
            ("zip", 2, "ZIP"),
            ("lat", 5, "Latitude"),
            ("lon", 5, "Longitude"),
            ("naics", 7, "NAICS Code"),
            ("db", 5, "D&B Number"),
            ("year", 5, "Reporting Year"),
            ("owner_name", 8, "Owner Name"),
            ("owner_address", 5, "Owner Address"),
            ("coordinator_name", 7, "Coordinator Name"),
            ("coordinator_title", 3, "Coordinator Title"),
            ("coordinator_phone", 5, "Coordinator Phone")
        ]

        for key, points, desc in checks:
            expected_val = expected_vals.get(key, "").lower()
            if expected_val and expected_val in extracted_text:
                score += points
                feedback_parts.append(f"{desc} present (+{points})")
            else:
                feedback_parts.append(f"{desc} missing or incorrect")
    else:
        feedback_parts.append("Failed to extract textual data from the saved file. No content points awarded.")

    # 4. VLM Trajectory Verification (7 points for Designations & Workflow)
    # This acts as a robust check for the boolean EPCRA 302 flag and anti-gaming visual confirmation
    vlm_score = 0
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=6)
    if frames:
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("epcra_302_checked", False):
                vlm_score += 4
                feedback_parts.append("VLM confirmed EPCRA 302 checked (+4)")
            if parsed.get("navigated_multiple_tabs", False):
                vlm_score += 3
                feedback_parts.append("VLM confirmed multi-tab navigation (+3)")
    
    score += vlm_score

    # Determine passing status
    # Pass requires >= 60 total score, AND core items must be present (Name, City/State/Zip)
    core_present = (expected_vals.get("facility_name", "") in extracted_text and
                    expected_vals.get("city", "") in extracted_text)
    
    passed = score >= 60 and core_present

    if passed:
        feedback_parts.insert(0, "TASK PASSED")
    else:
        feedback_parts.insert(0, "TASK FAILED")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }