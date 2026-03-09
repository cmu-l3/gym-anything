#!/usr/bin/env python3
"""
Verifier for measure_market_correction task.

Checks:
1. Workspace modified (anti-gaming).
2. Ruler object exists.
3. Ruler coordinates align with July 2023 High (~460) and Oct 2023 Low (~410).
4. Text object "Summer Correction" exists.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for SPY 2023 Correction
JULY_HIGH_PRICE_MIN = 450.0
JULY_HIGH_PRICE_MAX = 465.0  # Peak was ~460
OCT_LOW_PRICE_MIN = 405.0
OCT_LOW_PRICE_MAX = 420.0    # Bottom was ~410

# NinjaTrader XML times can be standard ISO or weird. 
# We'll rely on string matching in export or raw data.
# The export script dumps all found prices/times in the workspace if it finds a Ruler.

def verify_measure_market_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', "Summer Correction")

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\measure_market_correction_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Workspace Modified (10 pts)
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # 2. Chart Detected (10 pts)
    if result.get('has_chart', False):
        score += 10
        feedback_parts.append("SPY Chart detected (+10)")
    else:
        feedback_parts.append("SPY Chart NOT detected (0)")

    # 3. Ruler Existence (20 pts)
    has_ruler = result.get('has_ruler', False)
    if has_ruler:
        score += 20
        feedback_parts.append("Ruler tool used (+20)")
    else:
        feedback_parts.append("Ruler tool NOT found (0)")

    # 4. Ruler Coordinates Verification (40 pts)
    # We check if ANY of the extracted prices match our expected High/Low
    ruler_data = result.get('ruler_data', {})
    all_prices = [float(p) for p in ruler_data.get('AllPrices', []) if p]
    
    found_high = False
    found_low = False
    
    for p in all_prices:
        if JULY_HIGH_PRICE_MIN <= p <= JULY_HIGH_PRICE_MAX:
            found_high = True
        if OCT_LOW_PRICE_MIN <= p <= OCT_LOW_PRICE_MAX:
            found_low = True
            
    if has_ruler:
        if found_high:
            score += 20
            feedback_parts.append("Ruler anchored at July High (+20)")
        else:
            feedback_parts.append("Ruler start point incorrect (High not matched)")
            
        if found_low:
            score += 20
            feedback_parts.append("Ruler anchored at Oct Low (+20)")
        else:
            feedback_parts.append("Ruler end point incorrect (Low not matched)")

    # 5. Text Label (20 pts)
    has_text = result.get('has_text', False)
    text_content = result.get('text_content', "")
    
    if has_text and expected_text.lower() in text_content.lower():
        score += 20
        feedback_parts.append(f"Label '{expected_text}' found (+20)")
    elif has_text:
        score += 10
        feedback_parts.append(f"Text object found but content mismatch '{text_content}' (+10)")
    else:
        feedback_parts.append("Text label NOT found (0)")

    # Final Pass Check
    # Must have Ruler, matched at least one point, and saved workspace
    passed = score >= 70 and has_ruler and (found_high or found_low)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }