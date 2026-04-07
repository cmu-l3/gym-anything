#!/usr/bin/env python3
"""
Verifier for noaa_3screen_dashboard task.

Verification Strategy (Multi-Signal):
1. Configuration File Parsing (Primary):
   - Confirms Amateur.mod deletion
   - Verifies Miami_NHC coordinates
   - Validates existence, satellite bindings, QTH assignments, and Layout ID values for 3 distinct modules
   - Regex matching on gpredict.cfg for UTC and ground track properties
2. VLM Trajectory (Anti-Gaming Fallback):
   - Samples frames to ensure the agent actually navigated the Module configuration UI
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_noaa_3screen_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/noaa_3screen_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    modules = result.get('modules', [])
    qths = result.get('qths', [])
    cfg_content = result.get('gpredict_cfg', '')
    
    # 1. Check Amateur.mod deletion (10 pts)
    amateur_deleted = True
    for mod in modules:
        if mod['filename'].lower() == 'amateur.mod':
            amateur_deleted = False
            
    if amateur_deleted:
        score += 10
        feedback_parts.append("Amateur.mod deleted")
    else:
        feedback_parts.append("Amateur.mod NOT deleted")
        
    # 2. Check Miami NHC ground station (10 pts)
    miami_qth_filename = None
    for qth in qths:
        content = qth['content'].lower()
        lat_m = re.search(r'lat\s*=\s*([0-9.-]+)', content)
        lon_m = re.search(r'lon\s*=\s*([0-9.-]+)', content)
        if lat_m and lon_m:
            lat = float(lat_m.group(1))
            lon = float(lon_m.group(1))
            if abs(lat - 25.75) < 0.5 and abs(lon - -80.38) < 0.5:
                miami_qth_filename = qth['filename']
                score += 10
                feedback_parts.append("Miami_NHC ground station created")
                break
                
    if not miami_qth_filename:
        feedback_parts.append("Miami_NHC ground station NOT found")
        
    # 3. Check specialized modules (3 x 15 pts = 45 pts)
    global_wx_pts = 0
    radar_wx_pts = 0
    sched_wx_pts = 0
    
    for mod in modules:
        name = mod['filename'].lower()
        content = mod['content']
        props = {}
        for line in content.split('\n'):
            if '=' in line:
                k, v = line.split('=', 1)
                props[k.strip().upper()] = v.strip()
                
        # Parse satellites
        sats_str = props.get('SATELLITES', '')
        sats = [s for s in sats_str.split(';') if s]
        has_correct_sats = all(str(x) in sats for x in [25338, 28654, 33591])
        
        # Parse ground station binding
        qthfile = props.get('QTHFILE', '')
        bound_to_miami = False
        if miami_qth_filename and qthfile.lower() == miami_qth_filename.lower():
            bound_to_miami = True
            
        # Parse selected layout (0=List, 1=Map, 2=Polar)
        layout = props.get('LAYOUT', '')
        
        mod_score = 0
        if has_correct_sats: mod_score += 5
        if bound_to_miami: mod_score += 5
        
        # Assign best module matching based on naming and layout selection
        if 'global' in name or 'map' in name or layout == '1':
            current_pts = mod_score + (5 if layout == '1' else 0)
            if current_pts > global_wx_pts: global_wx_pts = current_pts
            
        if 'radar' in name or 'polar' in name or layout == '2':
            current_pts = mod_score + (5 if layout == '2' else 0)
            if current_pts > radar_wx_pts: radar_wx_pts = current_pts
            
        if 'schedule' in name or 'list' in name or layout == '0':
            current_pts = mod_score + (5 if layout == '0' else 0)
            if current_pts > sched_wx_pts: sched_wx_pts = current_pts
            
    if global_wx_pts == 15: feedback_parts.append("Global_Wx (Map) correct")
    elif global_wx_pts > 0: feedback_parts.append(f"Global_Wx partial ({global_wx_pts}/15)")
    else: feedback_parts.append("Global_Wx missing/incorrect")
    
    if radar_wx_pts == 15: feedback_parts.append("Radar_Wx (Polar) correct")
    elif radar_wx_pts > 0: feedback_parts.append(f"Radar_Wx partial ({radar_wx_pts}/15)")
    else: feedback_parts.append("Radar_Wx missing/incorrect")
    
    if sched_wx_pts == 15: feedback_parts.append("Schedule_Wx (List) correct")
    elif sched_wx_pts > 0: feedback_parts.append(f"Schedule_Wx partial ({sched_wx_pts}/15)")
    else: feedback_parts.append("Schedule_Wx missing/incorrect")
    
    score += global_wx_pts + radar_wx_pts + sched_wx_pts
    
    # 4. Global Preferences (15 pts)
    pref_score = 0
    if re.search(r'(?i)utc\s*=\s*1', cfg_content):
        pref_score += 7
        feedback_parts.append("UTC enabled")
    else:
        feedback_parts.append("UTC NOT enabled")
        
    if re.search(r'(?i)(?:track|orbit)[^|]*=\s*2', cfg_content):
        pref_score += 8
        feedback_parts.append("Ground track orbits=2 enabled")
    else:
        feedback_parts.append("Ground track orbits NOT set to 2")
        
    score += pref_score
    
    # 5. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots from a session of configuring GPredict satellite tracking software.
        Did the user interact with the Module configuration dialogs to create multiple tracking modules (tabs) and select specific layouts (Map, Polar, List)?
        Respond in JSON format:
        {
            "configured_modules": true/false,
            "reasoning": "brief explanation"
        }
        """
        
        if frames and final:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('configured_modules', False):
                    vlm_score = 20
                    feedback_parts.append("VLM: Confirmed module configuration activity")
                else:
                    feedback_parts.append("VLM: Did not detect module configuration activity")
            else:
                feedback_parts.append("VLM: Query failed")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM: Error during verification")
        
    score += vlm_score

    # To pass, agent must achieve >= 70 out of 100 possible points.
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }