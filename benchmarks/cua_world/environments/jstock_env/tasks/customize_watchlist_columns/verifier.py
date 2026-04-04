#!/usr/bin/env python3
"""
Verifier for customize_watchlist_columns task.
Uses VLM to inspect the table headers in the final screenshot.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_watchlist_columns(traj, env_info, task_info):
    """
    Verifies that specific columns are hidden/shown in the JStock watchlist.
    
    Primary verification is Visual (VLM) because extracting UI state from 
    serialized Java config files is unreliable and complex.
    
    Criteria:
    1. "Buy", "B.Qty", "Sell", "S.Qty" headers are NOT visible (hidden).
    2. "High", "Low" headers ARE visible.
    3. Config file was modified (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Load Result JSON & Check Config
    # ================================================================
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
    
    # Check config modification (20 points)
    if result.get('config_modified', False):
        score += 20
        feedback_parts.append("Settings saved (config modified)")
    else:
        feedback_parts.append("Settings NOT saved (config not modified)")

    # ================================================================
    # 2. VLM Verification of Table Headers
    # ================================================================
    # We use the final screenshot to check the final state of the table
    final_img = get_final_screenshot(traj)
    
    # We also check trajectory for menu interaction evidence
    frames = sample_trajectory_frames(traj, n=3)
    all_images = frames + [final_img]
    
    # Define columns to check
    # Note: JStock might use "Buy Qty" or "B.Qty" depending on version/width
    hidden_cols = ["Buy", "B.Qty", "Sell", "S.Qty"]
    visible_cols = ["High", "Low"]
    
    prompt = f"""
    Look at the final screenshot (the last image). It shows a stock market watchlist table.
    I need to verify which columns are visible in the table header.
    
    1. Are the columns "{', '.join(hidden_cols)}" VISIBLE in the header row? (They should be HIDDEN).
       Note: 'B.Qty' might appear as 'Buy Qty', 'S.Qty' as 'Sell Qty'.
    
    2. Are the columns "{', '.join(visible_cols)}" VISIBLE in the header row? (They should be VISIBLE).
    
    3. Look at the previous images. Did the user open a context menu on the table header or a 'View' menu?
    
    Return a JSON object with strictly this format:
    {{
      "buy_column_visible": boolean,
      "b_qty_column_visible": boolean,
      "sell_column_visible": boolean,
      "s_qty_column_visible": boolean,
      "high_column_visible": boolean,
      "low_column_visible": boolean,
      "menu_interaction_observed": boolean
    }}
    """
    
    parsed = {}
    hidden_visibility = []
    try:
        vlm_resp = query_vlm(images=all_images, prompt=prompt)
        parsed = vlm_resp.get("parsed", {}) if isinstance(vlm_resp, dict) else {}

        hidden_visibility = [
            parsed.get("buy_column_visible"),
            parsed.get("b_qty_column_visible"),
            parsed.get("sell_column_visible"),
            parsed.get("s_qty_column_visible"),
        ]
        hidden_correct = sum(value is False for value in hidden_visibility)
        score += hidden_correct * 10
        if hidden_correct == 4:
            feedback_parts.append("Hidden columns are all absent from the header.")
        else:
            feedback_parts.append(f"Only {hidden_correct}/4 hidden-column checks passed.")

        visible_correct = 0
        if parsed.get("high_column_visible"):
            visible_correct += 1
        if parsed.get("low_column_visible"):
            visible_correct += 1
        score += visible_correct * 10
        if visible_correct == 2:
            feedback_parts.append("Required High and Low columns are visible.")
        else:
            feedback_parts.append(f"Only {visible_correct}/2 required visible columns were confirmed.")

        if parsed.get("menu_interaction_observed"):
            score += 20
            feedback_parts.append("VLM observed a header/context-menu customization workflow.")
        else:
            feedback_parts.append("VLM did not clearly observe the customization workflow.")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed.")

    passed = (
        score >= 70
        and parsed.get("high_column_visible")
        and parsed.get("low_column_visible")
        and all(value is False for value in hidden_visibility)
    )
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
