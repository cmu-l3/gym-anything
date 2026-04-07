#!/usr/bin/env python3
"""
Verifier for Electronics Sourcing Research task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_electronics_sourcing(traj, env_info, task_info):
    """
    Verify the electronics sourcing task.
    
    Rubric (100 pts):
    - Bookmarks (30 pts):
      - "SBC Tracking" folder exists (15 pts)
      - Contains 3 correct URLs (5 pts each)
    - Report (30 pts):
      - Exists & modified (10 pts)
      - Contains all 3 vendors (10 pts)
      - Contains pricing data (10 pts)
    - Screenshots (25 pts):
      - 3 valid screenshots in Evidence folder (8.33 pts each)
    - History (15 pts):
      - Visits to all 3 domains (5 pts each)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Bookmarks Verification (30 pts)
    bk = result.get("bookmarks", {})
    if bk.get("sbc_folder_found"):
        score += 15
        feedback.append("Bookmark folder 'SBC Tracking' created (+15)")
    else:
        feedback.append("Bookmark folder 'SBC Tracking' NOT found")

    valid_urls = set(bk.get("valid_urls", []))
    url_score = len(valid_urls) * 5
    score += url_score
    feedback.append(f"Bookmarks found for {len(valid_urls)}/3 vendors (+{url_score})")

    # 2. Report Verification (30 pts)
    rep = result.get("report", {})
    if rep.get("exists"):
        score += 10
        feedback.append("Report file created (+10)")
        
        vendors = set(rep.get("vendors_found", []))
        if len(vendors) == 3:
            score += 10
            feedback.append("All 3 vendors mentioned in report (+10)")
        else:
            partial = int(len(vendors) * 3.33)
            score += partial
            feedback.append(f"{len(vendors)}/3 vendors mentioned (+{partial})")
            
        if rep.get("prices_found"):
            score += 10
            feedback.append("Pricing data found in report (+10)")
        else:
            feedback.append("No pricing data found in report")
    else:
        feedback.append("Report file sourcing_report.txt NOT found")

    # 3. Screenshots Verification (25 pts)
    screens = result.get("screenshots", {})
    count = screens.get("count", 0)
    # Cap at 3
    valid_count = min(count, 3)
    screen_score = int(valid_count * 8.34) # 25 / 3 approx
    score += screen_score
    feedback.append(f"Found {valid_count}/3 evidence screenshots (+{screen_score})")

    # 4. History Verification (15 pts)
    hist = result.get("history", {})
    visited = set(hist.get("visited_targets", []))
    hist_score = len(visited) * 5
    score += hist_score
    feedback.append(f"History confirms visits to {len(visited)}/3 domains (+{hist_score})")

    # Pass logic
    passed = score >= 70 and rep.get("exists") and bk.get("sbc_folder_found")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback)
    }