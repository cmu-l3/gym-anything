#!/usr/bin/env python3
"""
Verifier for mastering_chain_setup task.

Parses the Ardour session XML to verify:
1. Audio track renamed to "Stereo Mix"
2. EQ plugin inserted on Master bus
3. Compressor plugin inserted on Master bus
4. Plugins are in the correct order (EQ -> Compressor)
5. Session was saved by the agent (file modification time check)
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Default names to check if track was renamed at all
DEFAULT_NAMES = ["audio 1", "audio 2", "audio 3", "audio-1", "audio-2", "master", "monitor"]


def processor_matches(proc, keywords, uris):
    """Check if a Processor XML element matches plugin criteria."""
    name = (proc.get("name", "") or "").lower()
    for kw in keywords:
        if kw in name:
            return True
            
    for lv2 in proc.iter("lv2"):
        uri = (lv2.get("uri", "") or "").lower()
        for u in uris:
            if u in uri:
                return True
                
    return False


def verify_mastering_chain_setup(traj, env_info, task_info):
    """
    Verification Logic for mastering chain setup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_track_name = metadata.get('expected_track_name', "Stereo Mix").lower()
    eq_keywords = metadata.get('eq_keywords', ["eq", "equalizer", "a-eq", "ace eq"])
    eq_uris = metadata.get('eq_uris', ["urn:ardour:a-eq"])
    comp_keywords = metadata.get('comp_keywords', ["comp", "compressor", "a-comp", "ace comp"])
    comp_uris = metadata.get('comp_uris', ["urn:ardour:a-comp"])
    pass_threshold = metadata.get('pass_threshold', 60)

    score = 0
    feedback_parts = []
    subscores = {}

    # ================================================================
    # Read result timestamps
    # ================================================================
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task_result.json: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not read task results file"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ================================================================
    # Copy Session XML
    # ================================================================
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        if not os.path.exists(tmp_xml.name) or os.path.getsize(tmp_xml.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Session file missing or empty"}
            
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse session XML: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # ================================================================
    # Criterion 1: Track Renamed (20 pts)
    # ================================================================
    audio_tracks = []
    for route in root.iter("Route"):
        flags = route.get("flags", "")
        dtype = route.get("default-type", "")
        if "MasterOut" not in flags and "MonitorOut" not in flags:
            if dtype == "audio":
                audio_tracks.append(route)

    renamed_score = 0
    if audio_tracks:
        for track in audio_tracks:
            name = track.get("name", "").lower().strip()
            # Remove common separators for matching (e.g., "Stereo-Mix" -> "stereomix")
            normalized_name = name.replace(" ", "").replace("_", "").replace("-", "")
            expected_normalized = expected_track_name.replace(" ", "")
            
            if expected_normalized in normalized_name:
                renamed_score = 20
                feedback_parts.append(f"Track correctly renamed to '{track.get('name')}'")
                break
            elif name and name not in DEFAULT_NAMES:
                renamed_score = 8
                
        if renamed_score == 8:
            feedback_parts.append("Track renamed, but not to 'Stereo Mix'")
        elif renamed_score == 0:
            feedback_parts.append("Audio track was not renamed")
    else:
        feedback_parts.append("No audio tracks found in session")

    score += renamed_score
    subscores['track_renamed'] = renamed_score

    # ================================================================
    # Find Master Bus
    # ================================================================
    master_bus = None
    for route in root.iter("Route"):
        flags = route.get("flags", "")
        if "MasterOut" in flags or route.get("name", "").lower() == "master":
            master_bus = route
            break

    # ================================================================
    # Criteria 2-4: Master Bus Plugins and Order
    # ================================================================
    eq_score = 0
    comp_score = 0
    order_score = 0

    if master_bus is not None:
        eq_idx = -1
        comp_idx = -1
        
        processors = list(master_bus.iter("Processor"))
        for idx, proc in enumerate(processors):
            if processor_matches(proc, eq_keywords, eq_uris):
                eq_idx = idx
            if processor_matches(proc, comp_keywords, comp_uris):
                comp_idx = idx

        if eq_idx != -1:
            eq_score = 25
            feedback_parts.append("EQ plugin found on Master bus")
        else:
            feedback_parts.append("EQ plugin NOT found on Master bus")

        if comp_idx != -1:
            comp_score = 25
            feedback_parts.append("Compressor plugin found on Master bus")
        else:
            feedback_parts.append("Compressor plugin NOT found on Master bus")

        if eq_idx != -1 and comp_idx != -1:
            if eq_idx < comp_idx:
                order_score = 15
                feedback_parts.append("Plugins are in correct order (EQ -> Compressor)")
            else:
                feedback_parts.append("Plugin order incorrect (Compressor is before EQ)")
    else:
        feedback_parts.append("Master bus not found in session")

    score += eq_score + comp_score + order_score
    subscores['eq_inserted'] = eq_score
    subscores['comp_inserted'] = comp_score
    subscores['plugin_order'] = order_score

    # ================================================================
    # Criterion 5: Session Saved (15 pts)
    # Anti-gaming: Ensure modification time > task start time
    # ================================================================
    session_start_mtime = result.get('session_start_mtime', 0)
    session_end_mtime = result.get('session_end_mtime', 0)
    task_start_time = result.get('task_start_time', 0)
    
    save_score = 0
    if session_end_mtime > task_start_time and session_end_mtime > session_start_mtime:
        save_score = 15
        feedback_parts.append("Session was properly saved")
    else:
        feedback_parts.append("Session was not saved after modifications")

    score += save_score
    subscores['session_saved'] = save_score

    # ================================================================
    # Final Result Compilation
    # ================================================================
    # Prevent pass if no actual plugins were inserted
    plugins_inserted = (eq_score > 0 or comp_score > 0)
    
    passed = (score >= pass_threshold) and plugins_inserted

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": subscores
    }