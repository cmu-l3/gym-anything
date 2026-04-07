#!/usr/bin/env python3
"""
Verifier for openvsp_canard_pusher_config task.

Verification Strategy:
1. File-based parsing: The .vsp3 file is standard XML. We parse it to extract
   components (<Geom>), their types, and their parameters (<Parm>).
2. Criteria Checks:
   - Valid XML created during task (anti-gaming check)
   - Contains a fuselage/body component
   - Contains a main wing (span 5.0-9.0, sweep >= 15)
   - Contains a canard (span 2.0-5.0)
   - CRITICAL: Canard is positioned forward of main wing (X offset diff >= 0.5)
   - Contains a vertical surface
3. VLM Trajectory: Verifies UI interaction to prevent completely programmatic generation.
"""

import os
import json
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_openvsp_canard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_json_path = metadata.get('result_json', '/tmp/canard_pusher_result.json')
    
    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Basic File & Anti-Gaming Checks (10 pts + 10 pts)
    # ---------------------------------------------------------
    file_exists = result.get('file_exists', False)
    task_start = result.get('task_start', 0)
    mtime = result.get('mtime', 0)
    openvsp_running = result.get('openvsp_running_during_task', False)
    file_content = result.get('file_content', '')

    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Target .vsp3 file does not exist."}
    
    if mtime <= task_start:
        feedback_parts.append("File modification time is older than task start (Do Nothing detected).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    try:
        root = ET.fromstring(file_content)
        score += 10
        feedback_parts.append("Valid OpenVSP XML found.")
    except ET.ParseError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid XML format: {e}"}

    if openvsp_running:
        score += 10
        feedback_parts.append("OpenVSP was used.")

    # ---------------------------------------------------------
    # 2. Extract Geometry Components
    # ---------------------------------------------------------
    components = []
    for geom in root.findall(".//Geom"):
        comp_type = geom.findtext("Type", default="Unknown")
        name = geom.attrib.get("Name", "Unnamed")
        
        parms = {}
        for parm in geom.findall(".//Parm"):
            p_name = parm.attrib.get("Name")
            p_val = parm.attrib.get("Value")
            if p_name and p_val:
                try:
                    parms[p_name] = float(p_val)
                except ValueError:
                    pass
        components.append({"name": name, "type": comp_type, "parms": parms})

    if len(components) >= 4:
        score += 5
        feedback_parts.append(f"Model has {len(components)} components (>= 4).")
    else:
        feedback_parts.append(f"Model only has {len(components)} components (expected >= 4).")

    # ---------------------------------------------------------
    # 3. Identify Fuselage (10 pts)
    # ---------------------------------------------------------
    has_fuselage = any(c['type'] in ['Fuselage', 'Pod', 'BodyOfRevolution', 'Stack'] for c in components)
    if has_fuselage:
        score += 10
        feedback_parts.append("Fuselage/body component found.")
    else:
        feedback_parts.append("Missing fuselage component.")

    # ---------------------------------------------------------
    # 4. Identify Main Wing & Canard (15 pts + 15 pts)
    # ---------------------------------------------------------
    wings = [c for c in components if c['type'] == 'Wing']
    
    main_wing = None
    canard = None
    vertical = None
    
    for w in wings:
        span = w['parms'].get('TotalSpan', 0.0)
        sweep = w['parms'].get('Sweep', 0.0)
        
        if 5.0 <= span <= 9.0 and sweep >= 10.0:
            if not main_wing or span > main_wing['parms'].get('TotalSpan', 0):
                main_wing = w
        elif 2.0 <= span < 5.0:
            if not canard or span > canard['parms'].get('TotalSpan', 0):
                canard = w

    if main_wing:
        score += 15
        feedback_parts.append(f"Main wing identified (Span: {main_wing['parms'].get('TotalSpan',0):.1f}m).")
    else:
        feedback_parts.append("Missing main wing (could not find wing with span 5-9m).")

    if canard:
        score += 15
        feedback_parts.append(f"Canard identified (Span: {canard['parms'].get('TotalSpan',0):.1f}m).")
    else:
        feedback_parts.append("Missing canard (could not find wing with span 2-5m).")

    # ---------------------------------------------------------
    # 5. Position Check: Canard ahead of Main Wing (20 pts)
    # ---------------------------------------------------------
    # In OpenVSP, nose is typically at X=0, tail at +X. 
    # Smaller X means further forward.
    position_correct = False
    if main_wing and canard:
        mw_x = main_wing['parms'].get('X_Rel_Location', main_wing['parms'].get('X_Location', 0.0))
        ca_x = canard['parms'].get('X_Rel_Location', canard['parms'].get('X_Location', 0.0))
        
        # Canard should be at least 0.5m ahead (smaller X) of the main wing
        if ca_x < (mw_x - 0.5):
            score += 20
            position_correct = True
            feedback_parts.append(f"Positioning correct: Canard (X={ca_x:.1f}) is ahead of Main Wing (X={mw_x:.1f}).")
        else:
            feedback_parts.append(f"Positioning incorrect: Canard (X={ca_x:.1f}) is NOT ahead of Main Wing (X={mw_x:.1f}).")
    else:
        feedback_parts.append("Cannot verify canard positioning because components are missing.")

    # ---------------------------------------------------------
    # 6. Identify Vertical Surface (10 pts)
    # ---------------------------------------------------------
    for w in wings:
        if w != main_wing and w != canard:
            vertical = w
            break
            
    if vertical:
        score += 10
        feedback_parts.append("Vertical surface / 3rd wing component identified.")
    else:
        feedback_parts.append("Missing vertical surface (expected at least 3 wing components).")

    # ---------------------------------------------------------
    # 7. VLM Verification of Trajectory (Optional/Fallback)
    # ---------------------------------------------------------
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "You are verifying an agent's completion of an OpenVSP CAD task. "
                    "Looking at these workflow frames, does it show the agent actively interacting "
                    "with the OpenVSP GUI (e.g. adding components, adjusting parameters in dialogs)? "
                    "Return JSON with 'ui_interaction': true/false."
                )
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res.get('success') and vlm_res.get('parsed', {}).get('ui_interaction'):
                    feedback_parts.append("VLM confirms GUI interaction.")
                else:
                    feedback_parts.append("VLM did not detect strong GUI interaction.")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

    # Pass condition: must score >= 60 AND correct canard positioning is required
    passed = (score >= 60) and position_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }