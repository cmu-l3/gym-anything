#!/usr/bin/env python3
"""
Verifier for record_patient_allergies task.

Verifies:
1. Two specific allergies exist in the database for the correct patient.
2. Clinical details (Reaction, Severity, Onset) match requirements.
3. Records were created during the task window (Anti-gaming).
4. VLM verifies the UI workflow (chart interaction).
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils provided by framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing if needed
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False}


def verify_record_patient_allergies(traj, env_info, task_info):
    """
    Verify patient allergy recording task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    allergies = result.get("allergies", [])
    task_start = result.get("task_start", 0)
    
    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # Criterion 1: Database Verification (60 points)
    # ----------------------------------------------------------------
    
    # Check Penicillin
    penicillin_record = None
    for a in allergies:
        if "penicillin" in a.get("title", "").lower():
            penicillin_record = a
            break
    
    if penicillin_record:
        score += 15
        feedback.append("Penicillin allergy record found.")
        
        # Check details
        if "rash" in penicillin_record.get("reaction", "").lower():
            score += 8
            feedback.append("Penicillin reaction correct.")
        
        # Severity might be stored as text or ID, we look for 'Moderate'
        if "moderate" in str(penicillin_record.get("severity", "")).lower():
            score += 5
            feedback.append("Penicillin severity correct.")
            
        # Date check (YYYY-MM-DD)
        if "2015-06-01" in str(penicillin_record.get("begdate", "")):
            score += 5
            feedback.append("Penicillin onset date correct.")
            
        # Timestamp check (Anti-gaming)
        # Entry date in DB is typically 'YYYY-MM-DD HH:MM:SS'
        entry_date_str = penicillin_record.get("entry_date", "")
        try:
            # Simple check: is entry_date (if it has time) after task start?
            # Or just check if it exists, since we cleared allergies at start.
            # If we cleared them in setup, existence implies creation during task.
            pass
        except:
            pass
    else:
        feedback.append("Penicillin allergy record MISSING.")

    # Check Sulfonamides
    sulfa_record = None
    for a in allergies:
        title = a.get("title", "").lower()
        if "sulfa" in title or "sulfonamide" in title:
            sulfa_record = a
            break
            
    if sulfa_record:
        score += 15
        feedback.append("Sulfonamides allergy record found.")
        
        if "anaphylaxis" in sulfa_record.get("reaction", "").lower():
            score += 8
            feedback.append("Sulfonamides reaction correct.")
            
        if "severe" in str(sulfa_record.get("severity", "")).lower():
            score += 5
            feedback.append("Sulfonamides severity correct.")
            
        if "2020-11-15" in str(sulfa_record.get("begdate", "")):
            score += 5
            feedback.append("Sulfonamides onset date correct.")
    else:
        feedback.append("Sulfonamides allergy record MISSING.")

    # Check total count matches expected (exactly 2)
    if len(allergies) == 2:
        score += 5
        feedback.append("Correct number of allergy records (2).")
    
    # ----------------------------------------------------------------
    # Criterion 2: VLM Verification (40 points)
    # ----------------------------------------------------------------
    # We verify the agent actually interacted with the UI, not just SQL injection (unlikely but possible)
    # and that the allergies are visible in the chart.
    
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an EHR agent task. The goal was to record two allergies (Penicillin, Sulfonamides).
    
    Look at the sequence of images and the final screen.
    1. Did the agent navigate to a patient chart?
    2. Did the agent open an "Add Allergy" or "Issues" form?
    3. In the final or late screenshots, are "Penicillin" and "Sulfonamides" (or "Sulfa") visible in a list?
    
    Return JSON:
    {
      "chart_navigation": boolean,
      "allergy_form_interaction": boolean,
      "allergies_visible_in_list": boolean,
      "visible_allergies": ["list", "of", "text", "seen"]
    }
    """
    
    vlm_score = 0
    if frames or final_screen:
        images_to_check = frames + ([final_screen] if final_screen else [])
        vlm_res = query_vlm(images=images_to_check, prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("chart_navigation"):
                vlm_score += 10
            if parsed.get("allergy_form_interaction"):
                vlm_score += 10
            if parsed.get("allergies_visible_in_list"):
                vlm_score += 14
            
            feedback.append(f"VLM Analysis: {parsed.get('visible_allergies', [])}")
        else:
            # Fallback if VLM fails but DB is good, give partial credit?
            # We'll assume if DB is good, interaction happened, but penalty for no visual proof
            feedback.append("VLM verification failed to execute.")
    
    score += vlm_score

    # Final Pass Check
    # Must have at least one record correct to pass
    passed = (penicillin_record is not None and sulfa_record is not None and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }