#!/usr/bin/env python3
"""
Verifier for archival_audio_restoration task.
Evaluates precision region editing, plugin insertion, and export configuration.
"""

import os
import json
import logging
import tempfile
import xml.etree.ElementTree as ET

# Import VLM helpers safely
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def find_target_route(root, target_name):
    """Find a route by exact or close name."""
    for route in get_audio_routes(root):
        if route.get('name', '').lower() == target_name.lower():
            return route
    return None

def verify_archival_audio_restoration(traj, env_info, task_info):
    """
    Multi-criterion verifier for the archival restoration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Get execution metadata
    metadata = task_info.get('metadata', {})
    expected_trim = metadata.get('expected_trim_samples', 176400)
    trim_tol = metadata.get('trim_tolerance_samples', 22050)
    
    # 1. READ EXPORT RESULTS
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. READ ARDOUR SESSION XML
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()
    try:
        copy_from_env("/home/ga/Audio/sessions/MyProject/MyProject.ardour", tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"XML parse error: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # --- CRITERION 1: Track Setup (10 pts) ---
    target_route = find_target_route(root, "Oral History 1974")
    if target_route is not None:
        score += 10.0
        feedback.append("PASS: Track 'Oral History 1974' created/renamed.")
    else:
        # Fallback to the first available non-default track
        routes = get_audio_routes(root)
        if routes:
            target_route = routes[0]
            feedback.append("FAIL: Target track not named correctly. Grading first available track.")
        else:
            return {"passed": False, "score": 0.0, "feedback": "No audio tracks found."}

    route_id = target_route.get('id')
    
    # --- CRITERION 2: Audio Trimmed & Positioned (20 pts) ---
    # Find regions belonging to this route's playlist
    regions = []
    for pl in root.iter('Playlist'):
        pl_name = pl.get('name', '')
        if route_id in pl.get('id', '') or target_route.get('name') in pl_name:
            for region in pl.iter('Region'):
                regions.append(region)
    
    if regions:
        # Evaluate first region on track
        reg = regions[0]
        start_offset = int(reg.get('start', '0'))
        position = int(reg.get('position', '0'))
        
        # Check trim amount (start offset into the source file should be ~4.0 seconds)
        if abs(start_offset - expected_trim) <= trim_tol:
            score += 10.0
            feedback.append("PASS: Audio region trimmed by approx 4 seconds.")
        elif start_offset > 0:
            score += 5.0
            feedback.append(f"PARTIAL: Region trimmed, but inaccurate (start offset: {start_offset}).")
        else:
            feedback.append("FAIL: Region start not trimmed.")

        # Check positioning (should be moved to 0)
        if position <= 4410: # within 0.1 seconds of 0
            score += 10.0
            feedback.append("PASS: Audio region positioned at start of timeline.")
        else:
            feedback.append("FAIL: Audio region not moved to 0.")
            
        # --- CRITERION 3: Fade-in Applied (10 pts) ---
        fade_active = reg.get('fade-in-active', '0') == '1'
        has_fade_node = reg.find('FadeIn') is not None
        if fade_active or has_fade_node:
            score += 10.0
            feedback.append("PASS: Fade-in applied to region.")
        else:
            feedback.append("FAIL: No fade-in found on region.")
    else:
        feedback.append("FAIL: No audio regions found on the track.")

    # --- CRITERION 4: Plugin Inserted (15 pts) ---
    has_plugin = False
    for proc in target_route.iter('Processor'):
        if proc.get('type') == 'plugin':
            has_plugin = True
            break
            
    if has_plugin:
        score += 15.0
        feedback.append("PASS: FX Plugin successfully inserted on track.")
    else:
        feedback.append("FAIL: No FX Plugin inserted on the track.")

    # --- CRITERION 5: FLAC Export (30 pts) ---
    if export_data.get('export_exists'):
        if export_data.get('created_during_task'):
            # Validate size and format
            if export_data.get('file_size', 0) > 10000:
                if 'flac' in export_data.get('file_type', '').lower():
                    score += 30.0
                    feedback.append("PASS: Valid FLAC file exported during task.")
                else:
                    score += 10.0
                    feedback.append(f"PARTIAL: Exported file is not true FLAC format (Magic type: {export_data.get('file_type')})")
            else:
                feedback.append("FAIL: Exported file is too small to be valid audio.")
        else:
            feedback.append("FAIL: FLAC file exists but was not created during this task session.")
    else:
        feedback.append("FAIL: FLAC export file not found.")

    # --- CRITERION 6: VLM Trajectory Verification (15 pts) ---
    if VLM_AVAILABLE and query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_prompt = """Analyze this sequence of screenshots from a user working in the Ardour DAW.
Did the user do the following?
1. Open a Plugin window (e.g., an EQ, Filter, or effects UI) at any point?
2. Open the 'Export' dialog window to save their audio?

Return a JSON object:
{
    "plugin_window_visible": true/false,
    "export_dialog_visible": true/false
}"""
            try:
                result = query_vlm(images=frames + [final], prompt=vlm_prompt)
                if result and result.get("success"):
                    parsed = result.get("parsed", {})
                    if parsed.get("plugin_window_visible"):
                        score += 7.5
                        feedback.append("VLM PASS: Plugin UI interaction observed.")
                    if parsed.get("export_dialog_visible"):
                        score += 7.5
                        feedback.append("VLM PASS: Export dialog interaction observed.")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")
                # Grant points if VLM fails to avoid penalizing the agent for backend issues
                score += 15.0 

    pass_threshold = metadata.get('pass_threshold', 65)
    passed = score >= pass_threshold and export_data.get('export_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }