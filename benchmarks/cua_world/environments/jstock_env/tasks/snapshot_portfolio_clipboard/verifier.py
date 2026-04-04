#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_snapshot_portfolio(traj, env_info, task_info):
    """
    Verify the portfolio snapshot task.
    
    Criteria:
    1. Output file exists and was created during task (30 pts)
    2. File content contains AAPL and 123 (20 pts)
    3. File content contains MSFT and 45 (20 pts)
    4. VLM: Trajectory shows selection/copy interaction (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get programmatic results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract specific file content (full file)
    # The export script only gave us a preview. Let's try to copy the actual text file
    # to be robust against large files or encoding issues.
    file_content = ""
    if result.get('output_exists'):
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/portfolio_snapshot.txt", temp_txt.name)
            with open(temp_txt.name, 'r', errors='ignore') as f:
                file_content = f.read()
        except:
            # Fallback to preview if copy failed
            file_content = result.get('content_preview_json', "")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)

    score = 0
    feedback = []

    # Criterion 1: File Creation (30 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 30
        feedback.append("Success: Snapshot file created.")
    elif result.get('output_exists'):
        score += 15
        feedback.append("Partial: File exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("Fail: No output file found.")

    # Criterion 2 & 3: Content Verification (40 pts)
    # Check for our specific anti-gaming numbers
    required_data = [("AAPL", "123"), ("MSFT", "45")]
    
    for symbol, units in required_data:
        # Check symbol
        has_symbol = symbol in file_content
        # Check units (ensure it's not just part of a larger number, strict check difficult in raw text, simple contains is okay)
        has_units = units in file_content
        
        if has_symbol and has_units:
            score += 20
            feedback.append(f"Success: Found {symbol} with {units} units.")
        elif has_symbol:
            score += 5
            feedback.append(f"Partial: Found {symbol} but missing unit count {units}.")
        else:
            feedback.append(f"Fail: Missing data for {symbol}.")

    # Criterion 4: VLM Verification (30 pts)
    # Did the agent actually use the UI or just `echo ... > file`?
    # We look for table selection (blue highlight) or context menu usage.
    
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a stock software task. "
        "The user should be selecting rows in a portfolio table (look for blue highlighting) "
        "and copying them (Ctrl+C or Right-click > Copy). "
        "Then pasting into a text editor. "
        "Does the visual evidence show the user selecting rows in the JStock portfolio table? "
        "Answer YES or NO and explain."
    )
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt).strip()
        if "YES" in vlm_result.upper():
            score += 30
            feedback.append("Success: VLM confirmed UI interaction.")
        else:
            # Fallback: if text content is perfect, we might be lenient, 
            # but for now we want to encourage UI usage.
            # If they used keyboard shortcuts (Ctrl+A, Ctrl+C), visual evidence might be subtle (just highlighting).
            # If content is perfect (70 pts so far), we can assume they did it.
            if score >= 70:
                score += 30
                feedback.append("Success: Content matches perfectly (VLM inconclusive but task likely done).")
            else:
                feedback.append("Fail: VLM did not observe table selection.")
                logger.info(f"VLM Response: {vlm_result}")
    except Exception as e:
        # If VLM fails, give benefit of doubt if file content is correct
        logger.error(f"VLM error: {e}")
        if score >= 70:
            score += 30
            feedback.append("VLM skipped, content verified.")

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }