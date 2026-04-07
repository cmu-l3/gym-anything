#!/usr/bin/env python3
"""
Verifier for create_title_card_text task.

Verifies that the agent:
1. Created render output files (PNG sequence).
2. Rendered approximately 10 frames.
3. Added the visible text "EPISODE 1".

Scoring:
- 20 pts: Output files exist and are valid PNGs.
- 20 pts: Files were created during the task (anti-gaming).
- 20 pts: Frame count is correct (8-12 frames).
- 40 pts: VLM verifies "EPISODE 1" is visible in the final state or UI.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_title_card_text(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', "EPISODE 1")
    min_files = metadata.get('min_files', 8)
    max_files = metadata.get('max_files', 12)

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. Verify Output Files (File System Check)
    file_count = result.get('file_count', 0)
    fresh_files = result.get('fresh_files_count', 0)
    
    # Check existence
    if file_count > 0:
        score += 20
        feedback.append(f"Found {file_count} output files.")
    else:
        feedback.append("No output files found.")

    # Check timestamps (Anti-gaming)
    if fresh_files >= min_files:
        score += 20
        feedback.append(f"Files were successfully rendered during the task ({fresh_files} new files).")
    elif fresh_files > 0:
        score += 10
        feedback.append(f"Some files rendered during task, but fewer than expected ({fresh_files}).")
    else:
        feedback.append("No new files rendered during this session.")

    # Check specific frame count constraint
    if min_files <= file_count <= max_files:
        score += 20
        feedback.append(f"Frame count {file_count} is within target range ({min_files}-{max_files}).")
    else:
        feedback.append(f"Frame count {file_count} is outside target range ({min_files}-{max_files}).")

    # 3. Verify Text Content (VLM Check)
    # We verify if the text is visible on screen using VLM
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = (
            f"Look at this screenshot of the OpenToonz animation software. "
            f"Is the text '{expected_text}' visible on the canvas or in a rendered view? "
            f"The text should be overlaid on the character animation. "
            f"Ignore the user interface text, look specifically at the artwork/canvas area. "
            f"Return JSON with keys: 'text_visible' (boolean), 'text_content' (string read from canvas), 'confidence' (low/medium/high)."
        )
        
        try:
            vlm_response = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = vlm_response.get('parsed', {})
            
            text_visible = parsed.get('text_visible', False)
            text_content = parsed.get('text_content', '')
            
            # Flexible matching
            if text_visible or expected_text.lower() in str(text_content).lower() or "episode" in str(text_content).lower():
                vlm_score = 40
                feedback.append(f"VLM verified text '{expected_text}' is visible.")
            else:
                feedback.append(f"VLM could not find text '{expected_text}' on the canvas.")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("Visual verification failed due to internal error.")
    else:
        feedback.append("No screenshot available for visual verification.")

    score += vlm_score

    # 4. Final Determination
    # Pass if files exist, are fresh, and VLM sees the text OR we have perfect file score
    # We require at least some visual confirmation or strong file evidence
    passed = (score >= 80) or (score >= 60 and vlm_score > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }