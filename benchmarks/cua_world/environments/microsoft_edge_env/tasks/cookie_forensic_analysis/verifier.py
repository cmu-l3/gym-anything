#!/usr/bin/env python3
"""
Verifier for cookie_forensic_analysis task.

Criteria:
1. Report file exists and modified after task start.
2. Browser history shows visits to CNN, Weather, and Wikipedia.
3. Cookie database shows activity (proof of page loads).
4. Report content analysis:
   - Mentions all 3 domains.
   - Contains numeric counts.
   - Identifies third-party trackers (e.g., doubleclick).
   - Contains comparative analysis words.
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def verify_cookie_forensic_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from export script
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env("/tmp/cookie_forensic_analysis_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}. Did export_result.sh run?"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # Extract data
    report = result.get("report", {})
    history = result.get("history_visits", {})
    cookies = result.get("cookie_stats", {})
    content = report.get("content", "").lower()

    # --- Criterion 1: Report Existence & Freshness (10 pts) ---
    if report.get("exists") and report.get("modified_after_start"):
        score += 10
        feedback.append("Report file created/modified after task start (10/10)")
    elif report.get("exists"):
        score += 0
        feedback.append("Report file exists but was NOT modified during task (0/10)")
    else:
        feedback.append("Report file not found (0/10)")

    # --- Criterion 2: Site Visits (24 pts, 8 each) ---
    for site, visited in history.items():
        if visited:
            score += 8
            feedback.append(f"Visited {site} (8/8)")
        else:
            feedback.append(f"Did not visit {site} (0/8)")

    # --- Criterion 3: Cookie Database Activity (10 pts) ---
    # Proof that pages actually loaded and deposited data
    if cookies.get("recent_count", 0) > 5:
        score += 10
        feedback.append("Cookie database shows new entries (10/10)")
    else:
        feedback.append("No significant cookie activity detected (0/10)")

    # --- Criterion 4: Report Content Analysis ---
    
    # 4a. Mentions domains (15 pts)
    domains_mentioned = 0
    if "cnn" in content: domains_mentioned += 1
    if "weather" in content: domains_mentioned += 1
    if "wikipedia" in content: domains_mentioned += 1
    
    if domains_mentioned == 3:
        score += 15
        feedback.append("Report mentions all 3 target sites (15/15)")
    else:
        pts = domains_mentioned * 5
        score += pts
        feedback.append(f"Report mentions {domains_mentioned}/3 target sites ({pts}/15)")

    # 4b. Numeric counts (12 pts)
    # Looking for patterns like "15 cookies", "count: 20", "found 5"
    if re.search(r'\d+\s*(cookies|trackers|items|count)', content) or re.search(r'(count|total).{0,10}\d+', content):
        score += 12
        feedback.append("Report contains numeric cookie/tracker counts (12/12)")
    else:
        feedback.append("Report missing specific numeric counts (0/12)")

    # 4c. Identifies third-party trackers (17 pts)
    known_trackers = task_info.get("metadata", {}).get("known_trackers", [])
    found_trackers = [t for t in known_trackers if t in content]
    
    if len(found_trackers) >= 2:
        score += 17
        feedback.append(f"Identified known trackers: {', '.join(found_trackers[:3])} (17/17)")
    elif len(found_trackers) == 1:
        score += 8
        feedback.append(f"Identified only one known tracker: {found_trackers[0]} (8/17)")
    else:
        feedback.append("No specific known tracker domains (e.g. doubleclick) identified in report (0/17)")

    # 4d. Substantive content (7 pts)
    if report.get("size", 0) > 800:
        score += 7
        feedback.append("Report is substantive >800 bytes (7/7)")
    elif report.get("size", 0) > 200:
        score += 3
        feedback.append("Report is somewhat short (3/7)")
    else:
        feedback.append("Report is too short/empty (0/7)")

    # 4e. Comparative analysis (5 pts)
    comparatives = ["more", "less", "most", "least", "fewer", "highest", "lowest", "heaviest", "lightest"]
    if any(w in content for w in comparatives):
        score += 5
        feedback.append("Report contains comparative analysis language (5/5)")
    else:
        feedback.append("Report missing comparative analysis (0/5)")

    # Final Result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }