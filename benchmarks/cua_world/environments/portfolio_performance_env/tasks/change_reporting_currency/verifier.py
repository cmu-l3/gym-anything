#!/usr/bin/env python3
"""
Verifier for change_reporting_currency task.
Checks if the portfolio XML has been updated to EUR and includes exchange rate data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_reporting_currency(traj, env_info, task_info):
    """
    Verify that:
    1. The portfolio file exists and was modified.
    2. The reference/base currency is set to EUR.
    3. Historical exchange rate data has been imported (prices exist for a EUR security).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_currency = metadata.get('expected_currency', 'EUR')
    min_rates = metadata.get('min_rates_count', 10)

    # Copy result
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
            
    analysis = result.get("analysis", {})
    
    score = 0
    feedback_parts = []
    
    # 1. File Modification (20 pts)
    if analysis.get("file_exists") and analysis.get("file_modified"):
        score += 20
        feedback_parts.append("Portfolio file saved successfully")
    elif analysis.get("file_exists"):
        feedback_parts.append("Portfolio file found but NOT saved/modified")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found"}

    # 2. Check Currency (40 pts)
    base_curr = analysis.get("base_currency", "")
    if base_curr == expected_currency:
        score += 40
        feedback_parts.append(f"Currency correctly set to {base_curr}")
    else:
        feedback_parts.append(f"Currency is '{base_curr}' (expected '{expected_currency}')")

    # 3. Check Exchange Rate Data (40 pts)
    has_rates = analysis.get("exchange_rates_found", False)
    rate_count = analysis.get("exchange_rate_data_count", 0)
    
    if has_rates and rate_count >= min_rates:
        score += 40
        feedback_parts.append(f"Exchange rate data imported ({rate_count} entries)")
    elif has_rates:
        score += 20
        feedback_parts.append(f"Some exchange rate data found but few entries ({rate_count})")
    else:
        feedback_parts.append("No exchange rate price data found (did you import the CSV?)")

    # Pass threshold
    passed = score >= 70  # Needs currency switch + significant progress on data or file save
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }