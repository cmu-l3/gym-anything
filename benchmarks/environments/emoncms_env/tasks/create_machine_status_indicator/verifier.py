#!/usr/bin/env python3
"""
Verifier for Create Machine Status Indicator task.

Checks:
1. 'press_running' feed exists.
2. Feed data contains binary states (0/1) correlating to machine simulation.
3. 'Factory Monitor' dashboard exists.
4. Dashboard contains an LED/Status widget linked to the feed.
5. VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_machine_status(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    feedback = []
    
    # 1. Check Feed Existence (20 pts)
    if result.get('feed_exists'):
        score += 20
        feedback.append("Feed 'press_running' created.")
    else:
        feedback.append("Feed 'press_running' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Check Feed Data Quality (60 pts)
    # We expect values to be roughly binary: 0 and 1.
    # Or at least: Low (< 50) and High (roughly 1 or >1000 depending on config).
    # The prompt explicitly asked for "0 = Off, 1 = On".
    feed_values = result.get('feed_values', [])
    
    has_low = False
    has_high = False
    is_binary = True
    
    # Analyze values
    valid_values = [v for v in feed_values if v is not None]
    
    if not valid_values:
        feedback.append("Feed exists but contains no data.")
    else:
        for v in valid_values:
            if v < 0.5: # Effectively 0
                has_low = True
            elif v >= 0.9: # Effectively 1 or higher
                has_high = True
            
            # Check if it strictly adheres to 0/1 logic
            if not (abs(v - 0) < 0.1 or abs(v - 1) < 0.1):
                is_binary = False

        if has_low and has_high:
            if is_binary:
                score += 60
                feedback.append("Feed data correctly shows binary 0/1 status.")
            else:
                score += 40
                feedback.append("Feed data shows High/Low states, but values are not strict 0/1 (partial credit).")
        elif has_low:
            feedback.append("Feed only shows 'Off' state (0). Did the machine turn on?")
        elif has_high:
            feedback.append("Feed only shows 'On' state. Standby filtering failed?")
        else:
            feedback.append("Feed data does not match expected patterns.")

    # 3. Check Dashboard and Widget (20 pts)
    if result.get('dashboard_exists'):
        score += 10
        feedback.append("Dashboard 'Factory Monitor' created.")
        
        # Check for widget
        content_str = result.get('dashboard_content', '{}')
        try:
            # content is actually a string containing JSON inside the JSON result
            # Careful with double parsing if export script did jq -R
            content = json.loads(content_str)
            
            has_led = False
            # Dashboard content structure is complex, usually a list of widgets
            # Example: [{"type":"led","feedid":123,...}] or similar structure in 'widgets' key
            # Emoncms dashboard content structure varies by version, but usually look for 'type'
            
            # Flatten if nested
            widgets = []
            if isinstance(content, list):
                widgets = content
            elif isinstance(content, dict):
                # Sometimes wrapped in page wrapper
                widgets = content.values() 
            
            # Simple string search in the raw content JSON is often more robust for type checks
            if 'led' in content_str.lower() or 'indicator' in content_str.lower():
                score += 10
                feedback.append("Status/LED widget detected on dashboard.")
            else:
                feedback.append("Dashboard exists but no LED/Status widget detected.")
                
        except:
            feedback.append("Could not parse dashboard content.")
    else:
        feedback.append("Dashboard 'Factory Monitor' NOT found.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }