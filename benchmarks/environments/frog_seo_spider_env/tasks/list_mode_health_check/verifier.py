#!/usr/bin/env python3
"""Verifier for List Mode Health Check task.

Scoring (100 points total):
- CSV Export exists & modified (10 pts)
- CSV has correct URL subset (20 pts)
- CSV row count indicates List Mode usage (15 pts) [15-60 rows]
- CSV has SEO data columns (15 pts)
- Report exists & has content (20 pts)
- Screaming Frog was running (10 pts)
- VLM verification (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_list_mode_health_check(traj, env_info, task_info):
    """Verify list mode health check task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/list_mode_health_check_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # 1. CSV Existence (10 pts)
    if result.get('csv_found', False):
        score += 10
        feedback_parts.append("CSV export found (10/10)")
    else:
        feedback_parts.append("No CSV export found (0/10)")

    # 2. CSV Content - URL Match (20 pts)
    # We checked 5 random URLs. If at least 3 match, full points.
    matched = result.get('urls_matched_count', 0)
    if matched >= 3:
        score += 20
        feedback_parts.append(f"Target URLs confirmed in CSV ({matched}/5 sampled match) (20/20)")
    elif matched > 0:
        score += 10
        feedback_parts.append(f"Some target URLs found in CSV ({matched}/5 sampled match) (10/20)")
    else:
        feedback_parts.append("Target URLs not found in CSV (0/20)")

    # 3. CSV Row Count - List Mode Verification (15 pts)
    # Input was 20 URLs. List mode result should be ~20.
    # Spider mode on books.toscrape.com is ~1000.
    row_count = result.get('csv_row_count', 0)
    if 15 <= row_count <= 60:
        score += 15
        feedback_parts.append(f"Row count ({row_count}) matches List Mode expectation (15/15)")
    elif row_count > 60:
        feedback_parts.append(f"Row count ({row_count}) too high - suggests Spider Mode used instead of List Mode (0/15)")
    else:
        feedback_parts.append(f"Row count ({row_count}) too low (0/15)")

    # 4. SEO Columns (15 pts)
    if result.get('has_seo_columns', False):
        score += 15
        feedback_parts.append("SEO columns (Title, Status) present (15/15)")
    else:
        feedback_parts.append("SEO columns missing or invalid format (0/15)")

    # 5. Report Existence & Content (20 pts)
    if result.get('report_exists', False) and result.get('report_has_content', False):
        score += 20
        feedback_parts.append("Summary report exists with content (20/20)")
    elif result.get('report_exists', False):
        score += 10
        feedback_parts.append("Summary report exists but lacks specific keywords (10/20)")
    else:
        feedback_parts.append("Summary report missing (0/20)")

    # 6. SF Running (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # 7. VLM Verification (10 pts)
    # Optional check if we have screenshot capability
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if query_vlm and get_final_screenshot:
        final_ss = get_final_screenshot(traj)
        if final_ss:
            res = query_vlm(
                prompt="Is this a screenshot of Screaming Frog SEO Spider showing a list of URLs? Look for 'Mode: List' or a list of URLs in the main table.",
                image=final_ss
            )
            if res.get('success') and 'yes' in str(res.get('response', '')).lower():
                vlm_score = 10
                feedback_parts.append("VLM confirms interface (10/10)")
    
    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }