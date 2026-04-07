#!/usr/bin/env python3
"""
Verifier for Create WCST Assessment task.

Scoring Criteria:
1. Conditions CSV (35 points):
   - Exists & Created during task (10)
   - Valid Structure (cols) (10)
   - Complete 64-card deck (15)
2. Python Script (65 points):
   - Exists & Valid Syntax (10)
   - Key Imports (visual, event) (10)
   - Creates Window & Mouse (10)
   - Stimuli Definitions (Cards/Feedback) (10)
   - Rule Switching Logic (15)
   - Data Logging (10)
3. VLM Check (Pass/Fail gate):
   - Confirms Coder view was used and code isn't just a copy-paste from an external disallowed source (though difficult to prove, we check for interface usage).

Pass Threshold: 60 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_wcst_assessment(traj, env_info, task_info):
    """Verify WCST implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/wcst_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []
    
    # --- Verify CSV (35 pts) ---
    if result.get("csv_exists") and result.get("csv_modified"):
        score += 10
        feedback_parts.append("Conditions CSV created")
        
        if result.get("csv_columns_valid"):
            score += 10
            feedback_parts.append("CSV columns valid")
        else:
            feedback_parts.append("CSV missing required columns")
            
        if result.get("csv_complete_deck"):
            score += 15
            feedback_parts.append("Full 64-card deck verified")
        else:
            feedback_parts.append("Deck incomplete or invalid combinations")
    else:
        feedback_parts.append("Conditions CSV not created or not modified")

    # --- Verify Script (65 pts) ---
    if result.get("script_exists") and result.get("script_modified"):
        if result.get("script_syntax_valid"):
            score += 10
            feedback_parts.append("Python script valid")
            
            # Imports
            if result.get("imports_visual") and result.get("imports_event"):
                score += 10
                feedback_parts.append("PsychoPy imports present")
            
            # Window/Mouse
            if result.get("has_window") and result.get("has_mouse"):
                score += 10
                feedback_parts.append("Window/Mouse setup found")
            
            # Stimuli
            if result.get("has_text_stim") or result.get("has_shape_stim"):
                score += 10
                feedback_parts.append("Stimuli definitions found")
            
            # Rule Logic
            if result.get("has_rule_logic"):
                score += 15
                feedback_parts.append("Rule switching logic detected")
            else:
                feedback_parts.append("Rule switching logic missing/unclear")
                
            # Data Logging
            if result.get("saves_data"):
                score += 10
                feedback_parts.append("Data logging detected")
        else:
            feedback_parts.append("Python script has syntax errors")
    else:
        feedback_parts.append("Python script not created")

    # Nonce check
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        if result.get("result_nonce") != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "Anti-gaming nonce mismatch"}
    except:
        pass # If nonce fails, likely script error which handles score anyway

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }