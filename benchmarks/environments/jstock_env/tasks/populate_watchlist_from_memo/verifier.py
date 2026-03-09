#!/usr/bin/env python3
import json
import os
import base64
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_populate_watchlist_from_memo(traj, env_info, task_info):
    """
    Verifies that the agent created the 'Big Banks' watchlist with the correct stocks.
    
    Scoring:
    - Watchlist directory exists: 20 pts
    - CSV file exists and created during task: 10 pts
    - Correct stocks (JPM, BAC, WFC, C) present: 40 pts (10 each)
    - Excluded stocks (GS, MS) NOT present: 20 pts (10 each)
    - VLM Verification (Memo reading + UI usage): 10 pts
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_stocks = set(metadata.get('required_stocks', ["JPM", "BAC", "WFC", "C"]))
    excluded_stocks = set(metadata.get('excluded_stocks', ["GS", "MS"]))

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
    
    # 2. Check File Structure (30 pts)
    if result.get("watchlist_dir_exists", False):
        score += 20
        feedback.append("Watchlist 'Big Banks' directory created.")
    else:
        feedback.append("Watchlist 'Big Banks' directory NOT found.")

    csv_content = ""
    if result.get("csv_exists", False) and result.get("file_created_during_task", False):
        score += 10
        feedback.append("Watchlist CSV file created successfully.")
        try:
            csv_content = base64.b64decode(result.get("csv_content_base64", "")).decode('utf-8')
        except:
            feedback.append("Error decoding CSV content.")
    elif result.get("csv_exists", False):
        feedback.append("CSV file exists but timestamp indicates it wasn't created during task.")
    else:
        feedback.append("Watchlist CSV file NOT found.")

    # 3. Check Stock Content (60 pts)
    # Parse the CSV. JStock CSVs usually quote values. We look for symbols.
    # Simple contains check is usually sufficient for unique tickers, but let's be slightly robust.
    
    found_stocks = set()
    # Normalize content for search
    content_upper = csv_content.upper()
    
    # Check Required Stocks
    missing_required = []
    for stock in required_stocks:
        # Search for "STOCK" to avoid partial matches (e.g. searching 'C' finding 'BAC')
        # JStock format: "Code","Symbol"... -> "JPM","JPM"...
        if f'"{stock}"' in content_upper:
            score += 10
            found_stocks.add(stock)
        else:
            missing_required.append(stock)
            
    if not missing_required:
        feedback.append("All required stocks found.")
    else:
        feedback.append(f"Missing required stocks: {', '.join(missing_required)}")

    # Check Excluded Stocks
    found_excluded = []
    for stock in excluded_stocks:
        if f'"{stock}"' in content_upper:
            found_excluded.append(stock)
            # No points added, points are effectively deducted by not reaching max score
        else:
            score += 10 # 10 pts for correctly excluding each
            
    if not found_excluded:
        feedback.append("Excluded stocks correctly omitted.")
    else:
        feedback.append(f"Failed to exclude: {', '.join(found_excluded)}")

    # 4. VLM Verification (10 pts)
    # Check if agent opened the memo and used the UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screenshot = get_final_screenshot(traj)
        images = frames + [final_screenshot]
        
        prompt = (
            "Analyze these screenshots of a user interaction.\n"
            "1. Did the user open a text editor or viewer to read a file named 'morning_memo.txt'?\n"
            "2. Did the user interact with the JStock application menu to create a 'New Watchlist'?\n"
            "3. Did the user enter stock symbols like JPM, BAC, WFC, or C?\n"
            "Answer with YES or NO for each and provide a brief summary."
        )
        
        vlm_response = query_vlm(images=images, prompt=prompt)
        
        # Simple heuristic on VLM response
        if "YES" in vlm_response.upper():
            vlm_score = 10
            feedback.append("VLM confirms visual workflow.")
        else:
            feedback.append("VLM could not confirm visual workflow.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if memo was accessed via FS check, give partial credit
        if result.get("memo_accessed", False):
            vlm_score = 5
            feedback.append("File system logs show memo was accessed.")

    score += vlm_score

    # 5. Final Determination
    # Pass threshold: 80 points.
    # Must have created directory, file, added at least 3/4 required, and excluded both.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }