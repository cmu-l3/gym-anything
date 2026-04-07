#!/usr/bin/env python3
"""
Verifier for consolidate_issue_categories task.

Criteria:
1. 'Plumbing' category deleted (20 pts)
2. 'Electrical' category deleted (20 pts)
3. 'MEP' category exists (10 pts)
4. Issues originally in Plumbing/Electrical are now in MEP (40 pts)
5. No data loss (issues still exist) (10 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_issue_categories(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for script errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Data extraction
    final_categories = result.get("final_categories", [])
    final_cat_names = [c["name"] for c in final_categories]
    issue_states = result.get("issue_states", [])
    ground_truth = result.get("ground_truth", {})

    # Criterion 1: 'Plumbing' category deleted (20 pts)
    if "Plumbing" not in final_cat_names:
        score += 20
        feedback_parts.append("Plumbing category deleted")
    else:
        feedback_parts.append("Plumbing category still exists")

    # Criterion 2: 'Electrical' category deleted (20 pts)
    if "Electrical" not in final_cat_names:
        score += 20
        feedback_parts.append("Electrical category deleted")
    else:
        feedback_parts.append("Electrical category still exists")

    # Criterion 3: 'MEP' category exists (10 pts)
    mep_exists = False
    for cat in final_categories:
        if cat["name"] == "MEP":
            mep_exists = True
            # Optional: Check if it's the SAME MEP category ID if we wanted to be strict
            # but usually preserving the ID is the default behavior if they didn't delete MEP.
            break
    
    if mep_exists:
        score += 10
        feedback_parts.append("MEP category preserved")
    else:
        feedback_parts.append("MEP category missing")

    # Criterion 4 & 5: Issues reassigned and preserved (50 pts total)
    total_issues = len(issue_states)
    issues_reassigned = 0
    issues_preserved = 0

    if total_issues == 0:
        return {"passed": False, "score": 0, "feedback": "Setup error: No issues tracked"}

    for issue in issue_states:
        if issue.get("exists"):
            issues_preserved += 1
            cat_name = issue.get("category_name")
            if cat_name == "MEP":
                issues_reassigned += 1
    
    # Score preservation (10 pts)
    if issues_preserved == total_issues:
        score += 10
    else:
        feedback_parts.append(f"Data Loss: {total_issues - issues_preserved} issues deleted")

    # Score reassignment (40 pts)
    # 40 points distributed among issues
    points_per_issue = 40 / total_issues
    score += int(issues_reassigned * points_per_issue)
    
    if issues_reassigned == total_issues:
        feedback_parts.append("All issues correctly reassigned to MEP")
    else:
        feedback_parts.append(f"Only {issues_reassigned}/{total_issues} issues reassigned to MEP")

    passed = (score >= 95) # Require near perfection for data migration tasks

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }