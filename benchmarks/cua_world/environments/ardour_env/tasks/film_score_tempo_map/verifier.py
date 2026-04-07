#!/usr/bin/env python3
"""
Verifier for film_score_tempo_map task.

Parses the Ardour session XML to check tempo map, meter changes,
location markers, and track naming. Validates via VLM trajectory.
"""

import os
import json
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_tempos_and_meters(root):
    """Robust extraction across Ardour 6, 7, and 8 XML structures."""
    tempos = []
    meters = []
    tempo_map = root.find('.//TempoMap')
    
    if tempo_map is not None:
        for elem in tempo_map.iter():
            # Bar resolution
            bbt = elem.get('bbt') or elem.get('start')
            if not bbt:
                continue
            parts = bbt.split('|')
            if not parts[0].isdigit():
                continue
            bar = int(parts[0])
            
            # Check Tempo
            bpm = elem.get('beats-per-minute') or elem.get('note-types-per-minute') or elem.get('bpm')
            if bpm is not None:
                tempos.append({'bar': bar, 'bpm': float(bpm)})
                
            # Check Meter
            div = elem.get('divisions-per-bar') or elem.get('beats-per-bar')
            if div is not None:
                meters.append({'bar': bar, 'divisions': float(div)})
                
    return tempos, meters


def extract_markers(root):
    """Extract named location markers, ignoring system loops/punches."""
    markers = []
    locations = root.find('.//Locations')
    if locations is not None:
        for loc in locations.findall('Location'):
            flags = loc.get('flags', '')
            if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
                continue
            name = loc.get('name', '').strip()
            if not name or name.lower() in ('session', 'loop', 'punch'):
                continue
            markers.append(name)
    return markers


def get_audio_routes(root):
    """Extract names of non-bus audio routes."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        name = route.get('name', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags or name.lower() in ('master', 'monitor'):
            continue
        if route.get('default-type', '') == 'audio':
            routes.append(name)
    return routes


def find_nearest_entry(entries, target_bar, tolerance=1):
    """Find the best matching entry near the target bar."""
    best = None
    best_dist = float('inf')
    for entry in entries:
        dist = abs(entry['bar'] - target_bar)
        if dist <= tolerance and dist < best_dist:
            best = entry
            best_dist = dist
    return best


def marker_matches(found_markers, expected_marker):
    """Check if expected marker exists in found markers (case-insensitive substring)."""
    expected_lower = expected_marker.lower()
    for fm in found_markers:
        fm_lower = fm.lower()
        if expected_lower in fm_lower or fm_lower in expected_lower:
            return True
        # Specific aliases handling
        if expected_lower == 'prologue' and 'intro' in fm_lower:
            return True
        if expected_lower == 'chase' and 'action' in fm_lower:
            return True
        if expected_lower == 'finale' and 'end' in fm_lower:
            return True
    return False


def verify_film_score_tempo_map(traj, env_info, task_info):
    """
    Main verification logic.
    Scores out of 100 based on programmatic checks + VLM validation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    bpm_tolerance = metadata.get('bpm_tolerance', 5)
    bar_tolerance = metadata.get('bar_tolerance', 1)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # Extract exported files
    # ================================================================
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_result = json.load(f)
            
        copy_from_env("/tmp/session_export.ardour", tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse results: {str(e)}"}
    finally:
        for tmp_file in [tmp_json, tmp_xml]:
            if os.path.exists(tmp_file.name):
                os.unlink(tmp_file.name)

    # Anti-gaming check
    if not export_result.get('modified_during_task', False):
        feedback_parts.append("WARNING: Session file was not modified after task started.")

    # ================================================================
    # PROGRAMMATIC CRITERIA (80 Points)
    # ================================================================
    tempos, meters = extract_tempos_and_meters(root)
    markers = extract_markers(root)
    routes = get_audio_routes(root)
    
    # 1. Initial Tempo: Bar 1, 72 BPM (10 pts)
    t1 = find_nearest_entry(tempos, 1, bar_tolerance)
    if t1 and abs(t1['bpm'] - 72) <= bpm_tolerance:
        score += 10
        feedback_parts.append("Initial tempo configured correctly")
    elif t1 and abs(t1['bpm'] - 120) <= 1:
        feedback_parts.append("Initial tempo still default 120 BPM")
    elif t1:
        feedback_parts.append(f"Initial tempo incorrect ({t1['bpm']} BPM)")
    else:
        feedback_parts.append("No initial tempo found")

    # 2. Chase Tempo: Bar 9, 152 BPM (10 pts)
    t9 = find_nearest_entry(tempos, 9, bar_tolerance)
    if t9 and abs(t9['bpm'] - 152) <= bpm_tolerance:
        score += 10
        feedback_parts.append("Chase tempo configured correctly")
    elif t9:
        feedback_parts.append(f"Chase tempo incorrect ({t9['bpm']} BPM)")
    else:
        feedback_parts.append("Chase tempo not found at Bar 9")

    # 3. Waltz Tempo: Bar 21, 108 BPM (10 pts)
    t21 = find_nearest_entry(tempos, 21, bar_tolerance)
    if t21 and abs(t21['bpm'] - 108) <= bpm_tolerance:
        score += 10
        feedback_parts.append("Waltz tempo configured correctly")
    elif t21:
        feedback_parts.append(f"Waltz tempo incorrect ({t21['bpm']} BPM)")
    else:
        feedback_parts.append("Waltz tempo not found at Bar 21")

    # 4. Finale Tempo: Bar 33, 132 BPM (10 pts)
    t33 = find_nearest_entry(tempos, 33, bar_tolerance)
    if t33 and abs(t33['bpm'] - 132) <= bpm_tolerance:
        score += 10
        feedback_parts.append("Finale tempo configured correctly")
    elif t33:
        feedback_parts.append(f"Finale tempo incorrect ({t33['bpm']} BPM)")
    else:
        feedback_parts.append("Finale tempo not found at Bar 33")

    # 5. Waltz Meter: Bar 21, 3/4 Time (10 pts)
    m21 = find_nearest_entry(meters, 21, bar_tolerance)
    if m21 and abs(m21['divisions'] - 3.0) < 0.1:
        score += 10
        feedback_parts.append("Waltz meter configured correctly (3/4)")
    elif m21:
        feedback_parts.append(f"Waltz meter incorrect ({int(m21['divisions'])} divisions)")
    else:
        feedback_parts.append("Waltz meter change not found at Bar 21")

    # 6. Finale Meter: Bar 33, 4/4 Time (5 pts)
    m33 = find_nearest_entry(meters, 33, bar_tolerance)
    if m33 and abs(m33['divisions'] - 4.0) < 0.1 and m33['bar'] >= 31:
        score += 5
        feedback_parts.append("Finale meter configured correctly (4/4)")
    else:
        feedback_parts.append("Finale meter return not found at Bar 33")

    # 7. Section Markers (15 pts total)
    expected_markers = metadata.get('expected_markers', [])
    matched_markers = sum(1 for em in expected_markers if marker_matches(markers, em))
    
    if matched_markers >= 4:
        score += 15
        feedback_parts.append("All location markers correctly placed")
    elif matched_markers > 0:
        pts = int((matched_markers / 4) * 15)
        score += pts
        feedback_parts.append(f"Some location markers placed ({matched_markers}/4)")
    else:
        feedback_parts.append("No correct location markers found")

    # 8. Track Rename (10 pts)
    track_renamed = False
    still_default = False
    for r in routes:
        if "score sketch" in r.lower():
            track_renamed = True
        if "audio 1" in r.lower().replace(" ", ""):
            still_default = True

    if track_renamed and not still_default:
        score += 10
        feedback_parts.append("Track successfully renamed")
    elif track_renamed and still_default:
        score += 5
        feedback_parts.append("Track renamed but default track still exists")
    else:
        feedback_parts.append("Track not renamed appropriately")

    # ================================================================
    # VLM CRITERIA: Trajectory / Workflow Check (20 Points)
    # ================================================================
    vlm_points = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are evaluating a desktop agent configuring Ardour's Tempo Map and Time Signatures.
Please analyze these chronological frames and determine if the agent actively manipulated the tempo/meter settings.

Look for:
1. The 'Tempo' or 'Meter' dialogs being open (usually pop-ups).
2. The agent interacting with the tempo ruler or marker ruler at the top of the timeline.
3. Track name being edited in the track header.

Output JSON:
{
  "tempo_meter_interacted": true/false,
  "confidence": "high/medium/low",
  "reason": "short explanation"
}"""
            
            result = query_vlm(prompt=prompt, images=frames)
            
            if result and result.get("success") and result.get("parsed"):
                parsed = result["parsed"]
                if parsed.get("tempo_meter_interacted", False):
                    vlm_points = 20
                    feedback_parts.append("VLM confirms tempo/meter interaction")
                else:
                    feedback_parts.append("VLM did not observe tempo/meter interaction")
            else:
                # If VLM fails, assume they did it if programmatic score is high
                if score >= 40:
                    vlm_points = 20
                    feedback_parts.append("VLM check failed; awarded points based on XML success")
        else:
            if score >= 40:
                vlm_points = 20
                feedback_parts.append("No frames for VLM; awarded points based on XML success")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Fallback
        if score >= 40:
            vlm_points = 20

    score += vlm_points
    
    # Final pass determination
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }