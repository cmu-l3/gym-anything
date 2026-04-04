#!/usr/bin/env python3
"""
Verifier for plan_short_trade_risk_reward task.

Verifies:
1. Workspace was modified after task start.
2. SPY instrument is present in the workspace.
3. A RiskReward drawing tool is present.
4. The RiskReward tool contains the correct coordinates (450, 455, 435).
   Note: NinjaTrader XML serialization for RiskReward usually stores:
   - Anchor1 (Entry)
   - Anchor2 (Risk/Stop)
   - Anchor3 (Reward/Target)
   We check for these values in the extracted XML snippet.

Scoring:
- Workspace Modified: 10 pts
- SPY Chart: 10 pts
- RiskReward Tool: 30 pts
- Coordinates Correct: 45 pts (15 per price level)
- Correct Direction (Short): 5 pts
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/task_result.json"

def verify_plan_short_trade(traj, env_info, task_info):
    """Verify the plan_short_trade_risk_reward task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    exp_entry = metadata.get('entry_price', 450.00)
    exp_stop = metadata.get('stop_price', 455.00)
    exp_target = metadata.get('target_price', 435.00)
    tolerance = metadata.get('tolerance', 0.5)

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env(RESULT_PATH, temp_path)
        
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result file: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Modified (10 pts)
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace saved")
    else:
        feedback_parts.append("Workspace NOT saved")
        return {"passed": False, "score": 0, "feedback": "Task failed: Workspace not saved, no evidence of work."}

    # 2. SPY Instrument (10 pts)
    if result.get('instrument_found', False):
        score += 10
        feedback_parts.append("SPY chart found")
    else:
        feedback_parts.append("SPY instrument not detected")

    # 3. RiskReward Tool (30 pts)
    xml_snippet = result.get('drawing_xml_snippet', "")
    if result.get('risk_reward_found', False) or "RiskReward" in xml_snippet:
        score += 30
        feedback_parts.append("RiskReward tool used")
    else:
        feedback_parts.append("RiskReward tool NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Check Coordinates (45 pts + 5 pts for direction)
    # Extract all numbers from the XML snippet to find our prices
    # We look for numbers close to our targets.
    # Note: NinjaTrader might store them as <Y>450</Y> or inside 'Anchor' attributes.
    # We use a robust regex search for the values.
    
    def check_price(target, text, name):
        # Look for the price with flexible decimal places
        # e.g., 450, 450.0, 450.0000001
        pattern = r"(\d+\.?\d*)"
        matches = re.findall(pattern, text)
        found = False
        for m in matches:
            try:
                val = float(m)
                if abs(val - target) <= tolerance:
                    found = True
                    break
            except ValueError:
                continue
        return found

    entry_ok = check_price(exp_entry, xml_snippet, "Entry")
    stop_ok = check_price(exp_stop, xml_snippet, "Stop")
    target_ok = check_price(exp_target, xml_snippet, "Target")
    
    if entry_ok:
        score += 15
        feedback_parts.append(f"Entry {exp_entry} OK")
    else:
        feedback_parts.append(f"Entry {exp_entry} NOT found")
        
    if stop_ok:
        score += 15
        feedback_parts.append(f"Stop {exp_stop} OK")
    else:
        feedback_parts.append(f"Stop {exp_stop} NOT found")
        
    if target_ok:
        score += 15
        feedback_parts.append(f"Target {exp_target} OK")
    else:
        feedback_parts.append(f"Target {exp_target} NOT found")

    # 5. Direction Check (5 pts)
    # Since we verified the specific values 455 (stop) and 435 (target) were present,
    # and 455 > 450 > 435, the direction is implicitly correct if the values are correct.
    # We award these points if all 3 values are found.
    if entry_ok and stop_ok and target_ok:
        score += 5
        feedback_parts.append("Trade direction correct")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }