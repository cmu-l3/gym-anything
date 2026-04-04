#!/usr/bin/env python3
"""
Verifier for record_portfolio_dividends task.

Checks if JStock dividend CSV contains the correct entries for AAPL and MSFT.
Uses MULTIPLE SIGNALS:
1. File modification time (Anti-gaming)
2. Content verification (Correct amounts and dates)
3. VLM Trajectory analysis (Agent actually used the UI)
"""

import json
import tempfile
import os
import logging
import base64
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_portfolio_dividends(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata for expected values
    # AAPL: $96.00, Feb 15, 2024
    # MSFT: $37.50, Mar 14, 2024
    
    # =========================================================
    # CRITERION 1: File Modification (Anti-Gaming) (10 pts)
    # =========================================================
    if result.get('file_modified', False):
        score += 10
        feedback.append("Dividend file modified during task.")
    else:
        feedback.append("Dividend file was NOT modified/saved.")
        # If file wasn't saved, we can't verify content, but we proceed to check structure just in case.

    # =========================================================
    # CRITERION 2: Content Verification (60 pts)
    # =========================================================
    parsed_rows = result.get('parsed_rows', [])
    
    # Trackers
    aapl_found = False
    aapl_correct = False
    msft_found = False
    msft_correct = False
    
    for row in parsed_rows:
        code = row.get('code', '').upper()
        amount_str = row.get('amount', '0').replace(',', '') # Handle 1,000.00
        date_str = row.get('date', '')
        
        try:
            amount = float(amount_str)
        except ValueError:
            amount = 0.0

        # Check AAPL
        if 'AAPL' in code:
            aapl_found = True
            # Amount check: 96.00 ± 0.5
            amt_ok = abs(amount - 96.0) < 0.5
            # Date check: Feb / 02 / 2024
            date_ok = ('feb' in date_str.lower() or '02' in date_str) and '2024' in date_str
            
            if amt_ok and date_ok:
                aapl_correct = True
                feedback.append(f"AAPL entry correct (${amount}, {date_str}).")
            else:
                feedback.append(f"AAPL entry found but incorrect (Amount: {amount}, Date: {date_str}). Expected: 96.00 in Feb 2024.")

        # Check MSFT
        if 'MSFT' in code:
            msft_found = True
            # Amount check: 37.50 ± 0.5
            amt_ok = abs(amount - 37.5) < 0.5
            # Date check: Mar / 03 / 2024
            date_ok = ('mar' in date_str.lower() or '03' in date_str) and '2024' in date_str
            
            if amt_ok and date_ok:
                msft_correct = True
                feedback.append(f"MSFT entry correct (${amount}, {date_str}).")
            else:
                feedback.append(f"MSFT entry found but incorrect (Amount: {amount}, Date: {date_str}). Expected: 37.50 in Mar 2024.")

    # Scoring Logic for Content
    if aapl_found: score += 10
    if aapl_correct: score += 20
    if msft_found: score += 10
    if msft_correct: score += 20
    
    # Extra check for stray data
    if len(parsed_rows) == 2 and aapl_found and msft_found:
        score += 10
        feedback.append("Exactly 2 entries found (Clean data).")
    elif len(parsed_rows) > 2:
        feedback.append(f"Found {len(parsed_rows)} entries (Expected 2).")

    # =========================================================
    # CRITERION 3: VLM Verification (20 pts)
    # =========================================================
    # Check if agent actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_score = 0
        
        # Q1: Did the agent open the Dividend dialog?
        q1 = query_vlm(
            images=frames, 
            prompt="Does any of these screenshots show a 'Dividend' dialog box or the user entering a date/amount into a form?"
        )
        if q1.get("answer_bool", False):
            vlm_score += 10
        
        # Q2: Is JStock visible in final state?
        final_ss = get_final_screenshot(traj)
        if final_ss:
            q2 = query_vlm(
                images=[final_ss],
                prompt="Is the JStock application window visible?"
            )
            if q2.get("answer_bool", False):
                vlm_score += 10
                
        score += vlm_score
        feedback.append(f"VLM verification score: {vlm_score}/20")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # fallback: give full points if content is perfect to avoid punishing valid work
        if aapl_correct and msft_correct:
            score += 20
            feedback.append("VLM skipped, awarded points based on perfect data.")

    passed = (score >= 60) and aapl_correct and msft_correct
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }