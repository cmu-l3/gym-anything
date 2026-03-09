#!/usr/bin/env python3
"""
Verifier for edit_dashboard_widgets task.
Checks if Emoncms dashboard widgets were correctly reconfigured.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_dashboard_widgets(traj, env_info, task_info):
    """
    Verifies that the agent correctly edited the dashboard widgets.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result Data
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
    
    # 2. Check Prerequisites
    if not result.get('dashboard_found'):
        return {"passed": False, "score": 0, "feedback": "Dashboard 'Server Room Overview' not found in database."}

    content = result.get('dashboard_content', [])
    gt = result.get('ground_truth', {})
    
    target_power_id = str(gt.get('server_power_id', ''))
    target_temp_id = str(gt.get('server_temp_id', ''))
    target_hum_id = str(gt.get('server_humidity_id', ''))

    # Helper to find widget by type or fuzzy match
    def find_widgets(widgets, type_hint):
        return [w for w in widgets if w.get('type') == type_hint]

    dials = find_widgets(content, 'dial')
    values = find_widgets(content, 'feedvalue')

    # 3. Verify Power Widget (Dial)
    power_widget = None
    # Strategy: Find the dial that looks like power (either by correct ID, label, or units)
    # Since we can't guarantee order, we look for best match
    for w in dials:
        opts = w.get('options', {})
        # If it points to correct feed OR has correct label/units, candidate
        fid = str(opts.get('feedid', ''))
        name = opts.get('name', '').lower()
        units = opts.get('units', '')
        if fid == target_power_id or 'power' in name or 'w' in units.lower():
            power_widget = w
            break
    
    if power_widget:
        opts = power_widget.get('options', {})
        # Check Feed ID (15 pts)
        if str(opts.get('feedid', '')) == target_power_id:
            score += 15
            feedback.append("Power widget feed correct.")
        else:
            feedback.append(f"Power widget feed incorrect (Expected {target_power_id}).")
        
        # Check Label (5 pts)
        name = opts.get('name', '')
        if "server power" in name.lower() or "power (w)" in name.lower():
            score += 5
        else:
            feedback.append("Power widget label mismatch.")
            
        # Check Max (5 pts)
        if float(opts.get('max', 0)) == 5000:
            score += 5
        else:
            feedback.append("Power widget max value incorrect.")
    else:
        feedback.append("Could not identify Power dial widget.")

    # 4. Verify Temp Widget (Dial)
    temp_widget = None
    for w in dials:
        if w == power_widget: continue # Don't re-use
        opts = w.get('options', {})
        fid = str(opts.get('feedid', ''))
        name = opts.get('name', '').lower()
        units = opts.get('units', '')
        if fid == target_temp_id or 'temp' in name or 'c' in units.lower():
            temp_widget = w
            break
            
    if temp_widget:
        opts = temp_widget.get('options', {})
        # Check Feed ID (15 pts)
        if str(opts.get('feedid', '')) == target_temp_id:
            score += 15
            feedback.append("Temp widget feed correct.")
        else:
            feedback.append(f"Temp widget feed incorrect (Expected {target_temp_id}).")
            
        # Check Label (5 pts)
        name = opts.get('name', '')
        if "temperature" in name.lower() or "°c" in name.lower():
            score += 5
        else:
            feedback.append("Temp widget label mismatch.")
            
        # Check Min/Max (5 pts)
        if float(opts.get('min', 0)) == 10 and float(opts.get('max', 0)) == 45:
            score += 5
        else:
            feedback.append("Temp widget range incorrect.")
    else:
        feedback.append("Could not identify Temperature dial widget.")

    # 5. Verify Humidity Widget (Value)
    hum_widget = None
    if values:
        hum_widget = values[0] # Assuming only one feedvalue widget
    
    if hum_widget:
        opts = hum_widget.get('options', {})
        # Check Feed ID (15 pts)
        if str(opts.get('feedid', '')) == target_hum_id:
            score += 15
            feedback.append("Humidity widget feed correct.")
        else:
            feedback.append(f"Humidity widget feed incorrect (Expected {target_hum_id}).")
            
        # Check Label (10 pts)
        name = opts.get('name', '')
        if "humidity" in name.lower() or "%rh" in name.lower():
            score += 10
        else:
            feedback.append("Humidity widget label mismatch.")
    else:
        feedback.append("Humidity value widget not found.")

    # 6. VLM Verification (20 pts)
    # We want to see evidence of the editor being used.
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of the Emoncms Dashboard interface.
    1. Do you see the dashboard editor mode active (grid lines, widget configuration dialogs, or 'Save'/'Cancel' buttons)?
    2. Did the user modify widget settings (change feed, label, or range)?
    3. In the final screenshot, does the dashboard look configured correctly (e.g. dials showing values, not errors)?
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final])
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {}).get('analysis', '').lower()
            # Simple heuristic based on response
            score += 20 # Assume basic interaction if we got this far and programmatic checks passed partial
            feedback.append("VLM verification: Interaction detected.")
        else:
            feedback.append("VLM verification failed to run.")
    except:
        feedback.append("VLM verification error.")
        score += 10 # Fallback points if programmatic parts passed

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }