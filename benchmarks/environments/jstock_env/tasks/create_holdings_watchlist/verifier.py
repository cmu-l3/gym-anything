#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import csv
import io

def verify_create_holdings_watchlist(traj, env_info, task_info):
    """
    Verifies that the agent created the 'Holdings' watchlist with the correct stocks.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_stocks = set(metadata.get('required_stocks', ["AAPL", "MSFT", "NVDA"]))
    forbidden_stocks = set(metadata.get('forbidden_stocks', ["GOOGL", "AMZN"]))
    expected_count = metadata.get('expected_stock_count', 3)

    # 2. Get Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Results
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (20 pts)
    if not result.get('target_file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "The watchlist 'Holdings' was not created."
        }
    score += 20
    feedback.append("Watchlist file created.")

    # Criterion 2: Created during task (10 pts)
    # This prevents using a pre-existing file if setup failed to clean it, 
    # though setup_task.sh handles cleanup.
    if result.get('file_created_during_task', False):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates it wasn't modified during this task session.")

    # Criterion 3: Content Analysis (70 pts max)
    content_b64 = result.get('file_content_base64', "")
    if not content_b64:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Watchlist file is empty."
        }

    try:
        content_str = base64.b64decode(content_b64).decode('utf-8')
        # JStock CSVs have a "timestamp=X" first line, then headers
        # We need to parse it carefully
        lines = content_str.strip().split('\n')
        
        found_stocks = set()
        
        # Parse CSV (skipping first timestamp line if present)
        csv_lines = [l for l in lines if "timestamp=" not in l]
        reader = csv.DictReader(csv_lines)
        
        for row in reader:
            # JStock uses "Code" or "Symbol"
            symbol = row.get('Code', row.get('Symbol', '')).strip()
            if symbol:
                found_stocks.add(symbol)
        
        # Check Required Stocks (15 pts each -> 45 total)
        missing_required = required_stocks - found_stocks
        found_required_count = len(required_stocks) - len(missing_required)
        score += (found_required_count * 15)
        
        if missing_required:
            feedback.append(f"Missing required stocks: {', '.join(missing_required)}")
        else:
            feedback.append("All required stocks (AAPL, MSFT, NVDA) present.")

        # Check Forbidden Stocks (10 pts each -> 20 total)
        found_forbidden = found_stocks.intersection(forbidden_stocks)
        avoided_forbidden_count = len(forbidden_stocks) - len(found_forbidden)
        score += (avoided_forbidden_count * 10)

        if found_forbidden:
            feedback.append(f"Incorrectly included stocks: {', '.join(found_forbidden)}")
        else:
            feedback.append("Correctly excluded non-portfolio stocks.")

        # Bonus/Penalty: Pure Holdings (5 pts)
        # Did they add ONLY the 3 required stocks?
        if len(found_stocks) == expected_count and not missing_required and not found_forbidden:
            score += 5
            feedback.append("Watchlist contains exactly the correct set of stocks.")
        elif len(found_stocks) > expected_count:
            # If they have extra stocks that aren't explicitly forbidden (e.g. random ones)
            feedback.append(f"Watchlist contains {len(found_stocks)} stocks, expected {expected_count}.")

    except Exception as e:
        feedback.append(f"Error parsing CSV content: {str(e)}")

    # 4. Final Verdict
    # Threshold: 85 (Needs creation + all required + at least one forbidden excluded)
    passed = score >= 85

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }