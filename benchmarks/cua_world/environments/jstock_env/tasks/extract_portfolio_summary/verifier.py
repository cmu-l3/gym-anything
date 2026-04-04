#!/usr/bin/env python3
"""
Verifier for extract_portfolio_summary task.

Verifies:
1. File ~/portfolio_summary.txt exists and was created during task.
2. Content structure matches requirements.
3. Data accuracy (Portfolio items, Total Value, Watchlist items).
4. VLM verification for trajectory (visiting views).
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_portfolio_summary(traj, env_info, task_info):
    """
    Verify the extracted portfolio summary report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total_value', 52627.5)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
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

    # 1. File Existence and Timing (10 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    content = result.get('output_content_raw', "")
    
    if output_exists:
        if created_during:
            score += 10
            feedback_parts.append("File created successfully")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp indicates pre-existence (check system time)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file ~/portfolio_summary.txt not found"}
        
    if not content.strip():
        return {"passed": False, "score": 5, "feedback": "Output file is empty"}

    # 2. Portfolio Data Verification (45 pts)
    # Check for correct total count
    if re.search(r"Number of Stocks.*3", content, re.IGNORECASE) or content.count("- ") >= 3:
        score += 10
        feedback_parts.append("Portfolio count correct")
    else:
        feedback_parts.append("Portfolio count mismatch")

    # Check for specific stocks and values
    # AAPL: 100 shares @ 185.2 = 18520
    if "AAPL" in content and "100" in content and ("185.2" in content or "18520" in content):
        score += 10
        feedback_parts.append("AAPL details correct")
    else:
        feedback_parts.append("AAPL details missing/incorrect")

    # MSFT: 50 shares @ 374.5 = 18725
    if "MSFT" in content and "50" in content and ("374.5" in content or "18725" in content):
        score += 10
        feedback_parts.append("MSFT details correct")
    else:
        feedback_parts.append("MSFT details missing/incorrect")

    # NVDA: 25 shares @ 615.3 = 15382.5
    if "NVDA" in content and "25" in content and ("615.3" in content or "15382" in content):
        score += 5
        feedback_parts.append("NVDA details correct")
    else:
        feedback_parts.append("NVDA details missing/incorrect")

    # Check Total Value (Allow formatting variations: 52,627.50, 52627.5, etc.)
    # Remove commas and currency signs for checking
    clean_content = content.replace(",", "").replace("$", "")
    if "52627.5" in clean_content:
        score += 10
        feedback_parts.append(f"Total Net Purchase Value correct (${expected_total})")
    else:
        feedback_parts.append(f"Total value incorrect (expected ${expected_total})")

    # 3. Watchlist Data Verification (20 pts)
    # Check count
    if re.search(r"Number of Stocks.*5", content, re.IGNORECASE) or \
       (re.search(r"Watchlist", content, re.IGNORECASE) and len(re.findall(r"AAPL|MSFT|GOOGL|AMZN|NVDA", content)) >= 5):
        score += 10
        feedback_parts.append("Watchlist count correct")
    else:
        feedback_parts.append("Watchlist count mismatch")

    # Check symbols presence
    missing_symbols = []
    for sym in ["AAPL", "MSFT", "GOOGL", "AMZN", "NVDA"]:
        if sym not in content:
            missing_symbols.append(sym)
    
    if not missing_symbols:
        score += 10
        feedback_parts.append("All watchlist symbols present")
    else:
        feedback_parts.append(f"Missing symbols: {', '.join(missing_symbols)}")

    # 4. VLM / App State Verification (25 pts)
    # Since we can't easily run VLM inside this function without external calls,
    # we use proxies:
    # - If data is accurate, they MUST have visited the views.
    # - We verify the app was still running at the end.
    
    if result.get('app_was_running', False):
        score += 5
        feedback_parts.append("JStock was running")
    else:
        feedback_parts.append("JStock was closed")

    # Trajectory proxy: If they got both Portfolio specific data AND Watchlist specific data
    # (specifically GOOGL/AMZN which are ONLY in watchlist), they navigated.
    has_portfolio_data = "18520" in clean_content or "18725" in clean_content
    has_watchlist_data = "GOOGL" in content and "AMZN" in content
    
    if has_portfolio_data and has_watchlist_data:
        score += 20
        feedback_parts.append("Navigation verified via data coverage")
    elif has_portfolio_data:
        score += 10
        feedback_parts.append("Partial navigation (Portfolio only)")
    elif has_watchlist_data:
        score += 10
        feedback_parts.append("Partial navigation (Watchlist only)")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }