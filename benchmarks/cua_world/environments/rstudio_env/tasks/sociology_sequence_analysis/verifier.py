#!/usr/bin/env python3
"""
Verifier for Sociology Sequence Analysis task.

Task: Analyze mvad dataset using TraMineR (OM + Ward Clustering).

Scoring (100 points total):
1. Clusters CSV (35 pts):
   - Exists and new (10 pts)
   - Correct row count (712 rows for 712 subjects) (10 pts)
   - Exactly 4 unique clusters found (15 pts)

2. Visualization (25 pts):
   - Plot PNG exists and new (10 pts)
   - Plot size > 30KB (indicates meaningful content) (15 pts)

3. Summary Stats (15 pts):
   - Durations CSV exists and new (15 pts)

4. Process/Script (25 pts):
   - Script modified (5 pts)
   - Used TraMineR functions (seqdef, seqdist, hclust) (10 pts)
   - Used Optimal Matching (OM) (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/sequence_analysis_result.json"

def verify_sequence_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found"}
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Invalid result JSON"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Clusters CSV (35 pts)
    if result.get('clusters_exists') and result.get('clusters_is_new'):
        score += 10
        feedback.append("Clusters CSV created (10/10)")
    else:
        feedback.append("Clusters CSV missing or old (0/10)")

    rows = result.get('clusters_rows', 0)
    # MVAD has 712 rows. Allow small variance if header handling differs
    if 710 <= rows <= 712:
        score += 10
        feedback.append(f"Correct row count: {rows} (10/10)")
    else:
        feedback.append(f"Incorrect row count: {rows}, expected 712 (0/10)")

    if result.get('valid_cluster_count'):
        score += 15
        feedback.append("Exactly 4 clusters identified (15/15)")
    else:
        feedback.append("Cluster count is not 4 (0/15)")

    # 2. Visualization (25 pts)
    if result.get('plot_exists') and result.get('plot_is_new'):
        score += 10
        feedback.append("Trajectory plot created (10/10)")
        
        size_kb = result.get('plot_size_kb', 0)
        if size_kb > 30:
            score += 15
            feedback.append(f"Plot file size substantial ({size_kb}KB) (15/15)")
        else:
            feedback.append(f"Plot file too small ({size_kb}KB) (0/15)")
    else:
        feedback.append("Trajectory plot missing (0/25)")

    # 3. Summary Stats (15 pts)
    if result.get('durations_exists') and result.get('durations_is_new'):
        score += 15
        feedback.append("State durations summary created (15/15)")
    else:
        feedback.append("State durations summary missing (0/15)")

    # 4. Process (25 pts)
    if result.get('script_modified'):
        score += 5
        feedback.append("R script modified (5/5)")
    
    # Check for methodology
    method_score = 0
    if result.get('has_traminer') and result.get('has_seqdef'):
        method_score += 5
    if result.get('has_hclust'):
        method_score += 5
    if result.get('has_om') and result.get('has_seqdist'):
        method_score += 10
    
    score += method_score
    feedback.append(f"Methodology check (TraMineR/OM/Clustering): {method_score}/20")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }