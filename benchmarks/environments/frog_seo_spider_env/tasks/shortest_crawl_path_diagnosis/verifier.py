#!/usr/bin/env python3
"""
Verifier for shortest_crawl_path_diagnosis task.

Scoring (100 pts):
1. Crawl Path CSV exists and created during task (30 pts)
2. CSV contains correct target URL (30 pts)
3. CSV contains valid path data (rows > 1 or specific structure) (20 pts)
4. Depth report contains correct integer value (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shortest_crawl_path_diagnosis(traj, env_info, task_info):
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load result JSON
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

    # 3. Evaluate CSV (60 pts total)
    if result.get("csv_exists") and result.get("csv_modified_in_task"):
        score += 30
        feedback.append("Crawl Path CSV created successfully (+30).")
        
        # Check content
        if result.get("csv_has_target"):
            score += 30
            feedback.append("CSV contains target URL 'its-only-the-himalayas' (+30).")
        else:
            feedback.append("CSV does not contain target URL fragment (-30).")
            
        # Check validity (non-empty)
        if result.get("csv_row_count", 0) > 1:
             # Typically a path report has headers + at least 1 row of path data
             # Or multiple rows if listing links in chain
             score += 20
             feedback.append("CSV contains path data (+20).")
        else:
             feedback.append("CSV appears empty or header-only (-20).")
    else:
        feedback.append("Crawl Path CSV not found or not created during task (-80).")

    # 4. Evaluate Text Report (20 pts total)
    # Expected depth for "It's Only the Himalayas" on books.toscrape.com
    # Path: Home -> Travel -> Book (Depth 2 or 3 depending on 0-indexing)
    # Allow range 1-4 to account for slight crawling variations or counting methods
    if result.get("report_exists") and result.get("report_modified_in_task"):
        content = result.get("report_content", "").strip()
        try:
            depth = int(content)
            if 1 <= depth <= 4:
                score += 20
                feedback.append(f"Depth report value '{depth}' is within valid range (+20).")
            else:
                feedback.append(f"Depth report value '{depth}' seems incorrect (expected 1-4) (-20).")
        except ValueError:
            feedback.append("Depth report does not contain a valid integer (-20).")
    else:
        feedback.append("Depth report text file not found (-20).")

    # 5. Finalize
    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }