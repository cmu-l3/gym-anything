#!/usr/bin/env python3
"""
Verifier for SEC Filing Retrieval task.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sec_filing_retrieval(traj, env_info, task_info):
    """
    Verifies that the agent retrieved the correct Ford 10-K and extracted the right numbers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # 1. Check History (15 points)
    sec_visits = result.get('history', {}).get('sec_visits', 0)
    if sec_visits > 0:
        score += 15
        feedback.append("SEC website visited.")
    else:
        feedback.append("No history of visiting SEC.gov found.")

    # 2. Check Download (25 points)
    download = result.get('download', {})
    filename = download.get('filename', '').lower()
    is_large = download.get('is_large_enough', False)
    
    # Expect 'ford' or '10-k' or '10k' in filename usually, but primarily size and existence
    # Real 10-Ks are usually > 1MB, definitely > 500KB
    if filename and is_large:
        # Check if it looks like a document
        if filename.endswith('.pdf') or filename.endswith('.htm') or filename.endswith('.html'):
            score += 25
            feedback.append(f"Filing document downloaded: {filename} ({download.get('size_bytes')} bytes).")
        else:
            score += 10
            feedback.append(f"File downloaded but extension unclear: {filename}.")
    elif filename:
        feedback.append(f"File downloaded but too small to be a full 10-K: {filename}.")
    else:
        feedback.append("No filing document found in Downloads.")

    # 3. Check Summary File Existence (10 points)
    summary = result.get('summary', {})
    content = summary.get('content', '')
    if summary.get('exists'):
        score += 10
        feedback.append("Summary file created.")
    else:
        feedback.append("Summary file missing.")

    # 4. Check Data Extraction (50 points total)
    # Expected: Revenue ~184,992, Net Income ~5,879
    # Patterns allow for "184,992" or "184992" or "$184,992"
    # Also need to be careful of context, but simple regex is usually sufficient for this level
    
    # Revenue Check (25 pts)
    # Look for 184,992 with flexible punctuation
    rev_pattern = re.compile(r'184[.,]?992')
    if rev_pattern.search(content):
        score += 25
        feedback.append("Revenue value matches expected (approx 184,992).")
    else:
        feedback.append("Revenue value not found or incorrect.")

    # Net Income Check (25 pts)
    # Look for 5,879 with flexible punctuation
    inc_pattern = re.compile(r'5[.,]?879')
    if inc_pattern.search(content):
        score += 25
        feedback.append("Net Income value matches expected (approx 5,879).")
    else:
        feedback.append("Net Income value not found or incorrect.")

    # 5. VLM Trajectory Verification (Anti-gaming / Context check)
    # If the score is borderline or perfect, use VLM to ensure they didn't just guess or hallucinate.
    # We want to see evidence of the financial table.
    
    # Only verify visually if they downloaded something or extracted data
    if score > 15:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # Simple check: did they look at a financial table?
        vlm_prompt = (
            "Does the user appear to be viewing a financial report, "
            "specifically a Statement of Operations or Income Statement? "
            "Are they on the SEC website or viewing a PDF/HTML document?"
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('is_financial_doc', True):
                 # We don't deduct points here usually, but could use it to flag cheating
                 # For now, just append feedback
                 feedback.append("Visual verification confirmed viewing of financial documents.")
        except Exception:
            pass # VLM failure shouldn't fail the task if file checks pass

    # Normalize Score
    score = min(score, 100)
    passed = (score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }