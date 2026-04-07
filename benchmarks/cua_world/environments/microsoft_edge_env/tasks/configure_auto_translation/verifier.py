#!/usr/bin/env python3
"""
Verifier for configure_auto_translation task.

Scoring Criteria:
1. PDF Created (20 pts): Output file exists and was created during task.
2. PDF Valid (10 pts): Size > 50KB (indicates successful content render).
3. Source Visited (20 pts): History shows visit to the Spanish Wikipedia page.
4. Auto-Translate Configured (50 pts): Edge Preferences show 'es' is set to always translate.
   - This proves the agent configured the AUTOMATION setting, not just manual translation.

Pass Threshold: 70 points (Requires Configuration + Output)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_auto_translation(traj, env_info, task_info):
    """Verify that auto-translation was configured and used."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_pdf_size = metadata.get('min_pdf_size_kb', 50) * 1024
    
    # 2. Get Result JSON
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

    score = 0
    feedback_parts = []
    
    # 3. Check PDF Output (30 pts total)
    pdf_exists = result.get('pdf_exists', False)
    pdf_fresh = result.get('pdf_created_during_task', False)
    pdf_size = result.get('pdf_size_bytes', 0)
    
    if pdf_exists and pdf_fresh:
        score += 20
        feedback_parts.append("PDF created")
        
        if pdf_size > min_pdf_size:
            score += 10
            feedback_parts.append("PDF content valid (>50KB)")
        else:
            feedback_parts.append(f"PDF too small ({pdf_size} bytes)")
    else:
        feedback_parts.append("PDF output missing or stale")

    # 4. Check History (20 pts)
    if result.get('source_visited', False):
        score += 20
        feedback_parts.append("Source URL visited")
    else:
        feedback_parts.append("Source URL NOT visited")

    # 5. Check Configuration (50 pts) - CRITICAL
    # This proves the "configure" part of the task, distinguishing it from manual one-off translation
    if result.get('auto_translate_configured', False):
        score += 50
        feedback_parts.append("Auto-translation correctly configured in Preferences")
    else:
        feedback_parts.append("Auto-translation setting NOT found in Preferences")

    # 6. VLM Verification (Bonus/Sanity Check)
    # We check if the agent actually saw the translation UI or English text
    frames = sample_trajectory_frames(traj, n=3)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_feedback = ""
    try:
        # Prompt checking for English headers on what should be a Spanish page
        vlm_response = query_vlm(
            images=frames,
            prompt="Does the browser display the Wikipedia page title in English (e.g., 'Transport in Spain') instead of Spanish ('Transporte en España')? Do you see settings related to 'Languages' or 'Translate' being modified?"
        )
        if vlm_response.get("success"):
            vlm_feedback = f"VLM Analysis: {vlm_response.get('answer', 'Inconclusive')}"
            # We don't modify score strictly based on VLM here to avoid false negatives, 
            # but it adds confidence to the log.
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final Result
    passed = score >= 70
    feedback = " | ".join(feedback_parts)
    if vlm_feedback:
        feedback += f" | {vlm_feedback}"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }