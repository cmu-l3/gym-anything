#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from typing import List, Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_content(content: str) -> List[str]:
    """
    Parses JStock CSV content to extract stock codes.
    Expects format: "Code","Symbol",...
    Returns a list of stock codes (e.g., ["AAPL", "MSFT"]).
    """
    codes = []
    if not content:
        return codes
        
    lines = content.strip().split('\n')
    for line in lines:
        line = line.strip()
        if not line or line.startswith('"timestamp'):
            continue
        
        # Split by comma, respecting quotes ideally, but JStock format is simple
        # "AAPL","Apple Inc.",...
        parts = line.split(',')
        if len(parts) > 0:
            # Extract code from first column "Code"
            code = parts[0].replace('"', '').strip()
            # Skip header row
            if code.lower() == "code":
                continue
            if code:
                codes.append(code)
    return codes

def verify_segment_watchlist(traj, env_info, task_info):
    """
    Verifies that:
    1. 'Core Holdings' watchlist was created.
    2. AAPL and MSFT were moved to 'Core Holdings'.
    3. AAPL and MSFT were removed from 'My Watchlist'.
    4. Remaining stocks (GOOGL, AMZN, NVDA) are preserved in 'My Watchlist'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    moved_stocks = set(metadata.get('moved_stocks', ["AAPL", "MSFT"]))
    remaining_stocks = set(metadata.get('remaining_stocks', ["GOOGL", "AMZN", "NVDA"]))
    target_name = metadata.get('target_watchlist_name', "Core Holdings")

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Target Watchlist Creation (20 pts)
    target_info = result.get('target_watchlist', {})
    target_codes = set(parse_csv_content(target_info.get('content', '')))
    
    if target_info.get('exists') and target_info.get('created_during_task'):
        score += 20
        feedback.append(f"✓ '{target_name}' watchlist created.")
    elif target_info.get('exists'):
        score += 10 # Half points if exists but timestamp ambiguous (unlikely with clean setup)
        feedback.append(f"⚠ '{target_name}' exists but timestamp check failed.")
    else:
        feedback.append(f"✗ '{target_name}' watchlist NOT created.")

    # 2. Verify AAPL/MSFT in Target (20 pts)
    # Check if ALL moved stocks are in target
    missing_in_target = moved_stocks - target_codes
    if not missing_in_target:
        score += 20
        feedback.append(f"✓ {', '.join(moved_stocks)} found in '{target_name}'.")
    else:
        # Partial credit?
        present = moved_stocks - missing_in_target
        if present:
            score += 10
            feedback.append(f"⚠ Only {', '.join(present)} found in '{target_name}' (missing {', '.join(missing_in_target)}).")
        else:
            feedback.append(f"✗ None of the required stocks found in '{target_name}'.")

    # 3. Verify Source Watchlist Cleanup (20 pts)
    source_info = result.get('source_watchlist', {})
    source_codes = set(parse_csv_content(source_info.get('content', '')))
    
    # Check if moved stocks are REMOVED from source
    still_in_source = moved_stocks.intersection(source_codes)
    if not still_in_source:
        score += 20
        feedback.append(f"✓ {', '.join(moved_stocks)} successfully removed from 'My Watchlist'.")
    else:
        feedback.append(f"✗ {', '.join(still_in_source)} still present in 'My Watchlist'.")

    # 4. Verify Preservation of Others (20 pts)
    # Check if remaining stocks are STILL in source
    missing_from_source = remaining_stocks - source_codes
    if not missing_from_source:
        score += 20
        feedback.append(f"✓ Remaining stocks preserved in 'My Watchlist'.")
    else:
        feedback.append(f"✗ Stocks accidentally deleted: {', '.join(missing_from_source)}.")

    # 5. VLM Verification (20 pts)
    # Use VLM to confirm the UI interactions (creation of list, deletion of rows)
    # This helps catch "manual file editing" cheats, though checking timestamps helps too.
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(
            images=frames + [final_screen],
            prompt=f"Did the user create a new watchlist named '{target_name}' and move stocks AAPL/MSFT to it? Look for a new tab or menu item with that name. Look for rows being deleted from the original list."
        )
        if vlm_resp and "yes" in vlm_resp.lower():
            vlm_score = 20
            feedback.append("✓ VLM confirms workflow.")
        else:
            # Fallback if VLM is unsure but files are perfect
            if score >= 80:
                vlm_score = 20
                feedback.append("✓ Files correct (VLM inconclusive).")
            else:
                feedback.append("? VLM could not confirm workflow.")
    except Exception:
        # If VLM fails, default to trusting files if high score
        if score >= 80:
            vlm_score = 20
    
    score += vlm_score

    passed = (score >= 80) and (not missing_in_target) and (not still_in_source)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }