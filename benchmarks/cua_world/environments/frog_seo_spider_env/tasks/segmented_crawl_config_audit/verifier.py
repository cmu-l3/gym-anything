#!/usr/bin/env python3
"""
Verifier for segmented_crawl_config_audit@1

Verifies that the agent:
1. Configured Segments in Screaming Frog
2. Crawled the target site
3. Exported the data containing the "Segment" column
4. Produced a text summary
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_segmented_crawl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. CSV Export Existence (20 pts)
    if result.get("export_exists") and result.get("export_created_during_task"):
        score += 20
        feedback_parts.append("Valid CSV export found (+20)")
    elif result.get("export_exists"):
        score += 10
        feedback_parts.append("CSV export found but timestamp unclear (+10)")
    else:
        feedback_parts.append("No CSV export found (0)")

    # 2. Segment Column Config (30 pts)
    # This proves the configuration was applied in the tool
    if result.get("has_segment_column"):
        score += 30
        feedback_parts.append("'Segment' column found in export (+30)")
    else:
        feedback_parts.append("'Segment' column missing from export - config likely skipped (0)")

    # 3. Correct Segmentation Logic (40 pts)
    # 15 pts for Travel, 15 for Mystery, 10 for Poetry
    t_ok = result.get("travel_correct", False)
    m_ok = result.get("mystery_correct", False)
    p_ok = result.get("poetry_correct", False)
    
    logic_score = 0
    if t_ok: logic_score += 15
    if m_ok: logic_score += 15
    if p_ok: logic_score += 10
    
    score += logic_score
    if logic_score > 0:
        feedback_parts.append(f"Segmentation logic correct for {logic_score} pts")
    
    # 4. Report Existence (10 pts)
    if result.get("report_exists"):
        content = result.get("report_content", "").lower()
        # Check if report mentions the categories
        if "travel" in content and "mystery" in content:
            score += 10
            feedback_parts.append("Summary report valid (+10)")
        else:
            score += 5
            feedback_parts.append("Summary report exists but content minimal (+5)")
    else:
        feedback_parts.append("No summary report found (0)")

    # Final tally
    passed = (score >= 70) and result.get("has_segment_column")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }