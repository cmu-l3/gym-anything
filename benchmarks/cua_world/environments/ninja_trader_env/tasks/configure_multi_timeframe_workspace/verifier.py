#!/usr/bin/env python3
"""
Verifier for configure_multi_timeframe_workspace task.

Verifies:
1. Workspace was modified/saved during task execution (Anti-gaming)
2. Instrument SPY is present in chart configurations
3. Three distinct timeframes (Daily, Weekly, Monthly) are configured
4. Three required indicators (RSI, MACD, SMA) are present

Scoring:
- Workspace Modified: 10 pts
- SPY Present: 10 pts
- Daily Timeframe: 15 pts
- Weekly Timeframe: 15 pts
- Monthly Timeframe: 15 pts
- RSI Present: 12 pts
- MACD Present: 12 pts
- SMA Present: 11 pts
TOTAL: 100 pts
"""

import json
import tempfile
import os
import logging
import sys

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_multi_timeframe_workspace(traj, env_info, task_info):
    """
    Verify the NinjaTrader multi-timeframe workspace task.
    """
    # 1. Setup - Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Critical: copy_from_env function not available in environment info."
        }
    
    # 2. Retrieve Result JSON from Container
    # Path inside windows container (as defined in export_result.ps1)
    remote_path = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\configure_multi_timeframe_workspace_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file not found. Did the agent run the export script? (NinjaTraderTasks/configure_multi_timeframe_workspace_result.json missing)"
        }
    except json.JSONDecodeError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file is not valid JSON."
        }
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error retrieving verification data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: Workspace Modified (10 pts)
    # This proves the agent actually saved their work during the session
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("[Success] Workspace saved/modified (+10)")
    else:
        feedback_parts.append("[Fail] Workspace NOT saved or modified (0)")
        # Critical failure: If workspace wasn't saved, we can't verify anything else reliably
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task Failed: You did not save the workspace (File > Save Workspace), so your changes could not be verified."
        }

    # Criterion 2: Instrument SPY (10 pts)
    if result.get('found_spy', False):
        score += 10
        feedback_parts.append("[Success] SPY instrument found (+10)")
    else:
        feedback_parts.append("[Fail] SPY instrument NOT found in workspace (0)")

    # Criterion 3: Timeframes (45 pts total)
    timeframes_found = []
    if result.get('found_day', False):
        score += 15
        timeframes_found.append("Daily")
    if result.get('found_week', False):
        score += 15
        timeframes_found.append("Weekly")
    if result.get('found_month', False):
        score += 15
        timeframes_found.append("Monthly")
    
    if timeframes_found:
        feedback_parts.append(f"[Success] Timeframes found: {', '.join(timeframes_found)} (+{len(timeframes_found)*15})")
    else:
        feedback_parts.append("[Fail] No correct timeframes (Day/Week/Month) detected (0)")

    # Criterion 4: Indicators (35 pts total)
    indicators_found = []
    if result.get('found_rsi', False):
        score += 12
        indicators_found.append("RSI")
    if result.get('found_macd', False):
        score += 12
        indicators_found.append("MACD")
    if result.get('found_sma', False):
        score += 11
        indicators_found.append("SMA")
        
    if indicators_found:
        feedback_parts.append(f"[Success] Indicators found: {', '.join(indicators_found)} (+{len(indicators_found)*11 + (1 if len(indicators_found)==3 else 0)})") # rough adjustment for score math
    else:
        feedback_parts.append("[Fail] No required indicators found (0)")

    # 4. Final Verdict
    # Pass threshold: 70 points
    passed = score >= 70
    
    feedback_str = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str,
        "details": result
    }