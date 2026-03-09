#!/usr/bin/env python3
"""
Verifier for Regorafenib Co-medication Enumeration Task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enumeration(traj, env_info, task_info):
    """
    Verifies that the agent enumerated the co-medication categories for Regorafenib.
    
    Criteria:
    1. Report file exists and was created during task.
    2. Report contains header identifying "Regorafenib".
    3. Report lists a sufficient number of valid therapeutic categories (>10).
    4. Report contains a total count.
    5. VLM: Trajectory shows navigation to Regorafenib and scrolling of the list.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subset = set(k.lower() for k in metadata.get('expected_categories_subset', []))
    min_categories = metadata.get('min_categories', 10)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. File Existence & Anti-Gaming (20 pts)
    if not result_data.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result_data.get('file_created_during_task', False):
        feedback.append("File timestamp check failed (file older than task).")
        # specific penalty or fail? usually fail for anti-gaming, but let's just zero this section
    else:
        score += 20
        feedback.append("Report file created during task.")

    # 3. Content Analysis (40 pts)
    content = result_data.get('report_content_escaped', '').replace('\\n', '\n')
    lines = [L.strip() for L in content.split('\n') if L.strip()]
    
    # Check Header
    if any("regorafenib" in line.lower() for line in lines[:5]):
        score += 10
        feedback.append("Correct drug identified in header.")
    else:
        feedback.append("Header missing 'Regorafenib'.")

    # Check Count
    count_line = next((line for line in lines if "total" in line.lower() and any(c.isdigit() for c in line)), None)
    if count_line:
        score += 5
        feedback.append("Total count reported.")
    else:
        feedback.append("Total count line missing.")

    # Check Categories
    # Filter out header/count lines to find category list
    category_candidates = [
        line for line in lines 
        if "regorafenib" not in line.lower() 
        and "total" not in line.lower() 
        and "cancer drug" not in line.lower()
    ]
    
    # Validate against expected categories (fuzzy check)
    valid_found = 0
    found_list = []
    
    # Common categories in iChart
    known_categories = [
        "analgesics", "anticoagulants", "anticonvulsants", "antidepressants", 
        "antidiabetics", "antiemetics", "antifungals", "antihistamines", 
        "antimalarials", "antipsychotics", "antivirals", "anxiolytics", 
        "cardiovascular", "contraceptives", "corticosteroids", "gastrointestinal", 
        "herbals", "hormonal", "immunosuppressants", "lipid", "respiratory", "sedatives"
    ]
    
    for line in category_candidates:
        # Check if line matches a known category partially
        clean_line = line.lower()
        if any(kc in clean_line for kc in known_categories):
            valid_found += 1
            found_list.append(line)
    
    if valid_found >= min_categories:
        score += 25
        feedback.append(f"List contains {valid_found} valid therapeutic categories.")
    elif valid_found >= 5:
        score += 10
        feedback.append(f"List contains only {valid_found} valid categories (expected {min_categories}).")
    else:
        feedback.append(f"List content unclear or insufficient (found {valid_found} valid entries).")

    # 4. VLM Trajectory Verification (40 pts)
    # We need to ensure the agent actually scrolled the list
    from gym_anything.vlm import query_vlm
    
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    The goal was to select 'Regorafenib' and scroll through the 'Co-medications' list (therapeutic categories).
    
    Look at the sequence of screenshots.
    1. Is the 'Regorafenib' drug page or selection visible?
    2. Is a list of medical categories visible (e.g., Analgesics, Anticoagulants)?
    3. Does the agent SCROLL the list? (Do the visible items change across frames?)
    
    Return JSON:
    {
        "regorafenib_seen": true/false,
        "list_visible": true/false,
        "scrolling_observed": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("regorafenib_seen"): vlm_score += 10
        if parsed.get("list_visible"): vlm_score += 10
        if parsed.get("scrolling_observed"): vlm_score += 20
        
        score += vlm_score
        feedback.append(f"VLM verification: {parsed.get('reasoning')}")
    else:
        feedback.append("VLM verification failed to execute.")

    passed = (score >= 60) and (valid_found >= 5) and result_data.get('file_created_during_task', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }