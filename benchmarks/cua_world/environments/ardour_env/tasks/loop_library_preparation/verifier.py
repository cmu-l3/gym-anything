#!/usr/bin/env python3
"""
Verifier for loop_library_preparation task.
Uses multi-criteria evaluation and checks VLM trajectory to prevent gaming.
"""

import json
import math
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- XML Parsing Helpers ---

def get_tempo(root):
    # Ardour 6
    tempos = root.findall('.//TempoMap/Tempo')
    # Ardour 7+
    if not tempos:
        tempos = root.findall('.//TempoMap/Tempos/Tempo')
    
    for t in tempos:
        # Check common attribute names for BPM across versions
        bpm = t.get('bpm') or t.get('beats-per-minute') or t.get('note-types-per-minute')
        if bpm:
            try:
                return float(bpm)
            except ValueError:
                pass
    return 120.0  # Default Ardour tempo

def get_audio_routes(root):
    routes = []
    for route in root.findall('.//Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes

def get_route_gain_linear(route):
    for ctrl in route.findall('.//Controllable'):
        if ctrl.get('name') in ('gaincontrol', 'gain'):
            try:
                return float(ctrl.get('value', '1.0'))
            except (ValueError, TypeError):
                return 1.0
    return 1.0

def get_regions_for_route(root, route_name):
    count = 0
    for pl in root.findall('.//Playlist'):
        name = pl.get('name', '')
        # Handle Ardour's playlist naming conventions (e.g. "Piano Loops" or "Piano Loops.1")
        base_name = name.rsplit('.', 1)[0] if '.' in name else name
        if base_name.lower() == route_name.lower():
            count += len(pl.findall('.//Region'))
    return count

def get_range_markers(root):
    markers = []
    for loc in root.findall('.//Location'):
        flags = loc.get('flags', '')
        # Exclude system ranges
        if any(f in flags for f in ('IsSessionRange', 'IsAutoLoop', 'IsAutoPunch')):
            continue
        
        # A range marker either has IsRangeMarker flag or its start != end
        is_range = 'IsRangeMarker' in flags or loc.get('start', '0') != loc.get('end', '0')
        if is_range:
            markers.append(loc.get('name', ''))
    return markers

# --- Main Verifier ---

def verify_loop_library_preparation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback = []

    # 1. Fetch JSON result from export script
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/loop_task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            fs_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read file system result: {e}"}
    finally:
        os.unlink(tmp_json.name)

    # 2. Fetch Ardour Session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()
    xml_data_available = False
    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
        xml_data_available = True
    except Exception as e:
        feedback.append(f"Ardour session XML could not be parsed: {e}")
    finally:
        os.unlink(tmp_xml.name)

    # 3. Fetch pack_info.txt
    info_remote = "/home/ga/Audio/loop_pack_delivery/pack_info.txt"
    tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_txt.close()
    pack_info_content = ""
    try:
        copy_from_env(info_remote, tmp_txt.name)
        with open(tmp_txt.name, 'r') as f:
            pack_info_content = f.read().lower()
    except Exception:
        pass
    finally:
        os.unlink(tmp_txt.name)

    # Evaluate Criteria
    target_route_name = "Piano Loops"
    route_found = False
    target_route = None
    
    if xml_data_available:
        # Criterion 1: Session Tempo (10 points)
        tempo = get_tempo(root)
        if 88 <= tempo <= 92:
            score += 10
            feedback.append("PASS: Session tempo set to 90 BPM.")
        else:
            feedback.append(f"FAIL: Tempo is {tempo} BPM (expected 90).")

        # Criterion 2: Track Name (10 points)
        routes = get_audio_routes(root)
        for r in routes:
            name = r.get('name', '')
            if name.lower() in ("piano loops", "piano_loops", "piano-loops"):
                route_found = True
                target_route = r
                break
        
        if route_found:
            score += 10
            feedback.append("PASS: Track renamed to 'Piano Loops'.")
        else:
            feedback.append("FAIL: No track named 'Piano Loops'.")
            # Fallback to the first available non-master track to check gain/regions
            if routes:
                target_route = routes[0]

        # Criterion 3: Multiple Regions (10 points)
        if target_route is not None:
            r_name = target_route.get('name', '')
            region_count = get_regions_for_route(root, r_name)
            if region_count >= 3:
                score += 10
                feedback.append(f"PASS: Track has {region_count} regions (>=3 required).")
            elif region_count > 0:
                score += 5
                feedback.append(f"PARTIAL: Track has only {region_count} region(s).")
            else:
                feedback.append("FAIL: No regions found on track.")

            # Criterion 4: Gain at -6 dB (10 points)
            gain_lin = get_route_gain_linear(target_route)
            # -6 dB is approx 0.501
            if 0.40 <= gain_lin <= 0.60:
                score += 10
                feedback.append(f"PASS: Track gain is correctly set (linear: {gain_lin:.3f} approx -6dB).")
            else:
                feedback.append(f"FAIL: Track gain is incorrect (linear: {gain_lin:.3f}).")
        
        # Criterion 5: Range Markers (15 points)
        markers = get_range_markers(root)
        loop_markers = [m for m in markers if 'loop' in m.lower()]
        if len(loop_markers) >= 3:
            score += 15
            feedback.append(f"PASS: Found {len(loop_markers)} range markers with 'Loop' in name.")
        elif len(loop_markers) > 0:
            score += 7
            feedback.append(f"PARTIAL: Found {len(loop_markers)} range markers (expected >= 3).")
        else:
            feedback.append("FAIL: No range markers named 'Loop' found.")

    # Criterion 6: Exported WAV files (15 points)
    valid_wavs = fs_data.get('valid_wav_count', 0)
    created_during = fs_data.get('wav_created_during_task', False)
    
    if valid_wavs >= 2 and created_during:
        score += 15
        feedback.append(f"PASS: {valid_wavs} WAV files properly exported.")
    elif valid_wavs > 0 and created_during:
        score += 8
        feedback.append(f"PARTIAL: Only {valid_wavs} WAV file(s) exported (expected >= 2).")
    else:
        feedback.append("FAIL: No new valid WAV files exported.")

    # Criterion 7: Metadata File (15 points)
    info_exists = fs_data.get('info_file_exists', False)
    if info_exists and pack_info_content:
        # Check tokens
        tokens_found = 0
        for token in ["moonlight", "90", "minor"]:
            if token in pack_info_content:
                tokens_found += 1
        
        # Check for numbers (for loop count)
        has_number = any(char.isdigit() for char in pack_info_content.replace('90', ''))
        if has_number:
            tokens_found += 1
            
        pts = int((tokens_found / 4) * 15)
        score += pts
        feedback.append(f"Metadata file analysis: {tokens_found}/4 required attributes found ({pts} pts).")
    else:
        feedback.append("FAIL: pack_info.txt missing or empty.")

    # Criterion 8: VLM Trajectory Verification (15 points)
    # Ensure agent actually used the GUI to prevent scripting/XML tampering
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames and query_vlm:
            prompt = """Analyze this sequence of screenshots from a user preparing a loop sample pack in an Audio DAW (Ardour).
Does the sequence show the user visibly interacting with the audio file, splitting it into pieces (regions), or adjusting track configurations?
Return JSON:
{
    "worked_in_daw": true/false,
    "confidence": "high/medium/low",
    "reasoning": "what you see"
}"""
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('worked_in_daw'):
                    vlm_score = 15
                    feedback.append("PASS (VLM): Verified visible progression in DAW.")
                else:
                    feedback.append("FAIL (VLM): Trajectory does not show expected DAW interaction.")
            else:
                # If VLM fails, grant points based on other strong signals to not penalize falsely
                if xml_data_available and route_found and valid_wavs > 0:
                    vlm_score = 15
                    feedback.append("VLM query failed, but strong programmatic signals indicate success.")
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        # Default grant if exception
        if xml_data_available and valid_wavs > 0:
            vlm_score = 15

    score += vlm_score

    # Finalize
    passed = score >= 60 and (valid_wavs > 0 or route_found)
    
    return {
        "passed": passed,
        "score": min(int(score), 100),
        "feedback": "\n".join(feedback)
    }