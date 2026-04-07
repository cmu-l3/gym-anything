#!/usr/bin/env python3
"""Verifier for emr_to_edc_data_transcription task."""

import json
import tempfile
import os
import logging
import sys

# Import VLM utils
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

def _build_vlm_prompt():
    return """You are verifying a clinical research agent's workflow. The agent was tasked with transcribing data from an EMR text file into OpenClinica.

Examine these trajectory frames and determine:
1. Did the agent at any point open a text editor, terminal, or file viewer showing the 'PATIENT ENCOUNTER SUMMARY' for John Smith?
2. Did the agent interact with the OpenClinica web interface to enter data?
3. Did the agent use a calculator or spreadsheet to convert inches to cm or lbs to kg? (This is a bonus/supplemental indicator, not strictly required if they did it mentally).

Respond in JSON format:
{
    "emr_file_opened": true/false,
    "openclinica_used": true/false,
    "calculator_used": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_emr_transcription(traj, env_info, task_info):
    """
    Verify the EMR to EDC Data Transcription task.

    Scoring (100 points total):
    - Subject CV-106 enrolled with correct DOB and Gender: 20 pts
    - Baseline Encounter scheduled on correct date: 20 pts
    - Raw Vitals Transcribed (HR 82, SysBP 145, DiaBP 92): 20 pts
    - Unit Conversion Note exists with 177.8 cm and 88.5 kg: 20 pts
    - VLM Trajectory Check (EMR read + EDC used): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/emr_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Subject Enrollment
    if result.get("cv106_found", False):
        gender = result.get("cv106_gender", "").lower()
        dob = result.get("cv106_dob", "")
        
        if gender.startswith('m') and "1965-08-22" in dob:
            score += 20
            feedback_parts.append("CV-106 enrolled with correct DOB/Gender (+20)")
        else:
            score += 10
            feedback_parts.append(f"CV-106 enrolled but demographic mismatch (DOB: {dob}, Gender: {gender}) (+10)")
    else:
        feedback_parts.append("FAIL: Subject CV-106 not found (0/20)")

    # 2. Check Event Schedule
    event_date = result.get("event_date", "")
    if "2024-05-14" in event_date:
        score += 20
        feedback_parts.append("Encounter scheduled on correct date (+20)")
    elif event_date:
        score += 5
        feedback_parts.append(f"Encounter scheduled, but wrong date: {event_date} (+5)")
    else:
        feedback_parts.append("FAIL: Encounter not scheduled (0/20)")

    # 3. Check Vitals Transcription (82, 145, 92)
    item_values = result.get("item_values", "")
    vitals_found = 0
    for val in ["82", "145", "92"]:
        if val in item_values:
            vitals_found += 1
            
    if vitals_found == 3:
        score += 20
        feedback_parts.append("All 3 raw vitals transcribed correctly (+20)")
    elif vitals_found > 0:
        score += (vitals_found * 6)
        feedback_parts.append(f"Partial vitals transcribed: {vitals_found}/3 (+{vitals_found*6})")
    else:
        feedback_parts.append("FAIL: No matching vitals transcribed (0/20)")

    # 4. Check Unit Conversion in Discrepancy Notes
    notes = result.get("discrepancy_notes", "")
    conversion_score = 0
    
    # 70 in -> 177.8 cm
    if "177.8" in notes:
        conversion_score += 10
        feedback_parts.append("Height conversion correct: 177.8 cm (+10)")
    elif "178" in notes: # Accept rounding to integer
        conversion_score += 8
        feedback_parts.append("Height conversion rounded: 178 cm (+8)")
        
    # 195 lbs -> 88.45 kg -> 88.5 kg (accept 88.4 or 88.5)
    if "88.5" in notes or "88.4" in notes:
        conversion_score += 10
        feedback_parts.append("Weight conversion correct: 88.5 kg (+10)")
    elif "88" in notes or "89" in notes: # Accept integer rounding
        conversion_score += 8
        feedback_parts.append("Weight conversion rounded (+8)")

    if conversion_score == 0:
        feedback_parts.append("FAIL: Correct unit conversion annotations not found (0/20)")
    else:
        score += conversion_score

    # 5. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=_build_vlm_prompt())
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("emr_file_opened", False) and parsed.get("openclinica_used", False):
                    vlm_score += 20
                    feedback_parts.append("VLM confirmed EMR reading and EDC usage (+20)")
                elif parsed.get("openclinica_used", False):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed partial workflow (+10)")
                else:
                    feedback_parts.append("VLM did not detect correct workflow (0/20)")
            else:
                feedback_parts.append("VLM query failed, skipping workflow score.")
    
    score += vlm_score

    # Pass criteria: score >= 60 and at least one vital or conversion recorded
    key_data_entered = (vitals_found > 0 or conversion_score > 0)
    passed = (score >= 60) and key_data_entered

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }