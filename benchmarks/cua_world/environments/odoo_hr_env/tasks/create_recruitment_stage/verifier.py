#!/usr/bin/env python3
"""
Verifier for create_recruitment_stage task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_recruitment_stage(traj, env_info, task_info):
    """
    Verifies that the recruitment stage was created correctly in Odoo.
    
    Scoring Criteria (Total 100):
    1. Stage exists with partial name match (30 pts)
    2. Stage name is exactly "Technical Assessment" (10 pts)
    3. Requirements text contains "technical evaluation" (20 pts)
    4. Sequence is correct (After First Interview, Before Second Interview) (30 pts)
    5. Total stage count increased by exactly 1 (10 pts)
    """
    
    # 1. Retrieve result data from the container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Check for critical errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback = []
    
    # 3. Score Criteria
    
    # Criterion 1: Stage Exists (30 pts)
    if result.get("stage_found"):
        score += 30
        feedback.append("Stage 'Technical Assessment' created.")
    else:
        feedback.append("Stage 'Technical Assessment' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Exact Name Match (10 pts)
    if result.get("name_correct"):
        score += 10
    else:
        feedback.append("Stage name is not an exact match (check capitalization).")

    # Criterion 3: Description Content (20 pts)
    if result.get("description_correct"):
        score += 20
        feedback.append("Requirements description correct.")
    else:
        actual = result.get("details", {}).get("actual_requirements", "None")
        feedback.append(f"Requirements text missing 'technical evaluation'. Found: '{actual}'")

    # Criterion 4: Sequence/Ordering (30 pts)
    if result.get("sequence_correct"):
        score += 30
        feedback.append("Pipeline positioning correct.")
    else:
        seqs = result.get("details", {}).get("sequences", {})
        feedback.append(f"Pipeline positioning incorrect. (First Interview: {seqs.get('First Interview')}, New Stage: {seqs.get('Technical Assessment')}, Second Interview: {seqs.get('Second Interview')})")

    # Criterion 5: Count check (10 pts) - Anti-gaming
    if result.get("count_increased"):
        score += 10
    else:
        counts = result.get("details", {}).get("counts", {})
        feedback.append(f"Stage count did not increase by exactly 1 (Initial: {counts.get('initial')}, Final: {counts.get('final')}). Did you overwrite an existing stage?")

    # 4. Final Determination
    # Pass if score >= 50 (implied: Stage exists + at least 20 points from other criteria)
    passed = score >= 50
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result.get("details")
    }