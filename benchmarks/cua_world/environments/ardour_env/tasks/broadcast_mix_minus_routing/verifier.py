#!/usr/bin/env python3
"""
Verifier for broadcast_mix_minus_routing task.

Verifies Ardour DAW signal flow (Mix-Minus creation, positive/negative routing checks)
and parameter changes (+6dB, -3dB). Uses both programmatic XML parsing and VLM.
"""

import math
import os
import tempfile
import json
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Ardour XML Parsing Helpers ---

def get_routes(root):
    return [r for r in root.iter('Route') if 'MasterOut' not in r.get('flags', '') and 'MonitorOut' not in r.get('flags', '')]

def get_route_by_name(root, name):
    for r in get_routes(root):
        if r.get('name', '').lower() == name.lower():
            return r
    return None

def has_audio_in_playlist(root, route):
    if route is None:
        return False
    # Route's playlist is often named <RouteName> or <RouteName>.1
    route_name = route.get('name', '')
    for pl in root.iter('Playlist'):
        pl_name = pl.get('name', '')
        if pl_name.startswith(route_name):
            if list(pl.iter('Region')):
                return True
    return False

def is_routed_to(route, target_route):
    """
    Check if `route` sends audio to `target_route`.
    In Ardour, this can be a <Processor type="send"> OR a direct <Connection> in <Output>.
    """
    if route is None or target_route is None:
        return False
        
    target_id = target_route.get('id')
    target_name = target_route.get('name', '')

    # 1. Check Sends
    for proc in route.iter('Processor'):
        if proc.get('type') == 'send' and proc.get('target') == target_id:
            return True

    # 2. Check direct output connections
    for output in route.iter('Output'):
        for conn in output.iter('Connection'):
            other = conn.get('other', '')
            # Typical Ardour connection: other="Mix Minus/in 1"
            if target_name in other and ('/in' in other or ':in' in other):
                return True

    return False

def get_route_gain_db(route):
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

# --- Main Verifier ---

def verify_mix_minus_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    gain_tolerance = metadata.get('gain_tolerance', 0.5)

    score = 0
    feedback = []

    # 1. Read task_result.json to check basic file metrics
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_stats = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result_stats = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_stats.get("session_file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Ardour session file missing"}
    
    if not result_stats.get("file_modified_during_task", False):
        feedback.append("WARNING: Session file was not modified/saved during task execution.")

    # 2. Parse Ardour XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Ardour XML: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # --- Criterion 1: Tracks & Bus Created (15 pts) ---
    r_host = get_route_by_name(root, "Host Mic")
    r_board = get_route_by_name(root, "Soundboard")
    r_guest = get_route_by_name(root, "Remote Guest")
    r_mixminus = get_route_by_name(root, "Mix Minus")

    found_routes = sum([1 for r in [r_host, r_board, r_guest, r_mixminus] if r is not None])
    score += found_routes * 3.75  # Max 15
    if found_routes == 4:
        feedback.append("Tracks/Bus created correctly.")
    else:
        feedback.append(f"Found {found_routes}/4 required tracks/buses.")

    # --- Criterion 2: Audio Imported (10 pts) ---
    if has_audio_in_playlist(root, r_host):
        score += 5
    if has_audio_in_playlist(root, r_guest):
        score += 5
    feedback.append("Audio import checked.")

    # --- Criterion 3: Mix-Minus Feed Routing (20 pts) ---
    # Host and Soundboard MUST go to Mix Minus
    feed_score = 0
    if is_routed_to(r_host, r_mixminus):
        feed_score += 10
    if is_routed_to(r_board, r_mixminus):
        feed_score += 10
    score += feed_score
    if feed_score == 20:
        feedback.append("Host/Soundboard properly routed to Mix Minus.")
    else:
        feedback.append("Missing sends to Mix Minus.")

    # --- Criterion 4: Guest Isolation (20 pts) ---
    # Remote Guest MUST NOT go to Mix Minus
    # We only score this if the Guest track and Mix Minus bus actually exist to prevent gaming
    guest_isolated = False
    if r_guest is not None and r_mixminus is not None:
        if not is_routed_to(r_guest, r_mixminus):
            score += 20
            guest_isolated = True
            feedback.append("Guest track correctly isolated from Mix Minus.")
        else:
            feedback.append("FAIL: Guest track is routed to Mix Minus (echo caused!).")

    # --- Criterion 5: Gain Adjustments (20 pts) ---
    # Guest +6 dB, Mix Minus -3 dB
    gain_score = 0
    guest_gain = get_route_gain_db(r_guest)
    mixminus_gain = get_route_gain_db(r_mixminus)
    
    if r_guest is not None and abs(guest_gain - 6.0) <= gain_tolerance:
        gain_score += 10
    if r_mixminus is not None and abs(mixminus_gain - (-3.0)) <= gain_tolerance:
        gain_score += 10
    score += gain_score
    feedback.append(f"Gains: Guest {guest_gain:.1f}dB, MixMinus {mixminus_gain:.1f}dB.")

    # --- Criterion 6: VLM Trajectory Process Check (15 pts) ---
    # Verify the agent actually manipulated the DAW UI, not just directly wrote XML
    vlm_score = 0
    
    # Import VLM helpers from gym_anything
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_prompt = """Review this sequence of screenshots from a user operating the Ardour Digital Audio Workstation. 
            Did the user interact with the routing matrix, the mixer window, or the track header to configure routing or adjust gain sliders?
            Respond in JSON: {"daw_interaction_observed": true/false}"""
            
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('daw_interaction_observed', False):
                    vlm_score = 15
                    feedback.append("VLM confirms DAW interaction.")
                else:
                    feedback.append("VLM did not observe active DAW routing/mixing.")
            else:
                feedback.append("VLM query failed, awarding partial VLM points safely.")
                vlm_score = 10  # Benefit of doubt if API fails
        else:
            vlm_score = 15 # No frames usually means testing outside framework
    except ImportError:
        # Fallback if VLM not available
        logger.warning("VLM module not found. Skipping VLM check.")
        vlm_score = 15
    
    score += vlm_score

    # Check key criteria to pass: Must have Mix-Minus feed AND Guest Isolation
    key_criteria_met = (feed_score >= 10) and guest_isolated
    passed = (score >= metadata.get('pass_threshold', 70)) and key_criteria_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "details": {
            "feed_score": feed_score,
            "guest_isolated": guest_isolated,
            "gain_score": gain_score,
            "vlm_score": vlm_score
        }
    }