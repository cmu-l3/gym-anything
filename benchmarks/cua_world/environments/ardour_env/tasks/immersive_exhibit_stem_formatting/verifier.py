#!/usr/bin/env python3
"""
Verifier for immersive_exhibit_stem_formatting task.
Occupation: Audio and Video Equipment Technician (SOC 27-4011)
Industry: Museums, Historical Sites, and Similar Institutions

Verifies the agent correctly aligned, trimmed, and configured audio stems
for a hardware looper exhibit.
"""

import math
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAMPLE_RATE = 44100
TARGET_LENGTH_SAMPLES = 882000  # 20.0 seconds at 44.1 kHz
TOLERANCE_SAMPLES = 2000        # ~45ms tolerance for manual dragging


def get_audio_routes(root):
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def find_route_by_keywords(root, keywords):
    for route in get_audio_routes(root):
        rname = route.get('name', '').lower()
        if any(kw in rname for kw in keywords):
            return route
    return None


def get_route_gain_db(route):
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
    # Check controllable
    for ctrl in route.iter('Controllable'):
        if ctrl.get('name') == 'mute':
            return ctrl.get('value', '0') in ('1', 'yes', 'true')
    # Check attribute
    return route.get('muted', '0') in ('1', 'yes', 'true')


def get_regions_for_route(root, route_name):
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                })
    return regions


def get_range_markers(root):
    markers = []
    for loc in root.iter('Location'):
        flags = loc.get('flags', '')
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        try:
            start = int(loc.get('start', '0'))
            end = int(loc.get('end', '0'))
            if end > start:  # Valid range marker
                markers.append({
                    'name': loc.get('name', ''),
                    'start': start,
                    'end': end,
                })
        except ValueError:
            pass
    return markers


def verify_immersive_exhibit_stem_formatting(traj, env_info, task_info):
    """
    Multi-criterion verifier for immersive exhibit stem formatting.

    Criteria (100 pts total, pass >= 70):
      1. Track Creation & Naming (15 pts)
      2. Temporal Alignment (0:00.000) (15 pts)
      3. Precise Region Trimming (20.0s / 882k samples) (25 pts) - CRITICAL
      4. Range Marker Setup (15 pts)
      5. Hardware Mix States (+3dB Bass, Muted FX) (15 pts)
      6. Session Saved & Exported (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # 1. Fetch Session JSON Export Result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    export_result = {}
    try:
        copy_from_env("/tmp/exhibit_formatting_result.json", tmp_json.name)
        import json
        with open(tmp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load export result JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Fetch Session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session file not accessible: {e}"}

    if not os.path.exists(tmp_xml.name) or os.path.getsize(tmp_xml.name) == 0:
        return {"passed": False, "score": 0.0, "feedback": "Session file empty or missing"}

    try:
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"Session XML parse error: {e}"}

    # ================================================================
    # CRITERION 1: Track Creation & Naming (15 pts)
    # ================================================================
    tactile_keywords = ['tactile', 'bass', 'rumble']
    ambience_keywords = ['overhead', 'ambience', 'ambient']
    fx_keywords = ['spot', 'fx']

    tactile_route = find_route_by_keywords(root, tactile_keywords)
    ambience_route = find_route_by_keywords(root, ambience_keywords)
    fx_route = find_route_by_keywords(root, fx_keywords)

    tracks_found = sum(1 for r in [tactile_route, ambience_route, fx_route] if r is not None)
    
    if tracks_found == 3:
        score += 15.0
        feedback.append("PASS: All 3 tracks created with correct names.")
    elif tracks_found > 0:
        score += tracks_found * 5.0
        feedback.append(f"PARTIAL: Found {tracks_found}/3 required tracks.")
    else:
        feedback.append("FAIL: Required exhibit tracks not found.")

    # Gather regions for found routes
    all_regions = []
    if tactile_route:
        all_regions.extend(get_regions_for_route(root, tactile_route.get('name')))
    if ambience_route:
        all_regions.extend(get_regions_for_route(root, ambience_route.get('name')))
    if fx_route:
        all_regions.extend(get_regions_for_route(root, fx_route.get('name')))

    if not all_regions:
        feedback.append("FAIL: No audio regions found on the exhibit tracks.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    # ================================================================
    # CRITERION 2: Temporal Alignment (15 pts)
    # All regions must start at 0
    # ================================================================
    aligned_count = 0
    for r in all_regions:
        if abs(r['position']) <= TOLERANCE_SAMPLES:
            aligned_count += 1
            
    if len(all_regions) >= 3 and aligned_count == len(all_regions):
        score += 15.0
        feedback.append("PASS: All regions aligned exactly to 0:00.000.")
    elif aligned_count > 0:
        score += (aligned_count / len(all_regions)) * 10.0
        feedback.append(f"PARTIAL: {aligned_count}/{len(all_regions)} regions aligned to start.")
    else:
        feedback.append("FAIL: Regions are not aligned to the start timeline.")

    # ================================================================
    # CRITERION 3: Precise Region Trimming (25 pts) - CRITICAL
    # Lengths must be 882000 samples (20 seconds)
    # ================================================================
    trimmed_count = 0
    for r in all_regions:
        if abs(r['length'] - TARGET_LENGTH_SAMPLES) <= TOLERANCE_SAMPLES:
            trimmed_count += 1

    trimming_successful = False
    if len(all_regions) >= 3 and trimmed_count == len(all_regions):
        score += 25.0
        trimming_successful = True
        feedback.append("PASS: All regions perfectly trimmed to 20.0s.")
    elif trimmed_count > 0:
        score += (trimmed_count / len(all_regions)) * 15.0
        trimming_successful = True
        feedback.append(f"PARTIAL: {trimmed_count}/{len(all_regions)} regions trimmed to 20.0s.")
    else:
        feedback.append("FAIL: Regions were not properly trimmed to 20.0 seconds.")

    # ================================================================
    # CRITERION 4: Range Marker Setup (15 pts)
    # Range Marker spanning 0 to 882000
    # ================================================================
    markers = get_range_markers(root)
    valid_marker = False
    for m in markers:
        # Check if bounds match 0 to 20s
        if (abs(m['start'] - 0) <= TOLERANCE_SAMPLES and
            abs(m['end'] - TARGET_LENGTH_SAMPLES) <= TOLERANCE_SAMPLES):
            valid_marker = True
            break
            
    if valid_marker:
        score += 15.0
        feedback.append("PASS: Valid exhibit range marker found.")
    else:
        feedback.append("FAIL: Correctly positioned range marker not found.")

    # ================================================================
    # CRITERION 5: Hardware Mix States (15 pts)
    # Tactile Bass = +3dB, Spot FX = Muted
    # ================================================================
    mix_score = 0.0
    
    # Tactile Bass Gain (+3 dB tolerance +2 to +4)
    if tactile_route:
        bass_gain = get_route_gain_db(tactile_route)
        if 2.0 <= bass_gain <= 4.0:
            mix_score += 7.5
            feedback.append("PASS: Tactile Bass gain boosted.")
        else:
            feedback.append(f"FAIL: Tactile Bass gain is {bass_gain:.1f} dB (expected ~+3 dB).")
            
    # Spot FX Mute
    if fx_route:
        if is_route_muted(fx_route):
            mix_score += 7.5
            feedback.append("PASS: Spot FX track correctly muted.")
        else:
            feedback.append("FAIL: Spot FX track not muted.")
            
    score += mix_score

    # ================================================================
    # CRITERION 6: Session Exported (15 pts)
    # ================================================================
    export_status = export_result.get('export_exists', 'false')
    export_size = export_result.get('export_size', 0)
    
    if export_status == "true" and export_size > 1024:
        score += 15.0
        feedback.append("PASS: Mix correctly exported to final directory.")
    elif export_status == "true_wrong_location":
        score += 7.0
        feedback.append("PARTIAL: Mix exported but to default directory, not exhibit_final.")
    else:
        feedback.append("FAIL: Exported WAV mix not found.")

    # Clean up
    if os.path.exists(tmp_xml.name):
        os.unlink(tmp_xml.name)

    passed = score >= 70.0 and trimming_successful

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }