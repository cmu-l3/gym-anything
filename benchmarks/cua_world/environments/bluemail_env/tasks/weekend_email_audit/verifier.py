#!/usr/bin/env python3
"""
Verifier for weekend_email_audit task.

Scoring Breakdown (100 pts total):
1. Folder 'Weekend-Review' Created (10 pts)
2. Classification Accuracy (Precision & Recall) (40 pts)
   - Recall >= 80% (20 pts), >= 50% (10 pts)
   - Precision >= 80% (20 pts), >= 50% (10 pts)
3. Report File (25 pts)
   - Exists (10 pts)
   - Contains Count (5 pts)
   - Contains Subjects (10 pts)
4. HR Notification Email (25 pts)
   - Draft/Sent to correct address (15 pts)
   - Subject/Body relevant (10 pts)
"""

import json
import tempfile
import os
import sys

def verify_weekend_email_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from VM
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
    feedback = []

    # 1. Folder Creation (10 pts)
    if result.get('folder_created'):
        score += 10
        feedback.append("Folder 'Weekend-Review' created (+10)")
    else:
        feedback.append("Folder 'Weekend-Review' NOT found")

    # 2. Classification (40 pts)
    recall = result.get('recall', 0)
    precision = result.get('precision', 0)
    tp = result.get('true_positives', 0)
    gt = result.get('gt_weekend_count', 0)
    
    # Recall scoring
    if recall >= 0.8:
        score += 20
        feedback.append(f"High Recall ({recall:.0%}) (+20)")
    elif recall >= 0.5:
        score += 10
        feedback.append(f"Moderate Recall ({recall:.0%}) (+10)")
    else:
        feedback.append(f"Low Recall ({recall:.0%})")

    # Precision scoring
    # Only count precision if they actually moved something
    if result.get('true_positives', 0) + result.get('false_positives', 0) > 0:
        if precision >= 0.8:
            score += 20
            feedback.append(f"High Precision ({precision:.0%}) (+20)")
        elif precision >= 0.5:
            score += 10
            feedback.append(f"Moderate Precision ({precision:.0%}) (+10)")
        else:
            feedback.append(f"Low Precision ({precision:.0%})")
    else:
        feedback.append("No emails moved (Precision 0)")

    # 3. Report File (25 pts)
    if result.get('report_exists'):
        score += 10
        feedback.append("Report file exists (+10)")
        stats = result.get('report_stats', {})
        if stats.get('has_count'):
            score += 5
            feedback.append("Report contains numeric count (+5)")
        if stats.get('has_subjects'):
            score += 10
            feedback.append("Report contains email subjects (+10)")
    else:
        feedback.append("Report file missing")

    # 4. HR Email (25 pts)
    if result.get('draft_found'):
        score += 15
        feedback.append("HR draft found (+15)")
        details = result.get('draft_details', {})
        subj = details.get('subject', '').lower()
        body = details.get('body', '').lower()
        # Basic keyword check
        keywords = ['weekend', 'audit', 'review', 'compliance']
        if any(k in subj for k in keywords) or any(k in body for k in keywords):
            score += 10
            feedback.append("HR draft content relevant (+10)")
        else:
            feedback.append("HR draft content generic/irrelevant")
    else:
        feedback.append("HR draft NOT found")

    # Pass threshold
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }