#!/usr/bin/env python3
"""
Verifier for studio_cue_mix_setup task.

Verifies:
1. "Drummer Cue" bus exists.
2. The bus is disconnected from the Master output.
3. Tracks ("Click Track", "Bass", "Vocal") exist and send to the bus.
4. Sends are Pre-Fader (inserted before the amp processor).
5. Send gain levels match specifications within tolerance.
"""

import os
import json
import math
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_route_by_name(root, name_pattern):
    for route in root.iter('Route'):
        if name_pattern.lower() in route.get('name', '').lower():
            return route
    return None

def is_disconnected_from_master(route):
    output = route.find('Output')
    if output is not None:
        for conn in output.findall('Connection'):
            dest = conn.get('destination', '').lower()
            if 'master' in dest:
                return False
    return True

def get_send_processor(route, bus_id, bus_name):
    """Find the processor that acts as a send to the target bus."""
    for idx, proc in enumerate(route.findall('Processor')):
        ptype = proc.get('type', '')
        if ptype in ('intsend', 'send'):
            target = proc.get('target', '')
            pname = proc.get('name', '').lower()
            if target == bus_id or bus_name.lower() in pname:
                return idx, proc
    return -1, None

def get_main_fader_index(route):
    """Find the main channel volume fader index."""
    for idx, proc in enumerate(route.findall('Processor')):
        if proc.get('type') == 'amp' and proc.get('name') == 'amp':
            return idx
    return -1

def get_processor_gain_db(processor):
    gain_ctrl = processor.find(".//Controllable[@name='gaincontrol']")
    if gain_ctrl is not None:
        try:
            val = float(gain_ctrl.get('value', '1.0'))
            return 20 * math.log10(val) if val > 0 else -120.0
        except (ValueError, TypeError):
            return 0.0
    return 0.0

def verify_studio_cue_mix_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Extract metadata specifications
    metadata = task_info.get('metadata', {})
    expected_bus = metadata.get('expected_bus_name', 'Drummer Cue')
    required_tracks = metadata.get('required_tracks', ['Click Track', 'Bass', 'Vocal'])
    target_gains = metadata.get('target_gains', {'Click Track': 0.0, 'Bass': -12.0, 'Vocal': -6.0})
    tolerance = metadata.get('tolerance_db', 2.0)

    feedback_parts = []
    score = 0.0

    # 1. Anti-gaming: Ensure file was modified after task start
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name): os.unlink(tmp_json.name)

    mtime = result.get('session_mtime', 0)
    start_time = result.get('task_start_time', 0)
    
    if mtime <= start_time:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Session file not modified after task started. (mtime: {mtime}, start: {start_time})"
        }

    # 2. Parse Ardour XML
    tmp_ardour = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    try:
        copy_from_env("/home/ga/Audio/sessions/MyProject/MyProject.ardour", tmp_ardour.name)
        tree = ET.parse(tmp_ardour.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Ardour XML: {e}"}
    finally:
        if os.path.exists(tmp_ardour.name): os.unlink(tmp_ardour.name)

    # CRITERION 1: Cue Bus Created (15 pts)
    cue_bus = get_route_by_name(root, expected_bus)
    if cue_bus is not None:
        score += 15.0
        feedback_parts.append(f"Bus '{expected_bus}' exists.")
        cue_bus_id = cue_bus.get('id', '')
    else:
        feedback_parts.append(f"FAIL: Bus '{expected_bus}' not found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Master Disconnected (15 pts)
    if is_disconnected_from_master(cue_bus):
        score += 15.0
        feedback_parts.append("Cue bus outputs correctly disconnected from Master.")
    else:
        feedback_parts.append("FAIL: Cue bus still routes to Master.")

    # CRITERIA 3, 4, 5: Tracks, Pre-Fader Sends, Gain Staging
    pts_per_track_exists = 20.0 / len(required_tracks)
    pts_per_track_prefader = 30.0 / len(required_tracks)
    pts_per_track_gain = 20.0 / len(required_tracks)

    for track_name in required_tracks:
        route = get_route_by_name(root, track_name)
        if route is None:
            feedback_parts.append(f"Track '{track_name}' missing.")
            continue
            
        send_idx, send_proc = get_send_processor(route, cue_bus_id, expected_bus)
        
        # 3: Has Send
        if send_proc is not None:
            score += pts_per_track_exists
        else:
            feedback_parts.append(f"No send to '{expected_bus}' found on '{track_name}'.")
            continue

        # 4: Pre-Fader Topology
        main_fader_idx = get_main_fader_index(route)
        if main_fader_idx != -1 and send_idx < main_fader_idx:
            score += pts_per_track_prefader
            prefader_ok = True
        else:
            feedback_parts.append(f"Send on '{track_name}' is Post-Fader (should be Pre-Fader).")
            prefader_ok = False

        # 5: Gain Accuracy
        actual_gain = get_processor_gain_db(send_proc)
        target_gain = target_gains.get(track_name, 0.0)
        
        if abs(actual_gain - target_gain) <= tolerance:
            score += pts_per_track_gain
            if prefader_ok:
                feedback_parts.append(f"'{track_name}' send configured perfectly ({actual_gain:.1f} dB).")
        else:
            feedback_parts.append(f"'{track_name}' gain mismatch (Expected ~{target_gain}dB, Got {actual_gain:.1f}dB).")

    # VLM Trajectory check for anti-gaming visually
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            vlm_prompt = """Look at this sequence of screenshots from an Ardour DAW session.
            Did the user interact with the mixer/channel strips to create sends or a new bus?
            Reply in JSON format with a boolean field 'mixer_interaction'."""
            
            vlm_res = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_res and vlm_res.get('success'):
                if vlm_res.get('parsed', {}).get('mixer_interaction', False):
                    feedback_parts.append("VLM confirms mixer interaction.")
                else:
                    feedback_parts.append("VLM did NOT detect mixer interaction (possible script usage).")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    passed = score >= 70.0
    return {
        "passed": passed,
        "score": round(score),
        "feedback": " | ".join(feedback_parts)
    }