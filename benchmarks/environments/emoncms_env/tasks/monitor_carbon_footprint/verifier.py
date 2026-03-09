#!/usr/bin/env python3
import json
import os
import re

def verify_carbon_footprint(traj, env_info, task_info):
    """
    Verifies the carbon footprint monitoring task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result
    if os.path.exists("task_result.json"):
        os.remove("task_result.json")
    
    try:
        copy_from_env("/tmp/task_result.json", "task_result.json")
        with open("task_result.json", "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}

    score = 0
    feedback = []
    
    # 1. Verify Feed Creation (20 pts)
    if result.get("feed_exists"):
        score += 20
        feedback.append("Feed 'current_carbon_intensity' created.")
    else:
        feedback.append("Feed 'current_carbon_intensity' NOT found.")

    # 2. Verify Input Processing Logic (40 pts total)
    # Process list string looks like: "2:0.001,2:0.475,1:18"
    # 2 is the ID for 'x' (multiply), 1 is 'Log to feed'
    process_list = result.get("process_list", "")
    
    # Check for Scaling (W -> kW)
    # Accept 0.001 or 1/1000 logic
    has_scale = False
    if "2:0.001" in process_list: 
        has_scale = True
    
    if has_scale:
        score += 20
        feedback.append("Power scaling (x0.001) configured correctly.")
    else:
        feedback.append("Missing or incorrect power scaling (expected x0.001).")

    # Check for Carbon Factor
    has_factor = False
    if "2:0.475" in process_list:
        has_factor = True
    
    if has_factor:
        score += 20
        feedback.append("Carbon factor (x0.475) configured correctly.")
    else:
        feedback.append("Missing or incorrect carbon factor (expected x0.475).")
        
    # Check if Log to Feed is present (implied by feed existence, but check chain)
    # Pattern: 1:<feed_id>
    if re.search(r"1:\d+", process_list):
        feedback.append("Log to feed process found.")
    else:
        feedback.append("Log to feed process missing from chain.")

    # 3. Verify Dashboard (30 pts total)
    if result.get("dashboard_exists"):
        score += 15
        feedback.append("Dashboard 'Sustainability_Display' created.")
        
        # Check content for Dial/Gauge
        content = result.get("dashboard_content", [])
        # Content is a list of widgets objects
        has_dial = False
        linked_correctly = False
        
        # Emoncms stores content as a list of dicts. 
        # Widget type 4 is Dial, 1 is Dial, 6 is Cylinder... name varies.
        # We look for "type":"dial" or similar in the json string representation or object
        content_str = json.dumps(content).lower()
        
        if "dial" in content_str or "gauge" in content_str:
            has_dial = True
            
        if has_dial:
            score += 15
            feedback.append("Dial/Gauge widget found on dashboard.")
        else:
            feedback.append("No Dial/Gauge widget found on dashboard.")
            
    else:
        feedback.append("Dashboard 'Sustainability_Display' NOT found.")

    # 4. Verify Data Flow (10 pts)
    if result.get("feed_has_data"):
        score += 10
        feedback.append("Feed is receiving data.")
    else:
        feedback.append("Feed has no data.")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }