#!/usr/bin/env python3
"""
Verifier for mix_version_snapshots task.

Criteria (100 pts total, pass >= 60):
  1. Full_Mix snapshot exists, is fresh, and has correct gain (15 pts)
  2. Reduced_Mix snapshot exists, is fresh, and has correct gain (15 pts)
  3. Muted_Track snapshot exists, is fresh, and track is muted (15 pts)
  4. Snapshots are distinct (not identical copies of the same state) (15 pts)
  5. VLM Trajectory check: Agent interacted with fader/mixer and snapshot dialog (40 pts)
"""

import math
import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_first_audio_route(root):
    """Finds the first regular audio track (excluding Master/Monitor)."""
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            return route
    return None


def get_route_gain_db(route):
    """Extracts gain in dB from a route."""
    if route is None:
        return 0.0
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') in ('gaincontrol', 'gain'):
            try:
                val = float(ctrl.get('value', '1.0'))
                if val <= 0:
                    return -120.0
                return 20 * math.log10(val)
            except (ValueError, TypeError):
                return 0.0
    return 0.0


def is_route_muted(route):
    """Determines if a route is muted."""
    if route is None:
        return False
        
    # Check <MuteMaster> flag
    for mm in route.iter('MuteMaster'):
        if mm.get('muted', 'no') in ('1', 'yes', 'true'):
            return True
            
    # Check controllable
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
            
    # Check route attribute
    return route.get('muted', '0') in ('1', 'yes', 'true')


def verify_mix_version_snapshots(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    full_min = metadata.get('expected_full_mix_min_db', -3.0)
    full_max = metadata.get('expected_full_mix_max_db', 3.0)
    red_min = metadata.get('expected_reduced_mix_min_db', -15.0)
    red_max = metadata.get('expected_reduced_mix_max_db', -9.0)
    mute_thresh = metadata.get('mute_gain_threshold_db', -60.0)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Dictionary to hold the states for distinctness check
    snapshot_states = {}

    # Helper function to process a snapshot
    def process_snapshot(name, key, min_db=None, max_db=None, check_mute=False):
        nonlocal score, feedback_parts
        
        info = result.get(key, {})
        if not info.get('exists'):
            feedback_parts.append(f"FAIL: {name} snapshot file not found.")
            return False
            
        if not info.get('is_fresh'):
            feedback_parts.append(f"FAIL: {name} snapshot is stale (created before task).")
            return False

        # Copy the XML
        tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
        tmp_xml.close()
        try:
            copy_from_env(f"/tmp/{name}_Snapshot.ardour", tmp_xml.name)
            tree = ET.parse(tmp_xml.name)
            root = tree.getroot()
            
            route = get_first_audio_route(root)
            if route is None:
                feedback_parts.append(f"FAIL: {name} snapshot has no audio tracks.")
                return False
                
            gain = get_route_gain_db(route)
            muted = is_route_muted(route)
            
            # Save state for distinctness
            snapshot_states[key] = {'gain': gain, 'muted': muted}
            
            success = True
            if check_mute:
                if muted or gain <= mute_thresh:
                    score += 15
                    feedback_parts.append(f"PASS: {name} is muted correctly.")
                else:
                    feedback_parts.append(f"FAIL: {name} is NOT muted (gain: {gain:.1f} dB).")
                    success = False
            else:
                if min_db <= gain <= max_db:
                    score += 15
                    feedback_parts.append(f"PASS: {name} gain is {gain:.1f} dB (within {min_db} to {max_db}).")
                else:
                    feedback_parts.append(f"FAIL: {name} gain is {gain:.1f} dB (expected {min_db} to {max_db}).")
                    success = False
            
            return success
        except Exception as e:
            feedback_parts.append(f"ERROR: Failed to parse {name} XML: {e}")
            return False
        finally:
            if os.path.exists(tmp_xml.name):
                os.unlink(tmp_xml.name)

    # 2. Process each snapshot
    process_snapshot("Full_Mix", "full_mix", min_db=full_min, max_db=full_max)
    process_snapshot("Reduced_Mix", "reduced_mix", min_db=red_min, max_db=red_max)
    process_snapshot("Muted_Track", "muted_track", check_mute=True)

    # 3. Distinctness check (anti-gaming to prevent submitting 3 copies of the exact same XML)
    if len(snapshot_states) >= 2:
        states = list(snapshot_states.values())
        # Compare first against rest
        is_distinct = False
        first_state = states[0]
        for s in states[1:]:
            if abs(s['gain'] - first_state['gain']) > 0.5 or s['muted'] != first_state['muted']:
                is_distinct = True
                break
                
        if is_distinct:
            score += 15
            feedback_parts.append("PASS: Snapshots show distinct configurations.")
        else:
            feedback_parts.append("FAIL: All snapshots have identical gain/mute states (possible gaming).")

    # 4. VLM Verification (Trajectory Analysis)
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            prompt = """You are verifying an agent performing a DAW (Ardour) task.
The agent's goal was to adjust track gain/faders, toggle mute, and save session snapshots via dialog boxes.

Please evaluate the provided sequence of screenshots from the agent's workflow:
1. FADER_INTERACTION: Did the agent open the mixer or click/drag a volume fader/slider for the audio track?
2. MUTE_INTERACTION: Did the agent click an 'M' (Mute) button on a track?
3. SNAPSHOT_DIALOG: Did a dialog box appear for saving a 'Snapshot' where the agent could type a name?

Return JSON format:
{
    "fader_interaction_visible": true/false,
    "mute_interaction_visible": true/false,
    "snapshot_dialog_visible": true/false,
    "observations": "Brief explanation of what is visible"
}"""
            
            vlm_response = query_vlm(prompt=prompt, images=frames)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("fader_interaction_visible"):
                    vlm_score += 15
                    feedback_parts.append("VLM: Fader adjustment observed (+15)")
                if parsed.get("mute_interaction_visible"):
                    vlm_score += 10
                    feedback_parts.append("VLM: Mute toggle observed (+10)")
                if parsed.get("snapshot_dialog_visible"):
                    vlm_score += 15
                    feedback_parts.append("VLM: Snapshot dialog observed (+15)")
                    
                score += vlm_score
            else:
                feedback_parts.append(f"VLM verification failed to run: {vlm_response.get('error')}")
        except Exception as e:
            feedback_parts.append(f"VLM processing error: {e}")
    else:
        feedback_parts.append("VLM verification skipped (not available).")

    # 5. Finalize Score
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }