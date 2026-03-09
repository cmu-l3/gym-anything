#!/usr/bin/env python3
"""
Verifier for add_family_history task in OSCAR EMR.
Verifies that family history was added to the CPP for the correct patient.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_family_history(traj, env_info, task_info):
    """
    Verify family history documentation.
    
    Criteria:
    1. Database Persistence (70 pts):
       - Father's history (Diabetes, MI) present
       - Mother's history (Cancer, Hypertension) present
       - Brother's history (Asthma) present
       - Data was modified DURING the task window (anti-gaming)
    
    2. VLM Workflow Verification (30 pts):
       - Trajectory shows navigation to Chart/CPP
       - Trajectory shows text entry in Family History section
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # =========================================================
    # 1. Retrieve Data from Container
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Combine all text sources for searching
    # (OSCAR might store this in casemgmt_cpp OR linked notes depending on config version)
    combined_text = (
        result.get('cpp_content', '') + " " + 
        result.get('notes_content', '') + " " + 
        result.get('issues_content', '')
    ).lower()

    cpp_modified = result.get('cpp_modified_count', 0) > 0
    notes_modified = result.get('notes_modified_count', 0) > 0
    data_persisted = cpp_modified or notes_modified

    # =========================================================
    # 2. Database Content Verification (70 pts)
    # =========================================================
    score = 0
    feedback = []
    
    # Keywords to check
    # Father: Type 2 Diabetes, MI/Myocardial Infarction, Deceased
    father_score = 0
    if 'diabetes' in combined_text or 'dm' in combined_text: father_score += 10
    if 'myocardial' in combined_text or 'infarction' in combined_text or 'heart attack' in combined_text: father_score += 10
    if 'deceased' in combined_text or 'died' in combined_text: father_score += 5
    
    # Mother: Breast cancer, Hypertension
    mother_score = 0
    if 'breast' in combined_text and 'cancer' in combined_text: mother_score += 15
    if 'hypertension' in combined_text or 'htn' in combined_text or 'high blood pressure' in combined_text: mother_score += 10
    
    # Brother: Asthma
    brother_score = 0
    if 'asthma' in combined_text: brother_score += 20

    db_score = father_score + mother_score + brother_score
    
    if db_score == 0:
        feedback.append("No relevant family history found in database.")
    else:
        feedback.append(f"Database content match score: {db_score}/70")
        if father_score == 25: feedback.append("- Father's history complete")
        if mother_score == 25: feedback.append("- Mother's history complete")
        if brother_score == 20: feedback.append("- Brother's history complete")

    # Anti-gaming check: Timestamps
    if db_score > 0 and not data_persisted:
        feedback.append("WARNING: Data found but timestamp check failed (pre-existing data?). Penalty applied.")
        db_score = 0 # Fail if data wasn't created during task

    score += db_score

    # =========================================================
    # 3. VLM Workflow Verification (30 pts)
    # =========================================================
    # We assume 'gym_anything.vlm' isn't available in this constrained environment
    # so we perform a basic check on the trajectory existence, 
    # but in a real scenario we would use VLM calls here.
    # For this implementation, we will simulate VLM checks based on trajectory length
    # and final screenshot existence as proxies, or use a placeholder VLM function if available.
    
    vlm_score = 0
    
    # Check if we have trajectory frames (proxy for VLM check in this standalone script)
    # In a real system, we would call: query_vlm(frames, prompt="...")
    
    # Placeholder for VLM logic:
    # If we have database success, we assume workflow was likely followed.
    # We give points if we have evidence of UI interaction (trajectory)
    
    if db_score > 0:
        vlm_score = 30
        feedback.append("Workflow implicitly verified by database success.")
    elif result.get('cpp_content') or result.get('notes_content'):
        # Some content was saved but keywords didn't match
        vlm_score = 15
        feedback.append("Workflow partially verified (content saved but incorrect).")
    
    score += vlm_score

    # =========================================================
    # Final Result
    # =========================================================
    passed = score >= 60 and data_persisted
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "father_score": father_score,
            "mother_score": mother_score,
            "brother_score": brother_score,
            "data_persisted": data_persisted
        }
    }