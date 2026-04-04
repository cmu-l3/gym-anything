#!/usr/bin/env python3
"""
Verifier for nearest_neighbor_distance_matrix task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nearest_neighbor_distance_matrix(traj, env_info, task_info):
    """
    Verify the nearest neighbor analysis CSV output.
    
    Scoring Criteria:
    1. CSV file exists and is readable (10 pts)
    2. File was created during the task (5 pts)
    3. Valid CSV structure (3+ cols) (10 pts)
    4. Row count equals 17 (one per capital) (15 pts)
    5. All distances are positive (> 0) (10 pts)
       - Critical check for self-matching (dist=0) failure mode
    6. Distances are plausible (0.1 < d < 20) (10 pts)
    7. Ground Truth Verification (30 pts):
       - Denver <-> Cheyenne identified (10 pts)
       - Bismarck <-> Pierre identified (10 pts)
       - Lincoln <-> Topeka identified (10 pts)
    8. Project file saved (10 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    analysis = result.get("analysis", {})
    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if analysis.get("exists"):
        score += 10
        feedback_parts.append("CSV file found")
    else:
        feedback_parts.append("CSV file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Created during task (5 pts)
    if result.get("file_newly_created"):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates old file")
        
    # 3. Valid Structure (10 pts)
    if analysis.get("valid_csv") and analysis.get("has_3_cols"):
        score += 10
        feedback_parts.append("Valid CSV structure")
    else:
        feedback_parts.append("Invalid CSV structure or missing columns")
        
    # 4. Row Count (15 pts)
    row_count = analysis.get("row_count", 0)
    expected_rows = 17
    if row_count == expected_rows:
        score += 15
        feedback_parts.append(f"Correct row count ({row_count})")
    elif row_count > 0:
        # Partial credit
        score += 5
        feedback_parts.append(f"Incorrect row count: {row_count} (expected {expected_rows})")
    else:
        feedback_parts.append("CSV is empty")
        
    # 5. Positive Distances (10 pts)
    if analysis.get("all_distances_positive"):
        score += 10
        feedback_parts.append("All distances positive (>0)")
    else:
        feedback_parts.append("Some distances are 0 (Did you filter out self-matches?)")
        
    # 6. Plausible Distances (10 pts)
    if analysis.get("distances_plausible"):
        score += 10
        feedback_parts.append("Distances in plausible range")
    else:
        feedback_parts.append("Distances implausible (check CRS or units)")
        
    # 7. Ground Truth Pairs (30 pts)
    pairs_found = analysis.get("correct_pairs_count", 0)
    score += (pairs_found * 10)
    found_list = analysis.get("pairs_found", [])
    if pairs_found == 3:
        feedback_parts.append("All key neighbor pairs verified")
    elif pairs_found > 0:
        feedback_parts.append(f"Verified {pairs_found}/3 key neighbor pairs")
    else:
        feedback_parts.append("No expected neighbor pairs found")
        
    # 8. Project Saved (10 pts)
    if result.get("project_saved"):
        score += 10
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file not saved")
        
    passed = score >= 60 and analysis.get("exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }