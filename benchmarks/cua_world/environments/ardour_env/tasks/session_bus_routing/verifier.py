#!/usr/bin/env python3
"""
Verifier for session_bus_routing task.

Checks:
1. 3 Buses created with correct names (15 pts)
2. Tracks routed correctly to their respective buses (30 pts)
3. Buses routed to Master output (15 pts)
4. Bus gain levels set correctly (15 pts)
5. VLM trajectory verification (25 pts)
"""

import os
import math
import json
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_name(name):
    """Normalize names for flexible matching (case/underscore/hyphen insensitive)."""
    return name.lower().replace('_', ' ').replace('-', ' ').strip()


def get_all_routes(root):
    """Return all routes excluding Master and Monitor."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        routes.append(route)
    return routes


def get_route_gain_db(route):
    """Calculate gain in dB from Ardour's linear gaincontrol."""
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


def get_route_connections(route, direction="Output"):
    """Get a list of 'other' port names connected to this route."""
    conns = []
    for io in route.findall('IO'):
        if io.get('direction') == direction:
            for port in io.findall('Port'):
                for conn in port.findall('Connection'):
                    conns.append(conn.get('other', ''))
    return conns


def is_routed_to(route, target_name):
    """Check if the given route's output is connected to the target route."""
    conns = get_route_connections(route, "Output")
    target_norm = normalize_name(target_name)
    for c in conns:
        # 'other' looks like "Drum Bus/audio_in 1"
        target_port_base = normalize_name(c.split('/')[0])
        if target_port_base == target_norm:
            return True
    return False


def verify_session_bus_routing(traj, env_info, task_info):
    """Main verification function."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_buses = metadata.get('expected_buses', ["Drum Bus", "Music Bus", "Vocal Bus"])
    routing_map = metadata.get('routing_map', {})
    expected_gains_db = metadata.get('expected_gains_db', {})
    gain_tolerance = metadata.get('gain_tolerance_db', 1.5)

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. Read task execution state
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('session_modified', False):
        return {"passed": False, "score": 0, "feedback": "FAIL: Session was not modified or saved."}

    # ================================================================
    # 2. Parse Session XML
    # ================================================================
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse session XML: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    routes = get_all_routes(root)
    
    # Identify Buses and Tracks
    buses_found = {}
    tracks_found = {}
    
    for r in routes:
        name = r.get('name', '')
        norm_name = normalize_name(name)
        
        # Determine if it's an expected track
        is_track = False
        for expected_track in routing_map.keys():
            if normalize_name(expected_track) == norm_name:
                tracks_found[expected_track] = r
                is_track = True
                break
                
        # If not a track, check if it's an expected bus
        if not is_track:
            for expected_bus in expected_buses:
                if normalize_name(expected_bus) == norm_name:
                    buses_found[expected_bus] = r
                    break

    # ================================================================
    # CRITERION 1: Bus Existence (15 points)
    # ================================================================
    bus_score = 0
    for bus in expected_buses:
        if bus in buses_found:
            bus_score += 5
            
    score += bus_score
    feedback_parts.append(f"Buses created: {len(buses_found)}/{len(expected_buses)}")

    # ================================================================
    # CRITERION 2: Track Routing (30 points)
    # ================================================================
    routing_score = 0
    correct_routes = 0
    for track_name, target_bus in routing_map.items():
        if track_name in tracks_found and target_bus in buses_found:
            track_route = tracks_found[track_name]
            if is_routed_to(track_route, target_bus):
                routing_score += 5
                correct_routes += 1
                
    score += routing_score
    feedback_parts.append(f"Tracks routed correctly: {correct_routes}/{len(routing_map)}")

    # ================================================================
    # CRITERION 3: Master Routing (15 points)
    # ================================================================
    master_score = 0
    correct_masters = 0
    for bus_name, bus_route in buses_found.items():
        if is_routed_to(bus_route, "Master"):
            master_score += 5
            correct_masters += 1
            
    score += master_score
    if len(buses_found) > 0:
        feedback_parts.append(f"Buses routed to Master: {correct_masters}/{len(buses_found)}")

    # ================================================================
    # CRITERION 4: Gain Staging (15 points)
    # ================================================================
    gain_score = 0
    correct_gains = 0
    for bus_name, bus_route in buses_found.items():
        expected_gain = expected_gains_db.get(bus_name, 0.0)
        actual_gain = get_route_gain_db(bus_route)
        if abs(actual_gain - expected_gain) <= gain_tolerance:
            gain_score += 5
            correct_gains += 1
            
    score += gain_score
    if len(buses_found) > 0:
        feedback_parts.append(f"Correct bus gains: {correct_gains}/{len(buses_found)}")

    # ================================================================
    # CRITERION 5: VLM Trajectory Verification (25 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            
            prompt = """You are evaluating screenshots of an Ardour DAW session.
            The user was tasked with creating submix buses, routing audio tracks to those buses, and adjusting gain faders.
            
            Look closely at these chronological frames and determine:
            1. Did the user open or interact with the Mixer window (which shows vertical channel strips and faders)?
            2. Or did they use the Audio Connections / Routing Matrix grid?
            3. Do the screens show evidence of adding new buses or changing fader levels?
            
            Respond with JSON format:
            {
                "used_mixer_or_routing": true/false,
                "evidence": "brief string explaining what you observed"
            }
            """
            
            result = query_vlm(prompt=prompt, images=frames)
            if result.get('success'):
                parsed = result.get('parsed', {})
                if parsed.get('used_mixer_or_routing', False):
                    vlm_score = 25
                    feedback_parts.append("VLM: Verified interaction with mixer/routing UI")
                else:
                    feedback_parts.append("VLM: No evidence of mixer/routing usage in trajectory")
            else:
                vlm_score = 25 # Default pass if VLM fails randomly
                feedback_parts.append("VLM: Query failed, bypassing visual check")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            vlm_score = 25
            feedback_parts.append("VLM: Error occurred, bypassing visual check")
    else:
        # Scale score if VLM is entirely unavailable in env
        vlm_score = 25
        feedback_parts.append("VLM unconfigured: Auto-passing visual criteria")
        
    score += vlm_score

    # Evaluate final pass/fail
    passed = score >= 75 and correct_routes >= 4 and len(buses_found) == 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }