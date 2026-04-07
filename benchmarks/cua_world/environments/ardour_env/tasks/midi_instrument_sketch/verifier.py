#!/usr/bin/env python3
"""
Verifier for midi_instrument_sketch task.
Checks session XML for MIDI track, instrument plugin, imported MIDI region,
and file system for rendered WAV export.
"""

import os
import sys
import json
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_midi_routes(root):
    """Find all MIDI routes (tracks) in the session XML."""
    midi_routes = []
    for route in root.iter("Route"):
        name = route.get("name", "")
        dtype = route.get("default-type", "")
        if name.lower() in ("master", "monitor") or "MasterBus" in route.get("flags", ""):
            continue
        
        is_midi = False
        if dtype == "midi":
            is_midi = True
        else:
            # Fallback: check diskstream type if default-type is absent
            for ds in route.iter("Diskstream"):
                if ds.get("type", "") == "midi":
                    is_midi = True
                    break
        
        if is_midi:
            midi_routes.append(route)
    return midi_routes


def verify_midi_instrument_sketch(traj, env_info, task_info):
    """
    Verification Logic:
    1. MIDI track exists (20 pts)
    2. Track named correctly (10 pts)
    3. Virtual instrument present (25 pts)
    4. MIDI region imported (25 pts)
    5. Rendered WAV exported > 10KB (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_keywords = metadata.get('expected_track_keywords', ['tension', 'motif'])
    synth_keywords = metadata.get('synth_keywords', ['synth', 'reasonable', 'fluid', 'instrument', 'piano'])
    pass_threshold = metadata.get('pass_threshold', 55)

    score = 0
    feedback_parts = []

    # 1. Load JSON results
    result_json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_json_tmp.close()
    try:
        copy_from_env("/tmp/midi_instrument_sketch_result.json", result_json_tmp.name)
        with open(result_json_tmp.name, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(result_json_tmp.name):
            os.unlink(result_json_tmp.name)

    task_start = results.get('task_start', 0)

    # 2. Copy and parse Ardour Session XML
    session_xml_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    session_xml_tmp.close()
    try:
        copy_from_env("/home/ga/Audio/sessions/MyProject/MyProject.ardour", session_xml_tmp.name)
        tree = ET.parse(session_xml_tmp.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Ardour XML: {e}"}
    finally:
        if os.path.exists(session_xml_tmp.name):
            os.unlink(session_xml_tmp.name)

    # Criterion 1: MIDI Track Exists
    midi_routes = get_midi_routes(root)
    if midi_routes:
        score += 20
        feedback_parts.append(f"MIDI track found ({len(midi_routes)} total)")
    else:
        feedback_parts.append("No MIDI track found")

    # Criterion 2: Track Named Correctly
    has_correct_name = False
    if midi_routes:
        for route in midi_routes:
            name = route.get("name", "").lower()
            if any(kw in name for kw in expected_keywords):
                score += 10
                feedback_parts.append(f"Track named correctly ('{route.get('name')}')")
                has_correct_name = True
                break
        
        if not has_correct_name:
            for route in midi_routes:
                name = route.get("name", "").lower().strip()
                if name and name not in ("midi 1", "midi 2", "midi"):
                    score += 3
                    feedback_parts.append(f"Track renamed ('{route.get('name')}') but missing expected keywords")
                    break

    # Criterion 3: Virtual Instrument Present
    utility_types = ["meter", "amp", "fader", "monitor", "trim", "polarity"]
    instrument_found = False
    
    if midi_routes:
        for route in midi_routes:
            for proc in route.iter("Processor"):
                proc_type = proc.get("type", "").lower()
                proc_name = proc.get("name", "").lower()
                
                if proc_type in utility_types or proc_name in utility_types:
                    continue
                
                # Check LV2 URIs
                for lv2 in proc.iter("lv2"):
                    uri = lv2.get("uri", "").lower()
                    if any(s in uri for s in synth_keywords):
                        score += 25
                        feedback_parts.append(f"Synth instrument found (URI: {uri})")
                        instrument_found = True
                        break
                
                if instrument_found:
                    break

                # Check general plugin name for indicators
                if proc_type in ("lv2", "ladspa", "vst", "vst3", "insert"):
                    if any(s in proc_name for s in synth_keywords):
                        score += 25
                        feedback_parts.append(f"Synth instrument found ('{proc.get('name')}')")
                        instrument_found = True
                        break
                    elif proc_type != "insert":
                        # Partial credit for adding ANY non-utility plugin to the MIDI track
                        score += 10
                        feedback_parts.append(f"Plugin '{proc.get('name')}' found, but not recognized as a synth")
                        instrument_found = True
                        break
                        
            if instrument_found:
                break

    if not instrument_found and midi_routes:
        feedback_parts.append("No instrument plugin found on MIDI track")

    # Criterion 4: MIDI Region Imported
    region_found = False
    if midi_routes:
        # Build set of expected playlist names for the MIDI routes
        midi_playlist_names = set()
        for route in midi_routes:
            for ds in route.iter("Diskstream"):
                pl_name = ds.get("playlist", "")
                if pl_name:
                    midi_playlist_names.add(pl_name)
            
            r_name = route.get("name", "")
            if r_name:
                midi_playlist_names.add(r_name)
                midi_playlist_names.add(f"{r_name}.1")

        for playlist in root.iter("Playlist"):
            pl_name = playlist.get("name", "")
            pl_type = playlist.get("type", "")
            
            is_midi_pl = (
                pl_type == "midi" or 
                pl_name in midi_playlist_names or
                any(mn.lower() in pl_name.lower() for mn in midi_playlist_names if mn)
            )
            
            if is_midi_pl:
                regions = list(playlist.iter("Region"))
                if regions:
                    score += 25
                    feedback_parts.append(f"MIDI region imported to playlist '{pl_name}'")
                    region_found = True
                    break

        if not region_found:
            # Look broadly for midi-like region names in any playlist just in case
            for playlist in root.iter("Playlist"):
                for region in playlist.iter("Region"):
                    r_name = region.get("name", "").lower()
                    if "tension" in r_name or "motif" in r_name or "midi" in r_name:
                        score += 25
                        feedback_parts.append(f"MIDI region '{region.get('name')}' found")
                        region_found = True
                        break
                if region_found:
                    break

    if not region_found:
        feedback_parts.append("No imported MIDI region found in session")

    # Criterion 5: Rendered WAV Exported
    wav_exists = results.get('wav_exists', False)
    wav_size = results.get('wav_size_bytes', 0)
    wav_mtime = results.get('wav_mtime', 0)
    
    if wav_exists:
        # Anti-gaming: ensure the file was made/modified during the task run
        # Added a 10s buffer in case of slight clock differences
        if wav_mtime >= (task_start - 10):
            if wav_size > 10240: # > 10KB
                score += 20
                feedback_parts.append(f"Rendered WAV exported successfully ({wav_size/1024:.1f} KB)")
            elif wav_size > 44: # Header only or extremely short
                score += 10
                feedback_parts.append(f"WAV exported but size is suspiciously small ({wav_size} bytes)")
            else:
                feedback_parts.append("Exported WAV is empty")
        else:
            feedback_parts.append("WAV file exists but was created BEFORE the task started (anti-gaming block)")
    else:
        feedback_parts.append("No rendered WAV file exported")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }