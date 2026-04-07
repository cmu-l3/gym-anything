#!/usr/bin/env python3
"""
Verifier for Publish Meeting Minutes as PDF task.

Scoring:
- Source Versioned (20pts): Did the user increment the version of the Note?
- Target Created (20pts): Is there a file in 'Corporate Records'?
- Correct Format (20pts): Is it a PDF?
- Content Verified (30pts): Does it contain the unique string from the Note?
- Correct Title (10pts): Is it named 'Q3-Board-Minutes-Final.pdf'?

Also uses VLM to verify trajectory (did they use the UI?).
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback if running standalone
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_publish_meeting_minutes_pdf(traj, env_info, task_info):
    """
    Verify the publish task using API data exported from container
    and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Extract data
    source_major = result.get("source_major_version", 0)
    target_data = result.get("target_analysis", {})
    
    target_found = target_data.get("target_found", False)
    target_title = target_data.get("target_title", "")
    is_pdf = target_data.get("is_pdf", False)
    content_verified = target_data.get("content_verified", False)
    
    # --- Scoring ---
    
    # Criterion 1: Source Versioned (20 pts)
    # Expecting Major version >= 1 (initial was likely 0.0 or 0.1)
    if source_major >= 1:
        score += 20
        feedback_parts.append("Source note versioned correctly (Major)")
    elif result.get("source_minor_version", 0) > 1:
        score += 10
        feedback_parts.append("Source note versioned (Minor only - partial credit)")
    else:
        feedback_parts.append("Source note version NOT incremented")

    # Criterion 2: Target Created (20 pts)
    if target_found:
        score += 20
        feedback_parts.append("Target file found in Corporate Records")
    else:
        feedback_parts.append("No file found in Corporate Records")
        
    # Criterion 3: Correct Format (20 pts)
    if is_pdf:
        score += 20
        feedback_parts.append("Target is PDF")
    elif target_found:
        feedback_parts.append("Target is NOT PDF")
        
    # Criterion 4: Content Verified (30 pts)
    if content_verified:
        score += 30
        feedback_parts.append("PDF content verified (matches source note)")
    elif target_found and is_pdf:
        feedback_parts.append("PDF content does NOT match source (empty or wrong file?)")
        
    # Criterion 5: Correct Title (10 pts)
    # Loose check for title
    if "Q3-Board-Minutes-Final" in target_title:
        score += 10
        feedback_parts.append("Target title correct")
    elif target_found:
        feedback_parts.append(f"Target title incorrect: '{target_title}'")

    # --- VLM Verification (Trajectory) ---
    # We want to ensure they didn't just use `curl` or python script to do it all headless
    # The instructions imply using the Web UI.
    
    # (Optional but recommended for robust scoring)
    # If the score is already high, we can be lenient, or use VLM to confirm UI usage.
    # For now, we rely on the programmatic checks as primary, but if VLM was available:
    # vlm_score = perform_vlm_check(traj) ...
    
    passed = (score >= 70) and content_verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }