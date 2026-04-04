#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_portfolio_to_csv(traj, env_info, task_info):
    """
    Verifies that the JStock portfolio was exported to CSV.
    
    Scoring:
    - 15 pts: Output file exists at correct path
    - 15 pts: File created/modified AFTER task start (anti-gaming)
    - 10 pts: File size > 50 bytes (not empty)
    - 15 pts: CSV Header detected
    - 30 pts: Content check (10 pts each for AAPL, MSFT, NVDA)
    - 15 pts: VLM verification of trajectory (navigated to portfolio tab)
    
    Total: 100 pts
    Threshold: 60 pts
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. programmatic Verification
    
    # Criterion 1: File Existence (15 pts)
    if result.get('output_exists'):
        score += 15
        feedback_parts.append("Export file found.")
    else:
        feedback_parts.append("Export file NOT found at expected path.")
    
    # Criterion 2: Timestamp (Anti-gaming) (15 pts)
    if result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created during task session.")
    elif result.get('output_exists'):
        feedback_parts.append("Warning: File timestamp indicates it was not created during this session.")
        
    # Criterion 3: File Size (10 pts)
    size = result.get('output_size_bytes', 0)
    if size > 50:
        score += 10
        feedback_parts.append(f"File size valid ({size} bytes).")
    else:
        if result.get('output_exists'):
            feedback_parts.append(f"File is empty or too small ({size} bytes).")

    # Criterion 4: Header Check (15 pts)
    if result.get('has_header'):
        score += 15
        feedback_parts.append("CSV header detected.")
    else:
        if result.get('output_exists'):
            feedback_parts.append("CSV header missing or invalid.")

    # Criterion 5: Data Content (30 pts)
    stocks_found = 0
    if result.get('has_aapl'):
        score += 10
        stocks_found += 1
    if result.get('has_msft'):
        score += 10
        stocks_found += 1
    if result.get('has_nvda'):
        score += 10
        stocks_found += 1
    
    if stocks_found > 0:
        feedback_parts.append(f"Found data for {stocks_found}/3 expected stocks.")
    
    # 3. VLM Verification (15 pts)
    # Check if agent navigated to Portfolio Management tab
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        # Simple prompt to verify workflow
        prompt = (
            "Review these screenshots of a stock market software (JStock). "
            "Did the agent navigate to the 'Portfolio Management' tab (looks like a table of investments) "
            "and open a file export or save dialog? "
            "Reply 'YES' if they accessed the portfolio view and tried to save/export, otherwise 'NO'."
        )
        
        vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt).strip().upper()
        
        if "YES" in vlm_response:
            vlm_score = 15
            feedback_parts.append("VLM confirmed portfolio navigation.")
        else:
            feedback_parts.append("VLM did not observe portfolio navigation.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if data checks passed perfectly, assume navigation happened
        if score >= 70: 
            vlm_score = 15
            feedback_parts.append("VLM skipped, inferred success from data.")

    score += vlm_score

    # 4. Final Determination
    # Pass if file exists, is new, has header, and at least 2 stocks found (Total ~65 pts min required here)
    # Set rigid threshold at 60
    passed = score >= 60 and result.get('output_exists') and result.get('file_created_during_task')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }