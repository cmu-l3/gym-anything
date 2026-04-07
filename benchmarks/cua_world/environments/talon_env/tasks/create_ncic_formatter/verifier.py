#!/usr/bin/env python3
"""
Verifier for create_ncic_formatter task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Files exist in the correct locations (10 points)
2. Lists mapped properly and passed Python unit tests (30 points)
3. Weight formatting Python function works perfectly (15 points)
4. Height formatting Python function works perfectly (20 points)
5. Talon grammar looks structurally valid (10 points)
6. VLM Trajectory Check: Verify agent was actively coding (15 points)

Pass threshold: 85%
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's trajectory for a coding task on Windows.
The agent was asked to write Python and Talon scripts to format NCIC criminal data.

Look at the provided trajectory frames (which track the desktop over time):
1. Can you see a code editor (like Notepad, VS Code, etc.) being used?
2. Is the agent writing or editing Python code (`.py`) and Talon script code (`.talon`)?
3. Does it look like actual work was performed rather than just staring at an empty desktop?

Respond strictly in valid JSON format:
{
    "used_editor": true/false,
    "edited_code": true/false,
    "active_work_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_create_ncic_formatter(traj, env_info, task_info):
    """Verify the NCIC formatter system using exported unit tests and VLM."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    feedback_parts = []
    score = 0

    # 1. READ EXPORTED JSON RESULT
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. EVALUATE PROGRAMMATIC CRITERIA
    
    # Module Structure (10 pts)
    if result.get('module_dir_exists') and result.get('actions_file_exists') and result.get('commands_file_exists'):
        score += 10
        feedback_parts.append("✅ Module directory and files created")
    else:
        feedback_parts.append("❌ Missing required files or directory")

    # List Mappings (30 pts)
    if result.get('eye_color_mapped') and result.get('hair_color_mapped'):
        score += 30
        feedback_parts.append("✅ Eye and Hair colors successfully mapped to NCIC codes")
    elif result.get('eye_color_mapped') or result.get('hair_color_mapped'):
        score += 15
        feedback_parts.append("⚠️ Only one of the lists (Eye or Hair) was correctly mapped")
    else:
        feedback_parts.append(f"❌ List mappings failed. (Error: {result.get('list_error')})")

    # Weight Action (15 pts)
    if result.get('weight_test_passed'):
        score += 15
        feedback_parts.append("✅ `ncic_format_weight` strictly formats weights (padded to 3 chars)")
    else:
        feedback_parts.append("❌ `ncic_format_weight` failed unit tests (check padding logic)")

    # Height Action (20 pts)
    if result.get('height_test_passed'):
        score += 20
        feedback_parts.append("✅ `ncic_format_height` strictly formats heights (feet + padded inches)")
    else:
        feedback_parts.append(f"❌ `ncic_format_height` failed unit tests. (Error: {result.get('action_error')})")

    # Command Syntax (10 pts)
    if result.get('commands_syntax_valid'):
        score += 10
        feedback_parts.append("✅ `.talon` grammar file structurally valid")
    else:
        feedback_parts.append("❌ `.talon` grammar file missing required command definitions")

    # 3. VLM TRAJECTORY VERIFICATION (15 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=images)
            
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('used_editor') and parsed.get('edited_code'):
                    score += 15
                    feedback_parts.append("✅ VLM confirmed visual code editing workflow")
                else:
                    feedback_parts.append("❌ VLM did not observe active coding work (anti-gaming)")
            else:
                feedback_parts.append("⚠️ VLM query failed, skipped visual check")

    # Final Pass Condition
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }