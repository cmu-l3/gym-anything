#!/usr/bin/env python3
"""
Verifier for select_safe_antidepressant_vandetanib task.

Criteria:
1. File Creation: Report file exists and was created during the task.
2. Risk Identification: Citalopram identified as Red/Orange (High Risk).
3. Safer Alternatives: Sertraline/Mirtazapine identified as Yellow/Green.
4. Recommendation: A safe drug is recommended (Sertraline or Mirtazapine).
5. Workflow: VLM trajectory confirms navigation to Vandetanib interactions.
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

# Import VLM utils (mock import pattern matching framework)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for standalone testing
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(images, prompt): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safe_antidepressant(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON produced by export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Scoring Variables
    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # CHECK 1: File Existence & Anti-Gaming (20 pts)
    # ------------------------------------------------------------------
    file_exists = result_data.get("file_exists", False)
    file_content = result_data.get("file_content", "")
    task_start = int(result_data.get("task_start_timestamp", 0))
    file_mtime = int(result_data.get("file_mtime", 0))

    if file_exists:
        if file_mtime > task_start:
            score += 20
            feedback.append("Report file created successfully during task.")
        else:
            feedback.append("Report file exists but timestamp predates task (Anti-gaming fail).")
    else:
        feedback.append("Report file not found.")

    # ------------------------------------------------------------------
    # CHECK 2: Content Analysis (50 pts)
    # ------------------------------------------------------------------
    # Expected:
    # Citalopram: Red/Orange
    # Sertraline: Yellow/Green
    # Mirtazapine: Yellow/Green
    # Recommendation: Sertraline OR Mirtazapine
    
    content_lower = file_content.lower()
    
    # Helper regex to find color associated with drug
    def get_drug_color(drug_name, text):
        # Matches "Drug: Color" or "Drug - Color" or "Drug ... Color"
        pattern = f"{drug_name}.*?(red|orange|yellow|green|grey)"
        match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
        return match.group(1) if match else None

    # Check Citalopram (Risk) - 15 pts
    cit_color = get_drug_color("citalopram", content_lower)
    if cit_color in ["red", "orange"]:
        score += 15
        feedback.append(f"Correctly identified Citalopram risk ({cit_color}).")
    elif cit_color:
        feedback.append(f"Incorrect color for Citalopram: {cit_color} (Expected Red/Orange).")
    else:
        feedback.append("Citalopram entry missing or unreadable.")

    # Check Comparators (Safety) - 15 pts
    sert_color = get_drug_color("sertraline", content_lower)
    mirt_color = get_drug_color("mirtazapine", content_lower)
    
    safe_drugs_correct = 0
    if sert_color in ["yellow", "green", "grey"]: safe_drugs_correct += 1
    if mirt_color in ["yellow", "green", "grey"]: safe_drugs_correct += 1
    
    if safe_drugs_correct == 2:
        score += 15
        feedback.append("Correctly identified safety of Sertraline and Mirtazapine.")
    elif safe_drugs_correct == 1:
        score += 7
        feedback.append("Identified safety of one alternative drug.")
    else:
        feedback.append("Failed to correctly identify alternative drug safety.")

    # Check Recommendation - 20 pts
    # Look for "Recommendation: ..." line
    rec_match = re.search(r"recommendation:?\s*(.*)", content_lower)
    if rec_match:
        rec_text = rec_match.group(1)
        if "citalopram" in rec_text and "not" not in rec_text:
             feedback.append("Dangerous recommendation: Suggested Citalopram.")
        elif "sertraline" in rec_text or "mirtazapine" in rec_text:
            score += 20
            feedback.append("Recommendation is safe (Sertraline/Mirtazapine).")
        else:
            feedback.append("Recommendation unclear.")
    else:
        feedback.append("Recommendation section missing.")

    # ------------------------------------------------------------------
    # CHECK 3: VLM Workflow Verification (30 pts)
    # ------------------------------------------------------------------
    # We want to see evidence that the agent actually checked "Vandetanib"
    
    frames = sample_trajectory_frames(traj, n=5)
    
    if not frames:
        feedback.append("No trajectory frames available for VLM check.")
    else:
        vlm_prompt = """
        Analyze these screenshots from the Liverpool Cancer iChart app.
        The user should be checking drug interactions for 'Vandetanib'.
        
        Look for:
        1. The text 'Vandetanib' (likely selected as the Cancer Drug).
        2. A list of Comedications including 'Citalopram', 'Sertraline', or 'Mirtazapine'.
        3. Traffic light colors (Red, Orange, Yellow, Green) next to drugs.
        
        Answer JSON:
        {
            "vandetanib_visible": true/false,
            "antidepressants_visible": true/false,
            "colors_visible": true/false
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("vandetanib_visible"):
            vlm_score += 10
            feedback.append("VLM: Confirmed Vandetanib selection.")
        if parsed.get("antidepressants_visible"):
            vlm_score += 10
            feedback.append("VLM: Confirmed antidepressant list viewing.")
        if parsed.get("colors_visible"):
            vlm_score += 10
            feedback.append("VLM: Confirmed interaction colors visible.")
            
        score += vlm_score

    # Final Result
    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }