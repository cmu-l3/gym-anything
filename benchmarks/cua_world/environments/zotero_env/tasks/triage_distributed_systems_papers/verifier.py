#!/usr/bin/env python3
"""
Verifier for triage_distributed_systems_papers task.

Scoring Breakdown:
- Collections 'Classic Systems' and 'Modern Systems' exist: 10 pts
- Classic Papers (<= 2004) correctly filed: 40 pts
- Modern Papers (>= 2005) correctly filed: 40 pts
- Clean Organization (no duplicates/unassigned): 10 pts

Pass Threshold: 75 pts
"""

import json
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def parse_year(date_str):
    """Extract 4-digit year from date string."""
    if not date_str:
        return 0
    # Look for 4 digits (e.g. "1974", "May 2005", "2020-01-01")
    match = re.search(r'\d{4}', str(date_str))
    if match:
        return int(match.group(0))
    return 0

def verify_triage_distributed_systems_papers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Check Collections Existence (10 pts)
    cols = result.get('collections', [])
    col_names = [c['name'] for c in cols]
    
    has_classic = "Classic Systems" in col_names
    has_modern = "Modern Systems" in col_names
    
    if has_classic and has_modern:
        score += 10
        feedback_parts.append("Collections created")
    else:
        feedback_parts.append(f"Missing collections (Found: {col_names})")
        # If collections don't exist, we can't really score placement
        if not (has_classic or has_modern):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Failed to create required collections 'Classic Systems' and 'Modern Systems'."
            }

    # 2. Evaluate Items (80 pts total)
    items = result.get('items', [])
    if not items:
        return {"passed": False, "score": score, "feedback": "No items found in library"}

    # Logic counters
    correct_classic = 0
    correct_modern = 0
    total_classic_papers = 0
    total_modern_papers = 0
    misfiled_errors = 0
    unassigned_errors = 0
    duplicate_errors = 0

    for item in items:
        year = parse_year(item.get('date_str'))
        if year == 0:
            continue # Skip items without valid year if any (shouldn't happen with seed data)

        item_cols = item.get('collections', [])
        in_classic = "Classic Systems" in item_cols
        in_modern = "Modern Systems" in item_cols

        # Ground Truth Logic
        is_classic_paper = year <= 2004
        is_modern_paper = year >= 2005

        # Check correctness
        if is_classic_paper:
            total_classic_papers += 1
            if in_classic and not in_modern:
                correct_classic += 1
            else:
                if in_modern: misfiled_errors += 1
                if not in_classic and not in_modern: unassigned_errors += 1
                if in_classic and in_modern: duplicate_errors += 1
        
        elif is_modern_paper:
            total_modern_papers += 1
            if in_modern and not in_classic:
                correct_modern += 1
            else:
                if in_classic: misfiled_errors += 1
                if not in_classic and not in_modern: unassigned_errors += 1
                if in_classic and in_modern: duplicate_errors += 1

    # Calculate Scores
    # Classic Papers (40 pts)
    if total_classic_papers > 0:
        classic_pts = (correct_classic / total_classic_papers) * 40
        score += classic_pts
        feedback_parts.append(f"Classic: {correct_classic}/{total_classic_papers}")

    # Modern Papers (40 pts)
    if total_modern_papers > 0:
        modern_pts = (correct_modern / total_modern_papers) * 40
        score += modern_pts
        feedback_parts.append(f"Modern: {correct_modern}/{total_modern_papers}")

    # 3. Clean Organization Bonus (10 pts)
    # Only awarded if core task is mostly done and no messiness
    total_errors = misfiled_errors + unassigned_errors + duplicate_errors
    
    if total_errors == 0 and score >= 80:
        score += 10
        feedback_parts.append("Perfect organization")
    elif total_errors > 0:
        feedback_parts.append(f"Errors: {misfiled_errors} misfiled, {unassigned_errors} unassigned")

    score = int(score)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "classic_stats": f"{correct_classic}/{total_classic_papers}",
            "modern_stats": f"{correct_modern}/{total_modern_papers}",
            "errors": total_errors
        }
    }