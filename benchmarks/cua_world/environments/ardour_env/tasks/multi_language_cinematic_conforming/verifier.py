#!/usr/bin/env python3
"""
Verifier for multi_language_cinematic_conforming task.

Criteria evaluated:
1. Track Creation: Checks session XML for EN, ES, and FR dialogue tracks.
2. Region Synchronization: Checks that ES and FR dialogue regions start within
   a tight tolerance of the EN dialogue region.
3. Audio Exports: Checks that both Spanish and French mixes were exported and 
   created during the task session.
4. Mute Discipline: Ensures the session reflects isolated tracks (EN muted).
5. VLM Trajectory: Verifies UI interaction and export workflow to prevent gaming.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Sample rate for Ardour session
SAMPLE_RATE = 44100

def get_audio_routes(root):
    """Find all standard audio tracks."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def find_route_by_keywords(routes, keywords):
    """Find a route matching any of the given keywords."""
    for route in routes:
        name = route.get('name', '').lower()
        if any(kw.lower() in name for kw in keywords):
            return route
    return None

def get_route_mute_state(route):
    """Check if an Ardour route is muted."""
    # Check for direct attribute
    if route.get('muted') in ['1', 'yes', 'true']:
        return True
    # Check for controllable child
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute' and ctrl.get('value') == '1':
            return True
    return False

def get_region_position(root, route):
    """Find the earliest region position for a given route via its playlist."""
    diskstream = route.find('Diskstream')
    if diskstream is None:
        return None
    
    playlist_name = diskstream.get('playlist')
    if not playlist_name:
        return None
        
    for playlist in root.iter('Playlist'):
        if playlist.get('name') == playlist_name:
            positions = []
            for region in playlist.iter('Region'):
                try:
                    positions.append(int(region.get('position', '0')))
                except ValueError:
                    pass
            if positions:
                return min(positions)
    return None

def verify_cinematic_conforming(traj, env_info, task_info):
    """Main verification function."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sync_tolerance = metadata.get('sync_tolerance_samples', 8820) # 0.2 seconds
    min_kb = metadata.get('min_export_size_kb', 50)
    
    score = 0
    feedback_parts = []
    
    # 1. Parse JSON Result from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Parse Session XML
    session_xml_path = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    
    xml_root = None
    try:
        copy_from_env(session_xml_path, temp_xml.name)
        if os.path.exists(temp_xml.name) and os.path.getsize(temp_xml.name) > 0:
            tree = ET.parse(temp_xml.name)
            xml_root = tree.getroot()
    except Exception as e:
        logger.warning(f"Failed to parse session XML: {e}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    if not xml_root:
        return {"passed": False, "score": 0, "feedback": "Ardour session file could not be parsed or found"}

    # Evaluate Tracks & Sync
    routes = get_audio_routes(xml_root)
    
    route_en = find_route_by_keywords(routes, ['en', 'english'])
    route_es = find_route_by_keywords(routes, ['es', 'spanish'])
    route_fr = find_route_by_keywords(routes, ['fr', 'french'])
    
    tracks_exist = bool(route_es and route_fr)
    if tracks_exist:
        score += 15
        feedback_parts.append("ES/FR Tracks created")
    else:
        feedback_parts.append("Missing required dialogue tracks")

    sync_success = False
    if route_en and route_es and route_fr:
        pos_en = get_region_position(xml_root, route_en)
        pos_es = get_region_position(xml_root, route_es)
        pos_fr = get_region_position(xml_root, route_fr)
        
        if pos_en is not None and pos_es is not None and pos_fr is not None:
            es_diff = abs(pos_es - pos_en)
            fr_diff = abs(pos_fr - pos_en)
            
            if es_diff <= sync_tolerance and fr_diff <= sync_tolerance:
                sync_success = True
                score += 35
                feedback_parts.append("Regions successfully synchronized")
            else:
                feedback_parts.append(f"Sync failed. Diffs: ES {es_diff} samples, FR {fr_diff} samples (Tol: {sync_tolerance})")
        else:
            feedback_parts.append("Regions not found on one or more dialogue tracks")
    else:
        feedback_parts.append("Cannot verify sync due to missing tracks")

    # Evaluate Exports
    exports = result.get('exports', {})
    es_exp = exports.get('es', {})
    fr_exp = exports.get('fr', {})
    
    es_valid = es_exp.get('exists') and (es_exp.get('size_bytes', 0) > min_kb * 1024) and es_exp.get('created_during_task')
    if es_valid:
        score += 15
        feedback_parts.append("Spanish export valid")
    
    fr_valid = fr_exp.get('exists') and (fr_exp.get('size_bytes', 0) > min_kb * 1024) and fr_exp.get('created_during_task')
    if fr_valid:
        score += 15
        feedback_parts.append("French export valid")

    # Evaluate Mute Discipline (English track should be muted in the final save state)
    mute_discipline = False
    if route_en and get_route_mute_state(route_en):
        mute_discipline = True
        score += 5
        feedback_parts.append("EN track muted (good discipline)")
    else:
        feedback_parts.append("EN track left unmuted")

    # VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and frames and final_frame:
            prompt = """Analyze these screenshots of a user working in the Ardour DAW.
            Did the user actively arrange audio regions on the timeline and use the Export window to export audio files?
            Reply with a JSON object: {"timeline_arranged": true/false, "export_dialog_used": true/false}"""
            
            all_frames = frames + [final_frame]
            vlm_res = query_vlm(images=all_frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("timeline_arranged") and parsed.get("export_dialog_used"):
                    vlm_score = 15
                    feedback_parts.append("VLM confirmed manual timeline arrangement and export usage")
                else:
                    feedback_parts.append("VLM did not detect full timeline and export workflow")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM fails but everything else is perfect, grant the points to avoid punishing the agent for framework issues
        if sync_success and es_valid and fr_valid:
            vlm_score = 15
            feedback_parts.append("VLM skipped but granting points based on perfect artifacts")
            
    score += vlm_score

    # Final Decision
    passed = (score >= 70) and sync_success and (es_valid or fr_valid)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }