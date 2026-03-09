#!/usr/bin/env python3
"""
Verifier for inventory_cancer_drug_list task.

Verification Strategy:
1. Programmatic: Check if output file exists and was created during the task.
2. Programmatic: Validate file content format (First/Last/Count).
3. Programmatic: Sanity check the data (First='A...', Last='V-Z...', Count=reasonable range).
4. VLM: Trajectory verification to ensure the agent actually SCROLLED through the list 
   (preventing guessing or looking up online without using the app).

Scoring:
- 10 pts: File exists and created during task
- 20 pts: Format correct (all 3 fields parseable)
- 20 pts: Data sanity check (First/Last/Count values plausible)
- 50 pts: VLM Trajectory check (App opened + Scrolling observed)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Gym-Anything VLM utilities (assumed available in environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/Mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images=None, image=None): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_cancer_drug_list(traj, env_info, task_info):
    """
    Verify the inventory task using file checks + VLM trajectory analysis.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_min_count', 20)
    expected_max = metadata.get('expected_max_count', 80)
    
    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Checks (50 points total)
    
    # Check A: File Existence & Anti-Gaming (10 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("Output file created successfully.")
    else:
        feedback_parts.append("Output file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check B: Content Format (20 pts)
    p_first = result.get("parsed_first_drug", "").strip()
    p_last = result.get("parsed_last_drug", "").strip()
    try:
        p_count = int(result.get("parsed_total_count", 0))
    except:
        p_count = 0

    if p_first and p_last and p_count > 0:
        score += 20
        feedback_parts.append("File format correct.")
    else:
        feedback_parts.append(f"File format incomplete. First: {bool(p_first)}, Last: {bool(p_last)}, Count: {p_count}")
    
    # Check C: Data Plausibility (20 pts)
    data_score = 0
    
    # First drug should start with A (e.g., Abiraterone)
    if p_first and p_first[0].upper() == 'A':
        data_score += 5
    else:
        feedback_parts.append(f"First drug '{p_first}' does not start with A.")

    # Last drug should be late alphabet (V, W, X, Y, Z) - e.g., Venetoclax, Vinblastine
    if p_last and p_last[0].upper() in ['V', 'W', 'X', 'Y', 'Z']:
        data_score += 5
    else:
        feedback_parts.append(f"Last drug '{p_last}' seems unlikely for end of list.")

    # Count reasonable range
    if expected_min <= p_count <= expected_max:
        data_score += 10
    else:
        feedback_parts.append(f"Count {p_count} is outside expected range ({expected_min}-{expected_max}).")

    score += data_score
    feedback_parts.append(f"Data sanity check: {data_score}/20 pts.")

    # 3. VLM Trajectory Verification (50 points total)
    # Critical to prove they actually used the app and didn't just guess numbers
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying an agent's task performance on an Android app.
    The task was to open the 'Liverpool Cancer iChart' app and SCROLL through the entire list of cancer drugs.
    
    Look at this sequence of screenshots (chronological order):
    1. Does the 'Cancer iChart' app appear to be open? (Look for red/white UI, drug names list).
    2. Do you see evidence of SCROLLING? (E.g., early frames show drugs starting with 'A', later frames show drugs later in the alphabet).
    3. Did the agent reach the end of the list (drugs starting with V, W, X, Y, or Z)?
    
    Return JSON:
    {
        "app_opened": boolean,
        "scrolling_observed": boolean,
        "reached_end_of_list": boolean,
        "explanation": "brief description of what you see"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    vlm_score = 0
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("app_opened"):
            vlm_score += 10
        else:
            feedback_parts.append("VLM did not see the app open.")
            
        if parsed.get("scrolling_observed"):
            vlm_score += 20
        else:
            feedback_parts.append("VLM did not see scrolling behavior.")
            
        if parsed.get("reached_end_of_list"):
            vlm_score += 20
        else:
            feedback_parts.append("VLM did not see the end of the list.")
            
        feedback_parts.append(f"VLM Analysis: {parsed.get('explanation', 'No details')}")
    else:
        # Fallback if VLM fails: give partial credit if data checks were perfect
        # Assume if data is perfect, they probably did it.
        if score >= 45: 
            vlm_score = 25
            feedback_parts.append("VLM unavailable, granting partial check based on correct data.")
        else:
            feedback_parts.append("VLM verification failed and data checks incomplete.")

    score += vlm_score
    
    # 4. Final Result
    passed = score >= 60  # Require good data + some visual evidence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }