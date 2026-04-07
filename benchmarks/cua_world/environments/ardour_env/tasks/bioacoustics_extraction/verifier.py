#!/usr/bin/env python3
"""
Verifier for bioacoustics_extraction task.
Occupation: Zoologist and Wildlife Biologist (SOC 19-1023)

Checks that the agent extracted precise audio segments to a new track,
muted the original source, applied positive gain, and exported the result.
"""

import math
import os
import tempfile
import logging
import json
import xml.etree.ElementTree as ET

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 44100


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Get all audio tracks excluding master/monitor."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_by_name(root, target_name):
    """Find a route exactly matching or containing the target name (case-insensitive)."""
    for route in get_audio_routes(root):
        rname = route.get('name', '').lower()
        if target_name.lower() in rname:
            return route
    return None

def is_route_muted(route):
    """Check if an Ardour route is muted."""
    # Check route attribute
    if route.get('muted') in ('1', 'yes', 'true'):
        return True
    # Check controllable
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    return False

def get_route_gain_db(route):
    """Get track fader gain in dB."""
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

def get_playlist_regions(root, route_name):
    """Get all regions in the playlist belonging to a route."""
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'start': int(region.get('start', '0')), # Offset into source file
                    'position': int(region.get('position', '0')), # Position on timeline
                    'length': int(region.get('length', '0')),
                })
    return regions


# ---------- Main Verifier ----------

def verify_bioacoustics_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_timestamps_sec = metadata.get('target_timestamps_sec', [5.0, 14.0, 22.0])
    tolerance_sec = metadata.get('tolerance_sec', 0.5)
    gain_min_db = metadata.get('gain_min_db', 4.0)
    gain_max_db = metadata.get('gain_max_db', 10.0)

    score = 0
    feedback_parts = []

    # 1. Retrieve the task result JSON
    result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_tmp.close()
    
    try:
        copy_from_env("/tmp/task_result.json", result_tmp.name)
        with open(result_tmp.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        os.unlink(result_tmp.name)

    # 2. Retrieve Ardour session XML
    session_remote = task_result.get('session_xml_path', '/home/ga/Audio/sessions/MyProject/MyProject.ardour')
    xml_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    xml_tmp.close()
    
    try:
        copy_from_env(session_remote, xml_tmp.name)
        tree = ET.parse(xml_tmp.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(xml_tmp.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to parse session XML: {e}"}
    finally:
        if os.path.exists(xml_tmp.name):
            os.unlink(xml_tmp.name)

    # ================================================================
    # PROGRAMMATIC CRITERIA
    # ================================================================

    # Criterion 1: Track Creation (15 pts)
    target_route = get_route_by_name(root, "Target Species")
    if target_route is not None:
        score += 15
        feedback_parts.append("Target Species track exists")
    else:
        feedback_parts.append("FAIL: Target Species track missing")

    # Criterion 2: Region Extraction (30 pts - 10 per region)
    regions_found = 0
    if target_route is not None:
        regions = get_playlist_regions(root, target_route.get('name'))
        tolerance_samples = int(tolerance_sec * SAMPLE_RATE)
        
        for expected_sec in target_timestamps_sec:
            expected_samples = int(expected_sec * SAMPLE_RATE)
            matched = False
            for reg in regions:
                # 'start' is the offset into the original audio file where this region begins
                if abs(reg['start'] - expected_samples) <= tolerance_samples:
                    matched = True
                    break
            if matched:
                regions_found += 1
                
        score += (regions_found * 10)
        feedback_parts.append(f"{regions_found}/3 regions extracted correctly")

    # Criterion 3: Original Muted (15 pts)
    source_route = get_route_by_name(root, "Raw Canopy")
    if source_route is not None:
        if is_route_muted(source_route):
            score += 15
            feedback_parts.append("Source track is muted")
        else:
            feedback_parts.append("Source track is NOT muted")
    else:
        feedback_parts.append("Source track 'Raw Canopy' missing/renamed incorrectly")

    # Criterion 4: Gain Boost (20 pts)
    if target_route is not None:
        gain_db = get_route_gain_db(target_route)
        if gain_min_db <= gain_db <= gain_max_db:
            score += 20
            feedback_parts.append(f"Target gain correct ({gain_db:.1f} dB)")
        else:
            # Partial credit if they tried to boost it but missed the window
            if gain_db > 1.0:
                score += 10
                feedback_parts.append(f"Target gain boosted but outside range ({gain_db:.1f} dB)")
            else:
                feedback_parts.append(f"Target gain incorrect ({gain_db:.1f} dB)")

    # Criterion 5: File Exported (20 pts)
    if task_result.get('export_file_exists'):
        size_bytes = task_result.get('export_file_size_bytes', 0)
        created_during_task = task_result.get('file_created_during_task', False)
        
        if size_bytes > 10240 and created_during_task:
            score += 20
            feedback_parts.append("Valid audio exported")
        elif size_bytes <= 10240:
            feedback_parts.append("Export file too small (corrupt or silent)")
        elif not created_during_task:
            feedback_parts.append("Export file existed before task (gaming attempt)")
    else:
        feedback_parts.append("Export file NOT found")

    # ================================================================
    # VLM TRAJECTORY CHECK (Anti-Gaming)
    # ================================================================
    # We sample a few frames to ensure the agent actually worked in the UI
    # instead of just editing the XML file programmatically (if it somehow bypassed constraints)
    vlm_query = env_info.get("query_vlm")
    if vlm_query and len(traj) > 0:
        frames = sample_trajectory_frames(traj, n=3)
        prompt = """
        You are reviewing a trajectory of an AI agent using Ardour.
        Did the agent visibly interact with the Ardour UI (e.g., timeline, mixing board, or menus)?
        Answer exclusively in JSON:
        {"ui_interaction_observed": true/false}
        """
        try:
            vlm_res = vlm_query(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if not parsed.get("ui_interaction_observed", True):
                    logger.warning("VLM suspects no UI interaction occurred.")
                    feedback_parts.append("VLM WARNING: No Ardour UI interaction observed.")
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

    # ================================================================
    # FINAL SCORING
    # ================================================================
    pass_threshold = metadata.get('pass_threshold', 70)
    key_criteria_met = (regions_found >= 2 and task_result.get('export_file_exists'))
    
    passed = (score >= pass_threshold) and key_criteria_met

    if not key_criteria_met and score >= pass_threshold:
        feedback_parts.append("FAIL: Reached points threshold, but failed mandatory key criteria (extraction + export).")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }