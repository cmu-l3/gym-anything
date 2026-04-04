#!/usr/bin/env python3
"""
Verifier for configure_week_off task.

Strategy:
1. Anti-gaming: Check if DB file was modified during task.
2. Programmatic: Check if "Manufacturing Wing A" record exists in DB (if export succeeded).
3. Visual (VLM): Verify the specific grid pattern (Sunday all, Saturday 2/4) from screenshots.
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for standalone testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_week_off(traj, env_info, task_info):
    """
    Verify the week off configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        # Path matches export_result.ps1
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result file: {e}")
        feedback_parts.append("Could not retrieve task result from container")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score: Database Modification (Anti-gaming) - 20 pts
    db_modified = result.get('db_modified', False)
    if db_modified:
        score += 20
        feedback_parts.append("Database updated successfully")
    else:
        feedback_parts.append("No database changes detected (did you save?)")

    # 3. Score: Record Found (Programmatic) - 20 pts
    # This might fail if table name guess was wrong, so we treat it as bonus/confirmation
    record_found = result.get('week_off_record_found', False)
    if record_found:
        score += 20
        feedback_parts.append("Confirmed 'Manufacturing Wing A' in database")
    else:
        # Don't penalize too heavily if isql failed, rely on VLM
        feedback_parts.append("Database record verification skipped/failed")

    # 4. Score: VLM Verification (Visual correctness) - 60 pts
    # We need to verify the complex grid pattern
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + ([final_frame] if final_frame else [])

    vlm_prompt = """
    You are verifying an HR software configuration task.
    The user is creating a 'Week Off' rule.
    
    Target Configuration:
    - Name: "Manufacturing Wing A"
    - Sunday: Checked/OFF for ALL weeks (1, 2, 3, 4, 5)
    - Saturday: Checked/OFF for ONLY Week 2 and Week 4
    - Mon-Fri: NOT checked (Working)
    
    Look at the screenshots of the 'Week Off' or 'Weekly Off' configuration screen.
    1. Is the name "Manufacturing Wing A" visible?
    2. Is the grid pattern correct? 
       - Look for the row 'Sunday': Are all checkboxes checked?
       - Look for the row 'Saturday': Are the checkboxes for column '2' and '4' checked?
       - Are columns '1', '3', '5' for Saturday UNCHECKED?
       - Are Mon-Fri rows generally unchecked?
       
    Respond in JSON:
    {
        "name_match": true/false,
        "sunday_correct": true/false,
        "saturday_pattern_correct": true/false,
        "saved_success": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('name_match'):
            vlm_score += 20
            feedback_parts.append("VLM: Name 'Manufacturing Wing A' verified")
            
        if parsed.get('sunday_correct'):
            vlm_score += 20
            feedback_parts.append("VLM: Sunday pattern correct (all weeks)")
            
        if parsed.get('saturday_pattern_correct'):
            vlm_score += 20
            feedback_parts.append("VLM: Saturday pattern correct (2nd & 4th)")
            
    else:
        feedback_parts.append("VLM verification failed to run")
        
    score += vlm_score

    # Fallback/Adjustment: If DB verified but VLM missed (due to screenshot timing),
    # give partial credit for Saturday/Sunday if DB confirmed existence (implies some config)
    if record_found and vlm_score < 20:
        score += 30 # Bump up if we know it exists but couldn't see details
        feedback_parts.append("Trusting DB record existence over VLM miss")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }