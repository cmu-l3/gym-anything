#!/usr/bin/env python3
"""Verifier for onion_site_source_archival task."""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_onion_site_source_archival(traj, env_info, task_info):
    """
    Verify the agent successfully performed the dark web archival task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result data: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # DDG Onion History (10 pts)
    if result.get("history_has_search", False):
        score += 10
        feedback_parts.append("DDG onion search in history (10/10)")
    else:
        feedback_parts.append("DDG onion search NOT in history (0/10)")

    # HTML Archive Exists (20 pts) [Gate]
    html_exists = result.get("html_exists", False)
    html_is_new = result.get("html_is_new", False)
    html_size = result.get("html_size", 0)
    
    if html_exists and html_is_new and html_size > 10000:
        score += 20
        feedback_parts.append(f"HTML archive exists and is valid size ({html_size}B) (20/20)")
    elif html_exists and html_size > 0:
        score += 10
        feedback_parts.append(f"HTML archive exists but may be incomplete or old ({html_size}B) (10/20)")
    else:
        feedback_parts.append("HTML archive missing or empty (0/20)")

    # Correct DOM Content (20 pts)
    if result.get("html_has_content", False):
        score += 20
        feedback_parts.append("HTML contains 'digital forensics' (20/20)")
    else:
        feedback_parts.append("HTML missing expected search content (0/20)")

    # Asset Directory Exists (15 pts)
    asset_dir_exists = result.get("asset_dir_exists", False)
    asset_dir_name = result.get("asset_dir_name", "")
    js_count = result.get("js_file_count", 0)
    
    if asset_dir_exists and js_count >= 0:
        score += 15
        feedback_parts.append(f"Asset directory '{asset_dir_name}' exists with {js_count} JS files (15/15)")
    else:
        feedback_parts.append("Asset directory missing (0/15)")

    # Report File Exists (10 pts)
    report_exists = result.get("report_exists", False)
    report_is_new = result.get("report_is_new", False)
    report_content = result.get("report_content", "").lower()
    
    if report_exists and report_is_new:
        score += 10
        feedback_parts.append("Report file exists and is newly created (10/10)")
    elif report_exists:
        score += 5
        feedback_parts.append("Report file exists but predates task (5/10)")
    else:
        feedback_parts.append("Report file missing (0/10)")

    # Parse Report URL (10 pts)
    # Looking for duckduckgo...onion and something about q=digital
    if report_exists:
        url_pattern = r'duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad\.onion.*[?&]q=digital(?:\+|%20)forensics'
        if re.search(url_pattern, report_content):
            score += 10
            feedback_parts.append("Report contains correct DDG onion URL (10/10)")
        elif "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" in report_content:
            score += 5
            feedback_parts.append("Report contains onion domain but missing exact search params (5/10)")
        else:
            feedback_parts.append("Report missing DDG onion URL (0/10)")
    else:
        feedback_parts.append("Report URL check skipped (0/10)")

    # Parse Report Asset Count (15 pts)
    if report_exists and asset_dir_exists:
        # Check if the exact JS count is mentioned in the report
        count_pattern = rf'\b{js_count}\b'
        
        # Check if the asset dir name is mentioned
        dir_name_lower = asset_dir_name.lower()
        
        has_count = bool(re.search(count_pattern, report_content))
        has_dir = dir_name_lower in report_content
        
        if has_count and has_dir:
            score += 15
            feedback_parts.append(f"Report accurately lists directory '{asset_dir_name}' and JS count {js_count} (15/15)")
        elif has_count:
            score += 10
            feedback_parts.append(f"Report accurately lists JS count {js_count} but missing directory name (10/15)")
        elif has_dir:
            score += 5
            feedback_parts.append(f"Report lists directory name but missing JS count {js_count} (5/15)")
        else:
            feedback_parts.append("Report missing accurate directory name and JS count (0/15)")
    else:
        feedback_parts.append("Report asset count check skipped (0/15)")

    # Gate: Must have html file, must pass 75 threshold
    passed = (score >= 75) and html_exists and asset_dir_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }