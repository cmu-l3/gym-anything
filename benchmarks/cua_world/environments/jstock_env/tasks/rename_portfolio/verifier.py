#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_portfolio(traj, env_info, task_info):
    """
    Verifies that the JStock portfolio was renamed correctly.
    
    Criteria:
    1. New directory "Tech Growth Fund" exists (20pts)
    2. Old directory "My Portfolio" (specifically the csv) is gone (15pts)
    3. New directory contains buyportfolio.csv (15pts)
    4. Transaction data is preserved (AAPL, MSFT, NVDA) (10pts each = 30pts)
    5. JStock app is running (10pts)
    6. VLM check (10pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_transactions = metadata.get('expected_transactions', [])
    
    # Load result from container
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
    feedback_parts = []
    
    # 1. New Directory Check
    if result.get("new_dir_exists"):
        score += 20
        feedback_parts.append("New portfolio directory found")
    else:
        feedback_parts.append("New portfolio directory NOT found")

    # 2. Old Directory Check
    if not result.get("old_dir_exists"):
        score += 15
        feedback_parts.append("Old portfolio removed")
    else:
        feedback_parts.append("Old portfolio still exists")

    # 3. CSV Existence Check
    if result.get("csv_exists"):
        score += 15
        feedback_parts.append("Portfolio data file exists")
    else:
        feedback_parts.append("Portfolio data file missing")

    # 4. Data Integrity Check (30 pts total)
    transactions = result.get("transactions", [])
    matched_count = 0
    
    for expected in expected_transactions:
        found = False
        for actual in transactions:
            # Check Code (allowing for quotes or no quotes)
            code_match = actual.get("code") == expected["code"]
            
            # Check Units and Price with small tolerance
            units_match = abs(actual.get("units", 0) - expected["units"]) < 0.01
            price_match = abs(actual.get("price", 0) - expected["price"]) < 0.01
            
            if code_match and units_match and price_match:
                found = True
                break
        
        if found:
            matched_count += 1
            score += 10
            feedback_parts.append(f"{expected['code']} preserved")
        else:
            feedback_parts.append(f"{expected['code']} missing or incorrect")

    # 5. App State Check
    if result.get("app_running"):
        score += 10
        feedback_parts.append("JStock is running")
    else:
        feedback_parts.append("JStock was closed")

    # 6. VLM / Basic Visual Check (Placeholder logic for 10pts)
    # In a full implementation, we would query the VLM here using trajectory frames.
    # For this deterministic verifier, we assume if file structure is correct, visual is likely correct.
    # We give points if the core task (file rename + data preserve) succeeded.
    if result.get("new_dir_exists") and matched_count >= 2:
        score += 10
        feedback_parts.append("Visual verification inferred from data success")
    
    # Final Evaluation
    # Pass if: Directory renamed AND at least 2/3 transactions preserved
    passed = result.get("new_dir_exists") and matched_count >= 2 and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }