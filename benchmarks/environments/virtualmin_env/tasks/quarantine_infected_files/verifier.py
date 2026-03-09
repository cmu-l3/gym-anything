#!/usr/bin/env python3
"""
Verifier for quarantine_infected_files task.

SCORING CRITERIA:
1. Infected File 1 (index.php) in quarantine AND not in docroot (25 pts)
2. Infected File 2 (functions.php) in quarantine AND not in docroot (25 pts)
3. Infected File 3 (class-wp-http.php) in quarantine AND not in docroot (25 pts)
4. Decoy file (class.akismet.php) remains in docroot (15 pts)
5. Precision bonus: No extra files in quarantine (10 pts)
   - If total_quarantined_count > 3, this bonus is lost.

VLM VERIFICATION:
- Uses trajectory frames to verify the agent used search tools (grep/find/UI search)
  rather than just "knowing" the file locations (anti-gaming).
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quarantine_infected_files(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # ----------------------------------------------------------------
    # PROGRAMMATIC CHECKS
    # ----------------------------------------------------------------
    
    # Check File 1 (index.php)
    f1 = result.get('file_1', {})
    if f1.get('in_quarantine') and not f1.get('in_original'):
        score += 25
        feedback.append("File 1 (index.php) correctly quarantined.")
    elif f1.get('in_quarantine'):
        score += 15
        feedback.append("File 1 copied to quarantine but original remains (partial credit).")
    else:
        feedback.append("File 1 missed.")

    # Check File 2 (functions.php)
    f2 = result.get('file_2', {})
    if f2.get('in_quarantine') and not f2.get('in_original'):
        score += 25
        feedback.append("File 2 (functions.php) correctly quarantined.")
    elif f2.get('in_quarantine'):
        score += 15
        feedback.append("File 2 copied to quarantine but original remains (partial credit).")
    else:
        feedback.append("File 2 missed.")

    # Check File 3 (class-wp-http.php)
    f3 = result.get('file_3', {})
    if f3.get('in_quarantine') and not f3.get('in_original'):
        score += 25
        feedback.append("File 3 (class-wp-http.php) correctly quarantined.")
    elif f3.get('in_quarantine'):
        score += 15
        feedback.append("File 3 copied to quarantine but original remains (partial credit).")
    else:
        feedback.append("File 3 missed.")

    # Check Decoy (Precision)
    decoy = result.get('decoy', {})
    if decoy.get('in_original') and not decoy.get('in_quarantine'):
        score += 15
        feedback.append("Decoy file correctly preserved.")
    else:
        feedback.append("Decoy file was moved or deleted! (False Positive).")

    # Check for Collateral Damage (Extra files)
    total_quarantined = result.get('total_quarantined_count', 0)
    expected_quarantined = 0
    if f1.get('in_quarantine'): expected_quarantined += 1
    if f2.get('in_quarantine'): expected_quarantined += 1
    if f3.get('in_quarantine'): expected_quarantined += 1
    
    if total_quarantined == expected_quarantined and expected_quarantined > 0:
        score += 10
        feedback.append("Precision bonus: Exactly correct number of files moved.")
    elif total_quarantined > expected_quarantined:
        feedback.append(f"Precision penalty: {total_quarantined} files in quarantine (expected {expected_quarantined}).")

    # ----------------------------------------------------------------
    # VLM VERIFICATION (Process Check)
    # ----------------------------------------------------------------
    # We want to verify the agent actually searched for the string.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        I am analyzing an agent's attempt to clean malware from a server.
        The agent should be searching for files containing the string "eval(base64_decode".
        
        Look at these screenshots. Do you see evidence of:
        1. A file search operation (grep command, 'find' command, or Virtualmin File Manager search)?
        2. The string "eval(base64_decode" being typed or used as a search term?
        3. A list of search results showing PHP files?
        
        Return JSON: {"search_performed": boolean, "search_term_visible": boolean}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        vlm_data = vlm_res.get('parsed', {})
        
        if not vlm_data.get('search_performed', False) and not vlm_data.get('search_term_visible', False):
            # Penalize if score is high but no work shown (suspicious)
            if score > 50:
                feedback.append("WARNING: No visual evidence of search process found.")
                # We don't deduct hard points to avoid false negatives on VLM, 
                # but we note it in feedback.
    
    # ----------------------------------------------------------------
    # FINAL SCORING
    # ----------------------------------------------------------------
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }