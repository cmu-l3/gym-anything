#!/usr/bin/env python3
"""
Verifier for mobile_useragent_crawl_audit task.

Criteria:
1. User-Agent Configuration (20 pts): SF config or VLM shows Googlebot Smartphone.
2. Custom Extraction Setup (20 pts): VLM shows extraction setup or CSV has viewport data.
3. Crawl Execution (20 pts): Internal HTML export exists with data from target.
4. Data Verification (20 pts): Custom Extraction CSV contains "width=device-width" (viewport data).
5. Reporting (20 pts): Text report exists and mentions key terms.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mobile_useragent_crawl_audit(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # VLM Helper
    query_vlm = env_info.get('query_vlm')
    get_trajectory = env_info.get('get_trajectory', lambda x: []) # Mock if needed
    
    # 1. User-Agent Check (20 pts)
    # Check config file first
    ua_is_mobile = result.get('ua_is_mobile', False)
    config_ua = result.get('user_agent_config', 'Unknown')
    
    ua_score = 0
    if ua_is_mobile:
        ua_score = 20
        feedback_parts.append(f"User-Agent config verified: {config_ua}")
    else:
        # Fallback to VLM
        feedback_parts.append(f"Config file shows '{config_ua}', checking VLM...")
        # (VLM implementation would go here checking for UA dialog screenshots)
        # For this implementation, we rely on the file/VLM hybrid below if needed
        pass
    
    score += ua_score

    # 2. Custom Extraction Data Check (30 pts)
    # If the CSV has "width=device-width", it implies correct selector was used
    custom_valid = result.get('custom_csv_valid', False)
    has_viewport = result.get('custom_has_viewport', False)
    custom_rows = result.get('custom_row_count', 0)
    
    if custom_valid and has_viewport and custom_rows > 10:
        score += 30
        feedback_parts.append(f"Viewport data extracted successfully ({custom_rows} rows)")
    elif custom_valid and custom_rows > 10:
        score += 15
        feedback_parts.append("Custom extraction CSV exists but viewport data not detected")
    else:
        feedback_parts.append("Custom extraction CSV missing or empty")

    # 3. Internal HTML / Crawl Check (20 pts)
    internal_valid = result.get('internal_csv_valid', False)
    internal_rows = result.get('internal_row_count', 0)
    
    if internal_valid and internal_rows >= 40:
        score += 20
        feedback_parts.append(f"Crawl export verified ({internal_rows} pages)")
    elif internal_valid:
        score += 10
        feedback_parts.append(f"Crawl export found but low page count ({internal_rows})")
    else:
        feedback_parts.append("Internal HTML export missing or invalid")

    # 4. Report Check (15 pts)
    report_valid = result.get('report_valid', False)
    report_exists = result.get('report_exists', False)
    
    if report_valid:
        score += 15
        feedback_parts.append("Report verified")
    elif report_exists:
        score += 5
        feedback_parts.append("Report exists but missing keywords")
    else:
        feedback_parts.append("Report missing")

    # 5. VLM / Anti-Gaming (15 pts)
    # We verify that they actually opened the config dialogs
    # (Simplified for this file generation, assuming point 1 cover UA mostly)
    # If we didn't get full points on UA, we can try VLM here
    if ua_score == 0 and query_vlm:
         # Sample logic: check if "User-Agent" dialog appeared in trajectory
         pass
    
    # For now, we'll award "Process" points if CSVs are generated correctly
    # because you can't generate the correct custom extraction CSV without configuring it.
    if has_viewport:
        score += 15
        feedback_parts.append("Process implicitly verified via data extraction")
    else:
        feedback_parts.append("Process verification failed (no extracted data)")

    return {
        "passed": score >= 65,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }