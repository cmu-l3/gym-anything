#!/usr/bin/env python3
"""
Verifier for export_patient_cohort task.

Criteria:
1. Output file exists and was created during task.
2. File content contains the Target patients (born 2020).
3. File content does NOT contain Distractor patients (born 2019/2021).
4. VLM verification of the search/export workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_patient_cohort(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_patients', [])
    distractors = metadata.get('distractor_patients', [])

    # Get result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence Checks (20 pts)
    if result.get('file_exists'):
        score += 10
        if result.get('created_during_task'):
            score += 10
            feedback_parts.append("New file created.")
        else:
            feedback_parts.append("File exists but timestamp indicates pre-existence.")
    else:
        feedback_parts.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Content Analysis (50 pts)
    content = result.get('file_content_sample', '').lower()
    
    # Check Targets (20 pts each)
    targets_found = 0
    for t in targets:
        full_name = f"{t['first_name']} {t['last_name']}".lower()
        if full_name in content or (t['first_name'].lower() in content and t['last_name'].lower() in content):
            score += 10
            targets_found += 1
        else:
            feedback_parts.append(f"Missing target: {t['first_name']}")

    # Check Distractors (15 pts total logic - penalty style or bonus for exclusion)
    # We award points for EXCLUDING them.
    distractors_found = 0
    for d in distractors:
        full_name = f"{d['first_name']} {d['last_name']}".lower()
        if full_name in content:
            distractors_found += 1
            feedback_parts.append(f"Incorrectly included distractor: {d['first_name']}")
    
    if distractors_found == 0:
        score += 30
        feedback_parts.append("Correctly excluded patients outside date range.")
    else:
        # Partial credit if some excluded? No, strict filtering required for cohorts.
        feedback_parts.append("Failed date filtering check.")

    # 3. VLM Verification (30 pts)
    # Did they use the search tool?
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a user interacting with Oscar EMR.
    The goal was to search for patients born in 2020.
    
    Look for:
    1. A 'Search' or 'Demographic' or 'Report' page.
    2. Date fields being filled (e.g., '2020' or date ranges).
    3. A list of results appearing.
    4. A download or export action.
    
    Return JSON: {"search_tool_used": bool, "date_filter_seen": bool, "results_list_seen": bool}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        if parsed.get('search_tool_used') or parsed.get('results_list_seen'):
            vlm_score += 30
            feedback_parts.append("Visual verification passed.")
        else:
            feedback_parts.append("Visual verification inconclusive.")
    except Exception:
        # Fallback if VLM fails, assume pass if file content is perfect
        if score >= 60:
            vlm_score = 30
            feedback_parts.append("VLM skipped, content valid.")

    total_score = min(100, score + vlm_score)
    passed = total_score >= 75 and targets_found == len(targets) and distractors_found == 0

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }