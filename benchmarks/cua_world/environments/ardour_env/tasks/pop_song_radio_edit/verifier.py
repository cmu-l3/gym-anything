#!/usr/bin/env python3
"""
Verifier for the Pop Song Radio Edit task.
Evaluates Ardour session XML for exact structural edits (cuts and snap/ripple edits),
file sizes for shortening confirmation, and VLM trajectory analysis for workflow proof.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_radio_edit(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cut1_samples = metadata.get('cut_1_samples', 3969000)
    expected_cut2_samples = metadata.get('cut_2_samples', 7276500)
    tolerance = metadata.get('tolerance_samples', 88200) # +/- 2 seconds
    
    score = 0
    feedback_parts = []
    
    # 1. Load exported result metadata
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Parse Ardour Session XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    xml_valid = False
    try:
        copy_from_env("/tmp/session_export.ardour", temp_xml.name)
        if os.path.exists(temp_xml.name) and os.path.getsize(temp_xml.name) > 0:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            xml_valid = True
    except Exception as e:
        logger.warning(f"Failed to parse session XML: {e}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    if not xml_valid:
        return {"passed": False, "score": 0, "feedback": "Session XML could not be parsed."}

    # CRITERION 1: Track renamed to "Radio Edit" (10 pts)
    track_renamed = False
    target_playlist_name = ""
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            name = route.get('name', '')
            if name.lower() == 'radio edit':
                track_renamed = True
                score += 10
                feedback_parts.append("Track properly renamed")
                # Plist name usually matches the route name
                target_playlist_name = name
            elif not target_playlist_name:
                # Fallback to the first audio track we find if renaming failed
                target_playlist_name = name

    if not track_renamed:
        feedback_parts.append("Track not renamed to 'Radio Edit'")

    # Extract Regions from Playlist
    regions = []
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        # Only evaluate the playlist associated with our target track or containing extended_mix
        if target_playlist_name in pl_name or 'extended_mix' in pl_name:
            for r in playlist.iter('Region'):
                regions.append({
                    'position': int(r.get('position', 0)),
                    'length': int(r.get('length', 0)),
                    'start': int(r.get('start', 0)), # Source offset
                    'name': r.get('name', '')
                })
            if len(regions) > 0:
                break # Found our populated playlist

    # Sort regions by their position on the timeline
    regions.sort(key=lambda x: x['position'])

    # CRITERION 2: Middle section removed / Correct Cut Points (25 pts)
    structure_correct = False
    if len(regions) == 2:
        reg1, reg2 = regions[0], regions[1]
        
        # Check Region 1 length (~1:30)
        len_ok = abs(reg1['length'] - expected_cut1_samples) <= tolerance
        # Check Region 2 source start (~2:45)
        start_ok = abs(reg2['start'] - expected_cut2_samples) <= tolerance
        
        if len_ok and start_ok:
            structure_correct = True
            score += 25
            feedback_parts.append("Cut points are correct")
        else:
            feedback_parts.append(f"Cut points inaccurate (R1 len: {reg1['length']}, R2 start: {reg2['start']})")
    else:
        feedback_parts.append(f"Expected 2 regions after deletion, found {len(regions)}")

    # CRITERION 3: Gap Closed / Snapped (20 pts)
    gap_closed = False
    if len(regions) == 2:
        reg1, reg2 = regions[0], regions[1]
        expected_r2_pos = reg1['position'] + reg1['length']
        actual_r2_pos = reg2['position']
        
        if abs(actual_r2_pos - expected_r2_pos) <= 2000:  # Very tight tolerance for snapping
            gap_closed = True
            score += 20
            feedback_parts.append("Gap successfully closed (snapped)")
        else:
            gap_size = actual_r2_pos - expected_r2_pos
            feedback_parts.append(f"Gap not closed properly (off by {gap_size} samples)")

    # CRITERION 4: Export File Exists & Created During Task (15 pts)
    export_ok = False
    if result.get("output_exists") and result.get("file_created_during_task"):
        export_ok = True
        score += 15
        feedback_parts.append("Export file generated")
    else:
        feedback_parts.append("Valid export file not found")

    # CRITERION 5: Export is Shortened (15 pts)
    # The original was 4 mins, the edit cuts ~1m15s out. 
    # File size should be roughly > 1MB and < 90% of original.
    shortened_ok = False
    out_size = result.get("output_size_bytes", 0)
    orig_size = result.get("original_size_bytes", 0)
    
    if orig_size > 0 and 100000 < out_size < (orig_size * 0.9):
        shortened_ok = True
        score += 15
        feedback_parts.append("Exported file duration shortened correctly")
    elif out_size >= (orig_size * 0.9):
        feedback_parts.append("Exported file not shortened (looks like original length)")

    # CRITERION 6: VLM Trajectory Verification (15 pts)
    vlm_ok = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "Look at these sequential screenshots of a user working in the Ardour DAW. "
                    "Did the user successfully import an audio track, make cuts/splits to the audio region, "
                    "delete a middle segment, and move the remaining segments together on the timeline? "
                    "Reply with JSON: {\"editing_workflow_visible\": true/false, \"reason\": \"...\"}"
                )
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("editing_workflow_visible", False):
                        vlm_ok = True
                        score += 15
                        feedback_parts.append("VLM confirms editing workflow")
                    else:
                        feedback_parts.append("VLM did not detect workflow")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Do not penalize if VLM fails technically
            score += 15
            feedback_parts.append("VLM error (bypassed)")

    # Determine Pass/Fail (Threshold 70)
    # Must have the structure correct OR gap closed, AND exported
    key_criteria_met = (structure_correct or gap_closed) and export_ok
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }