#!/usr/bin/env python3
"""
Verifier for broadcast_commercial_time_stretch task.
Occupation: Broadcast Technician / Audio Producer

Uses MULTIPLE INDEPENDENT SIGNALS to verify correct DSP time-stretching,
preventing agents from gaming the task by simply trimming the region.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_broadcast_commercial_time_stretch(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    score = 0.0
    feedback = []

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_duration_s = metadata.get('target_duration_s', 25.0)
    tolerance_s = metadata.get('tolerance_s', 0.2)
    sample_rate = metadata.get('sample_rate', 44100)
    
    target_samples = int(target_duration_s * sample_rate)
    tolerance_samples = int(tolerance_s * sample_rate)

    # 1. Copy result JSON
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Result JSON error: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    # 2. Copy session XML
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_session = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_session.close()
    
    try:
        copy_from_env(session_remote, tmp_session.name)
        tree = ET.parse(tmp_session.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Session XML error: {e}"}
    finally:
        if os.path.exists(tmp_session.name):
            os.unlink(tmp_session.name)

    # ================================================================
    # CRITERION 1: Track Setup (15 points)
    # ================================================================
    vo_route = None
    for route in root.iter('Route'):
        if route.get('default-type') == 'audio':
            if 'voiceover' in route.get('name', '').lower():
                vo_route = route
                break
    
    if not vo_route:
        feedback.append("FAIL: 'Voiceover' track not found.")
        return {"passed": False, "score": 0.0, "feedback": " | ".join(feedback)}
    
    route_name = vo_route.get('name', '')
    vo_regions = []
    
    # Locate regions on this track's playlist
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower() or pl_name.lower().startswith(route_name.lower()):
            for region in playlist.iter('Region'):
                vo_regions.append({
                    'name': region.get('name', ''),
                    'position': int(region.get('position', '0')),
                    'length': int(region.get('length', '0')),
                    'source-0': region.get('source-0', '')
                })

    if not vo_regions:
        feedback.append("FAIL: No audio regions found on 'Voiceover' track.")
        return {"passed": False, "score": 0.0, "feedback": " | ".join(feedback)}
    
    vo_regions.sort(key=lambda r: r['position'])
    first_region = vo_regions[0]
    
    if first_region['position'] <= int(1.0 * sample_rate):  # Within 1s of 0.0
        score += 15
        feedback.append("PASS: 'Voiceover' track exists with audio starting near 0.0s.")
    else:
        score += 5
        feedback.append(f"PARTIAL: Audio starts at {first_region['position']/sample_rate:.2f}s instead of 0.0s.")

    # ================================================================
    # CRITERION 2: Region Length (25 points)
    # ================================================================
    region_len = first_region['length']
    if abs(region_len - target_samples) <= tolerance_samples:
        score += 25
        feedback.append(f"PASS: Region length is {region_len/sample_rate:.2f}s (target 25.0s).")
    else:
        feedback.append(f"FAIL: Region length is {region_len/sample_rate:.2f}s (expected ~25.0s).")

    # ================================================================
    # CRITERION 3: Anti-Gaming DSP Operation (35 points) - REQUIRED
    # Verifies the underlying file was actually time-stretched, not trimmed.
    # ================================================================
    dsp_passed = False
    source_id = first_region['source-0']
    source_name = ""
    for source in root.iter('Source'):
        if source.get('id') == source_id:
            source_name = source.get('name', '')
            # Clean up Ardour's stereo split suffixes (%L or %R)
            if '%' in source_name:
                source_name = source_name.split('%')[0] + '.wav'
            break
            
    audiofiles_info = result.get('audiofiles_info', {})
    source_frames = 0
    
    if source_name:
        for fname, frames in audiofiles_info.items():
            if source_name.replace('.wav', '') in fname:
                source_frames = frames
                break
                
    if source_frames == 0 and audiofiles_info:
        # Fallback: check if ANY session audio file has the target duration
        for fname, frames in audiofiles_info.items():
            if abs(frames - target_samples) <= tolerance_samples:
                source_frames = frames
                source_name = fname
                break

    if source_frames > 0:
        if abs(source_frames - target_samples) <= tolerance_samples:
            score += 35
            dsp_passed = True
            feedback.append(f"PASS: Underlying audio file '{source_name}' is {source_frames/sample_rate:.2f}s, proving time-stretch DSP occurred.")
        else:
            feedback.append(f"FAIL: Underlying audio file is {source_frames/sample_rate:.2f}s. This indicates a trim operation, NOT a time-stretch.")
    else:
        feedback.append(f"FAIL: Could not determine valid underlying audio file length for source '{source_name}'.")

    # ================================================================
    # CRITERION 4: Export Verification (25 points)
    # ================================================================
    export_frames = result.get('exported_frames', 0)
    if export_frames > 0:
        if abs(export_frames - target_samples) <= tolerance_samples:
            score += 25
            feedback.append(f"PASS: Exported WAV is {export_frames/sample_rate:.2f}s.")
        else:
            feedback.append(f"FAIL: Exported WAV is {export_frames/sample_rate:.2f}s (expected ~25.0s).")
    else:
        feedback.append("FAIL: Exported WAV not found or invalid.")
        
    passed = (score >= 60.0) and dsp_passed
    
    # ================================================================
    # VLM Trajectory Verification (Optional Logging)
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and frames:
            prompt = "Look at these screenshots of a user working in Ardour DAW. Did they use the Time Stretch tool (clock/arrow icon) or Time Stretch dialog to compress the audio region? Reply with a short observation."
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res.get("success"):
                feedback.append(f"[VLM] {vlm_res.get('response', '')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }