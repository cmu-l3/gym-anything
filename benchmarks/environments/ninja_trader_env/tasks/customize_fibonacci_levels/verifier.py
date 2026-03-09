#!/usr/bin/env python3
"""
Verifier for customize_fibonacci_levels task.

Criteria:
1. Workspace modified/Fib tool found (20 pts)
2. 78.6% Level Added (25 pts)
3. 23.6% Level Removed (15 pts)
4. 61.8% Level is Red (20 pts)
5. Chart Instrument is SPY (10 pts)
6. VLM Confirmation (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_fibonacci_levels(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load JSON Result
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
    feedback_parts = []

    # Criterion 1: Fib Tool Found (20 pts)
    if result.get('fib_tool_found', False):
        score += 20
        feedback_parts.append("Fibonacci tool found in workspace (+20)")
    else:
        feedback_parts.append("Fibonacci tool NOT found (0)")

    # Criterion 2: 78.6 Level Added (25 pts)
    if result.get('level_786_found', False):
        score += 25
        feedback_parts.append("Level 78.6% added (+25)")
    else:
        feedback_parts.append("Level 78.6% missing (0)")

    # Criterion 3: 23.6 Level Removed (15 pts)
    if not result.get('level_236_found', False):
        # Only award points if tool was actually found (avoiding empty workspace pass)
        if result.get('fib_tool_found', False):
            score += 15
            feedback_parts.append("Level 23.6% removed (+15)")
    else:
        feedback_parts.append("Level 23.6% still present (0)")

    # Criterion 4: 61.8 Level Color (20 pts)
    color = result.get('level_618_color', 'None')
    if color == 'Red':
        score += 20
        feedback_parts.append("Level 61.8% is Red (+20)")
    else:
        feedback_parts.append(f"Level 61.8% color is {color} (0)")
        
    # Criterion 5: Instrument Check (10 pts)
    inst = result.get('chart_instrument', '')
    if 'SPY' in inst:
        score += 10
        feedback_parts.append("SPY Chart confirmed (+10)")
    else:
        feedback_parts.append(f"Chart instrument mismatch: {inst} (0)")

    # Criterion 6: VLM Verification (10 pts)
    # Check if a chart with lines is visible
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        try:
            prompt = (
                "Analyze this trading chart. "
                "1. Is there a Fibonacci retracement drawing visible (horizontal lines)? "
                "2. Is there a line labeled roughly 0.786 or 78.6? "
                "3. Is there a distinct Red horizontal line? "
                "Reply JSON: {\"lines_visible\": bool, \"label_786\": bool, \"red_line\": bool}"
            )
            vlm_resp = query_vlm(images=[final_screenshot], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('lines_visible'):
                vlm_score += 5
            if parsed.get('red_line'):
                vlm_score += 5
            
            if vlm_score > 0:
                feedback_parts.append(f"Visual verification passed (+{vlm_score})")
                score += vlm_score
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Pass threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }