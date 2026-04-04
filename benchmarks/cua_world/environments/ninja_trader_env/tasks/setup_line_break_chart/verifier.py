#!/usr/bin/env python3
"""
Verifier for setup_line_break_chart task in NinjaTrader.

Scoring Criteria:
1. Workspace saved (15 pts) - Anti-gaming: must be modified during task
2. Line Break Chart Type (25 pts) - CRITICAL GATE
3. Line Count = 3 (10 pts)
4. AAPL Instrument (15 pts)
5. SMA(20) Indicator (15 pts)
6. RSI(14) Indicator (15 pts)
7. VLM Visual Verification (5 pts)

Total: 100 pts
Pass Threshold: 70 pts (and Line Break Type must be correct)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_PATH_IN_CONTAINER = r"C:\Users\Docker\Desktop\NinjaTraderTasks\setup_line_break_chart_result.json"

def verify_setup_line_break_chart(traj, env_info, task_info):
    """
    Verify the Line Break chart setup using programmatic file checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Programmatic Verification (Workspace XML)
    # ================================================================
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_IN_CONTAINER, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file not found. Did you save the workspace?"
        }
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error parsing result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Workspace Modification (15 pts)
    if result.get('workspace_modified', False):
        score += 15
        feedback.append("Workspace saved successfully (+15)")
    else:
        feedback.append("Workspace NOT saved (0)")
        # Critical failure: if not saved, nothing to check
        return {"passed": False, "score": 0, "feedback": "Workspace was not saved. Cannot verify configuration."}

    # 2. AAPL Instrument (15 pts)
    if result.get('found_aapl', False):
        score += 15
        feedback.append("Instrument AAPL found (+15)")
    else:
        feedback.append("Instrument AAPL NOT found (0)")

    # 3. Line Break Chart Type (25 pts) - GATED
    chart_type_correct = result.get('found_line_break', False)
    if chart_type_correct:
        score += 25
        feedback.append("Line Break chart type confirmed (+25)")
    else:
        feedback.append("Line Break chart type NOT found (0)")

    # 4. Line Count = 3 (10 pts)
    if result.get('found_line_count_3', False):
        score += 10
        feedback.append("Line count set to 3 (+10)")
    else:
        if chart_type_correct:
            feedback.append("Line count is NOT 3 (0)")
        else:
            feedback.append("Line count check skipped (wrong chart type)")

    # 5. SMA(20) (15 pts)
    if result.get('found_sma_20', False):
        score += 15
        feedback.append("SMA(20) found (+15)")
    else:
        feedback.append("SMA(20) NOT found (0)")

    # 6. RSI(14) (15 pts)
    if result.get('found_rsi_14', False):
        score += 15
        feedback.append("RSI(14) found (+15)")
    else:
        feedback.append("RSI(14) NOT found (0)")

    # ================================================================
    # 2. VLM Verification (Visual Check) (5 pts + Confidence Check)
    # ================================================================
    
    # Only perform VLM check if we have a reasonable programmatic score
    # to confirm visual rendering
    vlm_score = 0
    if score >= 40:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a NinjaTrader task. The user was supposed to create a 3-Line Break chart for AAPL.
        
        Look at the images. A Line Break chart looks like a series of vertical rectangular blocks (often alternating colors like green/red or black/white) that vary in height but always connect to the previous block's close. They look different from standard candlesticks because they often lack wicks and have a distinct 'blocky' appearance.
        
        Answer these questions JSON format:
        1. Is a trading chart visible?
        2. Does the chart look like a Line Break chart (blocky, no wicks) rather than standard candlesticks?
        3. Can you see indicators (lines overlaid on price or panels below)?
        4. Is the instrument AAPL visible?
        
        {
            "chart_visible": true/false,
            "looks_like_line_break": true/false,
            "indicators_visible": true/false,
            "aapl_visible": true/false
        }
        """
        
        try:
            vlm_response = query_vlm(
                images=frames + [final_screen],
                prompt=prompt
            )
            
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('chart_visible', False) and parsed.get('looks_like_line_break', False):
                vlm_score = 5
                feedback.append("Visual verification: Line Break chart confirmed (+5)")
            elif parsed.get('chart_visible', False):
                # Penalty if it looks like candlesticks but programmatic said line break?
                # For now just don't award the 5 pts
                feedback.append("Visual verification: Chart visible but Line Break appearance unclear")
            else:
                feedback.append("Visual verification: Chart not clearly visible")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback.append("VLM check skipped due to error")
    
    score += vlm_score

    # Final logic
    # If the chart type is wrong, cap the score (Gate)
    if not chart_type_correct and score > 45:
        score = 45
        feedback.append("SCORE CAPPED: Correct chart type (Line Break) is required to pass.")

    passed = (score >= 70) and chart_type_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }