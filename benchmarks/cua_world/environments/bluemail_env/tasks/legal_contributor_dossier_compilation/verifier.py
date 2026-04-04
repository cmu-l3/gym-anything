#!/usr/bin/env python3
"""
Verifier for legal_contributor_dossier_compilation.

Scoring Criteria:
1. Folder Structure (20 pts): 'Direct' and 'Mentions' folders exist.
2. Direct Emails Isolated (25 pts): Emails in 'Direct' folder are actually from target.
3. Mentions Emails Isolated (20 pts): Emails in 'Mentions' folder contain keywords.
4. Negative Constraint (15 pts): 'Mentions' folder MUST NOT contain emails from target.
5. Report Drafted (10 pts): Email to legal-audit exists.
6. Report Accuracy (10 pts): Reported counts match actual folder counts.

Total: 100
Pass Threshold: 70
"""

import json
import os
import tempfile
import re

def verify_legal_dossier(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    stats = result.get("stats", {})
    score = 0
    feedback = []

    # 1. Folder Structure (20 pts)
    if result.get("direct_folder_found") and result.get("mentions_folder_found"):
        score += 20
        feedback.append("Folder structure created correctly (20/20)")
    elif result.get("direct_folder_found") or result.get("mentions_folder_found"):
        score += 10
        feedback.append("Partial folder structure found (10/20)")
    else:
        feedback.append("No required folders found (0/20)")

    # 2. Direct Emails Integrity (25 pts)
    # Require at least 2 emails, and high precision
    direct_total = stats.get("direct_count", 0)
    direct_correct = stats.get("direct_correct_sender", 0)
    
    if direct_total >= 2:
        precision = direct_correct / direct_total
        if precision >= 0.9:
            score += 25
            feedback.append(f"Direct folder contents accurate: {direct_correct}/{direct_total} (25/25)")
        elif precision >= 0.5:
            score += 10
            feedback.append(f"Direct folder contents mixed accuracy: {direct_correct}/{direct_total} (10/25)")
        else:
            feedback.append(f"Direct folder contents mostly wrong: {direct_correct}/{direct_total} (0/25)")
    else:
        feedback.append("Direct folder empty or insufficient data (0/25)")

    # 3. Mentions Emails Integrity (20 pts)
    mentions_total = stats.get("mentions_count", 0)
    mentions_correct = stats.get("mentions_contain_keyword", 0)
    
    if mentions_total >= 2:
        precision = mentions_correct / mentions_total
        if precision >= 0.7: # Lower threshold as keyword matching can be fuzzy
            score += 20
            feedback.append(f"Mentions folder contents relevant: {mentions_correct}/{mentions_total} (20/20)")
        elif precision >= 0.4:
            score += 10
            feedback.append(f"Mentions folder contents partially relevant (10/20)")
        else:
            feedback.append("Mentions folder contents irrelevant (0/20)")
    else:
        feedback.append("Mentions folder empty or insufficient data (0/20)")

    # 4. Negative Constraint (15 pts) - CRITICAL
    # Mentions folder must NOT contain emails from the target
    mentions_from_target = stats.get("mentions_from_target", 0)
    if mentions_total > 0:
        if mentions_from_target == 0:
            score += 15
            feedback.append("Negative Constraint Met: No target emails in Mentions folder (15/15)")
        else:
            feedback.append(f"Negative Constraint FAILED: Found {mentions_from_target} emails from target in Mentions folder (0/15)")
            # This is a major failure for a legal discovery task
    else:
        feedback.append("Skipping negative constraint (folder empty) (0/15)")

    # 5. Report Drafted (10 pts)
    reports = result.get("report_emails", [])
    report_found = False
    report_body = ""
    if reports:
        score += 10
        feedback.append("Report email found (10/10)")
        report_found = True
        report_body = reports[0].get("body", "")
    else:
        feedback.append("No report email found (0/10)")

    # 6. Report Accuracy (10 pts)
    # Extract numbers from body and compare to actuals
    if report_found:
        # Simple regex to find numbers
        numbers = [int(n) for n in re.findall(r'\b\d+\b', report_body)]
        
        # We look for the actual counts in the numbers found
        # This is a loose check: if the actual numbers appear in the email, we give credit
        matches_direct = direct_total in numbers
        matches_mentions = mentions_total in numbers
        
        if matches_direct and matches_mentions:
            score += 10
            feedback.append("Reported counts match actuals (10/10)")
        elif matches_direct or matches_mentions:
            score += 5
            feedback.append("Reported counts partially match (5/10)")
        else:
            feedback.append(f"Reported counts do not match actuals (Found {numbers} vs {direct_total}/{mentions_total}) (0/10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }