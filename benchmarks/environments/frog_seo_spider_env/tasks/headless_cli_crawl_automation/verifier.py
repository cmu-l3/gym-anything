#!/usr/bin/env python3
"""
Verifier for Headless CLI Crawl Automation task.

Scoring System (100 points total):
1. Output Directory Created (10 pts)
2. Export File Exists & Created During Task (30 pts)
   - Exists: 15 pts
   - Created after start: 15 pts
3. Content Validation (60 pts)
   - Valid Domain (quotes.toscrape.com) found in CSV: 40 pts
   - Sufficient Data (>10 rows): 20 pts

Bonus/Penalty:
- If file exists but is empty/invalid: 0 for content.

Pass Threshold: 80 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_headless_cli_crawl(traj, env_info, task_info):
    """Verify the headless CLI crawl task."""
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Output Directory (10 pts)
    if result.get("dir_exists"):
        score += 10
        feedback_parts.append("Output directory created (10/10)")
    else:
        feedback_parts.append("Output directory NOT found (0/10)")

    # 2. Export File Existence & Timing (30 pts)
    file_found = result.get("file_found")
    created_correctly = result.get("file_created_after_start")
    
    if file_found:
        score += 15
        feedback_parts.append("CSV file found (15/15)")
        if created_correctly:
            score += 15
            feedback_parts.append("File created during task (15/15)")
        else:
            feedback_parts.append("File timestamp predates task (0/15)")
    else:
        feedback_parts.append("No CSV file found in output directory (0/30)")

    # 3. Content Validation (60 pts)
    valid_domain = result.get("valid_domain")
    row_count = result.get("row_count", 0)
    expected_rows = task_info.get("metadata", {}).get("expected_min_rows", 10)

    if file_found and created_correctly:
        # Domain check
        if valid_domain:
            score += 40
            feedback_parts.append("CSV contains target domain data (40/40)")
        else:
            feedback_parts.append("CSV does not contain 'quotes.toscrape.com' data (0/40)")

        # Row count check
        if row_count >= expected_rows:
            score += 20
            feedback_parts.append(f"Data volume sufficient ({row_count} rows) (20/20)")
        elif row_count > 0:
            partial = int(20 * (row_count / expected_rows))
            score += partial
            feedback_parts.append(f"Partial data volume ({row_count}/{expected_rows} rows) ({partial}/20)")
        else:
            feedback_parts.append("CSV is empty (0/20)")
    else:
        feedback_parts.append("Skipping content validation due to missing/invalid file (0/60)")

    # Optional: Mention headless log detection in feedback (no points, just confirmation)
    if result.get("headless_log_detected"):
        feedback_parts.append("(Headless execution confirmed in logs)")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }