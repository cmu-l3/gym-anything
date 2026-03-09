#!/usr/bin/env python3
"""
Verifier for configure_synchronized_chart_dashboard task.

Evaluates:
1. Workspace modified (10 pts)
2. 3 Charts created (SPY, AAPL, MSFT) (15 pts)
3. Interval Linking set to Green on all (30 pts)
4. Global Crosshair set on all (25 pts)
5. Timeframe set to 60 Minute on all (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_synchronized_chart_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside the container (Windows path mapped to generic usually, but here we used exact path in script)
        # Note: 'copy_from_env' handles the container file system access.
        # The script `export_result.ps1` saved to C:\Users\Docker\Desktop\NinjaTraderTasks\result.json
        # We need to access that path. 
        container_path = "C:/Users/Docker/Desktop/NinjaTraderTasks/result.json"
        
        copy_from_env(container_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Workspace Modified (10 pts)
    if result.get('workspace_modified', False):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Analyze Charts
    charts = result.get('charts', [])
    target_instruments = ['SPY', 'AAPL', 'MSFT']
    found_instruments = [c.get('instrument') for c in charts]
    
    # Criterion 2: 3 Charts Created (15 pts)
    instruments_present = 0
    for instr in target_instruments:
        if any(instr in (c.get('instrument') or "") for c in charts):
            instruments_present += 1
            
    if instruments_present == 3:
        score += 15
        feedback_parts.append("All 3 instruments found (+15)")
    elif instruments_present > 0:
        partial = instruments_present * 5
        score += partial
        feedback_parts.append(f"{instruments_present}/3 instruments found (+{partial})")
    else:
        feedback_parts.append("No required instruments found (0)")

    # If no relevant charts, stop here
    relevant_charts = [c for c in charts if c.get('instrument') in target_instruments]
    if not relevant_charts:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Interval Linking (30 pts)
    # Expect "Green"
    # NinjaTrader XML usually stores "Green" or a localized string. We accept "Green".
    linked_count = 0
    for c in relevant_charts:
        link = c.get('link_interval', '')
        if link and 'Green' in str(link):
            linked_count += 1
            
    if linked_count == 3:
        score += 30
        feedback_parts.append("All charts Interval Linked (Green) (+30)")
    elif linked_count > 0:
        partial = linked_count * 10
        score += partial
        feedback_parts.append(f"{linked_count}/3 charts Linked (+{partial})")
    else:
        feedback_parts.append("Interval linking missing/wrong color (0)")

    # Criterion 4: Global Crosshair (25 pts)
    crosshair_count = 0
    for c in relevant_charts:
        ch = c.get('crosshair_type', '')
        if ch and 'Global' in str(ch):
            crosshair_count += 1
            
    if crosshair_count == 3:
        score += 25
        feedback_parts.append("All charts Global Crosshair (+25)")
    elif crosshair_count > 0:
        partial = crosshair_count * 8
        score += int(partial)
        feedback_parts.append(f"{crosshair_count}/3 Global Crosshair (+{int(partial)})")
    else:
        feedback_parts.append("Global Crosshair missing (0)")

    # Criterion 5: Timeframe 60 Minute (20 pts)
    timeframe_count = 0
    for c in relevant_charts:
        val = c.get('period_value', 0)
        ptype = c.get('period_type', '')
        
        # XML might store type as "Minute" or "0" (enum). 
        # Checking for value 60 and type containing "Minute"
        if val == 60 and 'Minute' in str(ptype):
            timeframe_count += 1
            
    if timeframe_count == 3:
        score += 20
        feedback_parts.append("All charts 60 Minute (+20)")
    elif timeframe_count > 0:
        partial = timeframe_count * 6
        score += int(partial)
        feedback_parts.append(f"{timeframe_count}/3 charts 60m (+{int(partial)})")
    else:
        feedback_parts.append("Timeframe incorrect (0)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }