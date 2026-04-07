#!/usr/bin/env python3
"""
Verifier for live jazz recording session setup task.
Occupation: Music Producer / Recording Engineer
Industry: Live Music / Recording Studios

Checks:
1. Snapshot file creation
2. Correct track names and counts
3. Session tempo mapped correctly
4. Track gain scaling
5. Placement of session markers
6. Correct muting of specific tracks
"""

import math
import os
import sys
import tempfile
import json
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ---------- Ardour XML helpers ----------

def get_audio_routes(root):
    """Get all standard audio tracks (excluding Master/Monitor buses)."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_gain_db(route):
    """Retrieve gain of a route in decibels."""
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
    """Check if the route is muted."""
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    # Backup check on route attributes
    return route.get('muted', '0') in ('1', 'yes', 'true')

def get_markers(root):
    """Extract user-placed session markers."""
    locations = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        # Ignore system boundaries and auto-loops
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        # Ardour sometimes flags standard markers as "IsMark"
        name = loc.get('name', '').strip()
        if not name:
            continue
        locations.append(int(loc.get('start', '0')))
    return locations

def get_tempo(root):
    """Extract primary session tempo."""
    for t in root.iter('Tempo'):
        bpm = t.get('note-types-per-minute') or t.get('beats-per-minute')
        if bpm:
            try:
                return float(bpm)
            except ValueError:
                pass
    return 120.0  # Default Ardour tempo


# ---------- Main Verifier ----------

def verify_jazz_session_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy JSON results securely
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

    score = 0
    feedback_parts = []
    
    snapshot_exists = result.get('snapshot_exists', False)
    snapshot_mtime = result.get('snapshot_mtime', 0)
    task_start = result.get('task_start', 0)
    
    # CRITERION 1: Snapshot creation (15 points)
    if snapshot_exists:
        if snapshot_mtime >= task_start:
            score += 15
            feedback_parts.append("PASS: Valid Snapshot 'Pre_Show_Template' created.")
            file_to_parse = result.get('snapshot_path')
        else:
            feedback_parts.append("FAIL: Snapshot exists but was created BEFORE task started (anti-gaming check).")
            file_to_parse = result.get('main_path')
    else:
        feedback_parts.append("FAIL: Snapshot 'Pre_Show_Template' was not created. Falling back to main session evaluation.")
        file_to_parse = result.get('main_path')
        
    # Attempt to copy and parse the XML file (snapshot preferred, main file fallback)
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    try:
        copy_from_env(file_to_parse, temp_xml.name)
        if not os.path.exists(temp_xml.name) or os.path.getsize(temp_xml.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Session file missing or empty."}
        
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"XML parsing failed: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # CRITERION 2: Track Names (20 points)
    routes = get_audio_routes(root)
    route_names = [r.get('name', '').lower().replace('_', ' ').replace('-', ' ') for r in routes]
    
    track_matches = 0
    targets = ["upright bass", "piano", "drums", "saxophone"]
    for target in targets:
        # Flexible matching
        if any(target in rn or (target.split()[1] if ' ' in target else target) in rn for rn in route_names):
            track_matches += 1
            
    track_score = track_matches * 5
    score += track_score
    feedback_parts.append(f"Tracks: Found {track_matches}/4 properly named tracks ({track_score} pts)")

    # CRITERION 3: Tempo Configuration (15 points)
    tempo = get_tempo(root)
    target_tempo = metadata.get('target_tempo', 140)
    tolerance = metadata.get('tempo_tolerance', 5)
    
    if abs(tempo - target_tempo) <= tolerance:
        score += 15
        feedback_parts.append(f"Tempo: Correct at {tempo} BPM (15 pts)")
    else:
        feedback_parts.append(f"Tempo: Incorrect ({tempo} BPM instead of {target_tempo} BPM)")

    # CRITERION 4: Gain Levels (20 points)
    bass_range = metadata.get('bass_gain_range', [-5.0, -1.0])
    drums_range = metadata.get('drums_gain_range', [-8.0, -4.0])
    
    bass_found, drums_found = False, False
    gain_score = 0
    for r in routes:
        name = r.get('name', '').lower()
        db = get_gain_db(r)
        
        if 'bass' in name:
            bass_found = True
            if bass_range[0] <= db <= bass_range[1]:
                gain_score += 10
                feedback_parts.append(f"Gain: Bass correctly staged at {db:.1f} dB")
            else:
                feedback_parts.append(f"Gain: Bass incorrect at {db:.1f} dB")
        elif 'drum' in name:
            drums_found = True
            if drums_range[0] <= db <= drums_range[1]:
                gain_score += 10
                feedback_parts.append(f"Gain: Drums correctly staged at {db:.1f} dB")
            else:
                feedback_parts.append(f"Gain: Drums incorrect at {db:.1f} dB")
                
    if not bass_found:
        feedback_parts.append("Gain: Could not find Bass track to check gain.")
    if not drums_found:
        feedback_parts.append("Gain: Could not find Drums track to check gain.")
        
    score += gain_score

    # CRITERION 5: Session Markers (20 points)
    markers = get_markers(root)
    unique_marker_positions = len(set(markers))
    
    if unique_marker_positions >= 3:
        score += 20
        feedback_parts.append(f"Markers: Found {unique_marker_positions} distinct markers (20 pts)")
    elif unique_marker_positions > 0:
        score += (unique_marker_positions * 6)
        feedback_parts.append(f"Markers: Only found {unique_marker_positions} distinct markers")
    else:
        feedback_parts.append("Markers: No chronological timeline markers found")

    # CRITERION 6: Mute State (10 points)
    sax_muted = False
    sax_found = False
    for r in routes:
        if 'sax' in r.get('name', '').lower():
            sax_found = True
            if is_route_muted(r):
                sax_muted = True
                break
                
    if sax_muted:
        score += 10
        feedback_parts.append("Mute: Saxophone track correctly muted (10 pts)")
    elif sax_found:
        feedback_parts.append("Mute: Saxophone track was NOT muted")
    else:
        feedback_parts.append("Mute: Saxophone track not found to verify mute state")

    # Final Evaluation Check
    passed = score >= 60 and snapshot_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }