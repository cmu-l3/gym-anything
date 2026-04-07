#!/usr/bin/env python3
"""
Verifier for podcast_double_ender_sync task.
Evaluates precise mathematical alignment of audio regions in Ardour XML,
along with VLM verification of the agent's workflow.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_audio_routes(root):
    """Get audio tracks from Ardour XML."""
    routes = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' in flags or 'MonitorOut' in flags:
            continue
        if route.get('default-type') == 'audio':
            routes.append(route)
    return routes


def find_playlist_for_route(root, route_name):
    """Find the active playlist for a given route name."""
    for playlist in root.iter('Playlist'):
        pl_name = playlist.get('name', '')
        base = pl_name.rsplit('.', 1)[0] if '.' in pl_name else pl_name
        if base.lower() == route_name.lower():
            return playlist
    return None


def get_main_region(playlist):
    """Find the longest region in a playlist (avoids deleted/split fragments)."""
    if playlist is None:
        return None
    regions = list(playlist.iter('Region'))
    if not regions:
        return None
    # Return the region with the longest duration to ensure we are looking at the speech part
    return max(regions, key=lambda r: int(r.get('length', '0')))


def has_active_fade_in(region):
    """Check if region has an active fade-in applied."""
    if region is None:
        return False
    
    # Check attribute
    if region.get('fade-in-active') == '1':
        return True
        
    # Check child element
    fade_in = region.find('FadeIn')
    if fade_in is not None and fade_in.get('active') == '1':
        return True
        
    return False


def verify_double_ender_sync(traj, env_info, task_info):
    """
    Programmatic and VLM verification of podcast sync task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_sync_val = metadata.get('sync_offset_samples', 198450)
    tolerance = metadata.get('tolerance_samples', 22050)  # 0.5 seconds
    
    score = 0.0
    feedback = []

    # ================================================================
    # 1. READ EXPORT JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/podcast_sync_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read export data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not export_data.get('session_modified_during_task', False):
        feedback.append("WARNING: Session file was not saved during task execution.")

    # ================================================================
    # 2. READ SESSION XML
    # ================================================================
    session_remote = "/home/ga/Audio/sessions/MyProject/MyProject.ardour"
    tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.ardour')
    tmp_xml.close()

    try:
        copy_from_env(session_remote, tmp_xml.name)
        tree = ET.parse(tmp_xml.name)
        root = tree.getroot()
    except Exception as e:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read/parse session XML: {e}"}
    finally:
        if os.path.exists(tmp_xml.name):
            os.unlink(tmp_xml.name)

    # ================================================================
    # 3. TRACK SETUP (15 points)
    # ================================================================
    routes = get_audio_routes(root)
    route_names = [r.get('name', '').lower() for r in routes]
    
    has_host = 'host' in route_names
    has_guest = 'guest' in route_names
    
    if has_host and has_guest:
        score += 15
        feedback.append("PASS: 'Host' and 'Guest' tracks created.")
    else:
        feedback.append("FAIL: Did not find both 'Host' and 'Guest' tracks.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # ================================================================
    # 4. REGION ANALYSIS & SYNCHRONIZATION (30 points)
    # ================================================================
    pl_host = find_playlist_for_route(root, 'host')
    pl_guest = find_playlist_for_route(root, 'guest')
    
    reg_host = get_main_region(pl_host)
    reg_guest = get_main_region(pl_guest)
    
    if not reg_host or not reg_guest:
        feedback.append("FAIL: Missing audio regions on Host or Guest tracks.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    # In Ardour XML:
    # 'start' = offset into the original audio file
    # 'position' = location on the session timeline
    host_start = int(reg_host.get('start', '0'))
    host_pos = int(reg_host.get('position', '0'))
    
    guest_start = int(reg_guest.get('start', '0'))
    guest_pos = int(reg_guest.get('position', '0'))
    
    # Mathematical proof of alignment:
    # Sync Value = (Guest.start - Guest.position) - (Host.start - Host.position)
    # For perfect alignment given the files, this should equal exactly 198,450 (4.5s)
    sync_value = (guest_start - guest_pos) - (host_start - host_pos)
    
    if abs(sync_value - expected_sync_val) <= tolerance:
        score += 30
        feedback.append(f"PASS: Tracks perfectly synchronized (offset: {sync_value} samples).")
        sync_passed = True
    else:
        feedback.append(f"FAIL: Tracks not synchronized. Expected sync offset ~{expected_sync_val}, got {sync_value}.")
        sync_passed = False

    # ================================================================
    # 5. PRE-ROLL TRIMMED (15 points)
    # Host pre-roll is 10s (441,000 samples). 
    # ================================================================
    # Allow 1s leeway in case they trimmed right up to the waveform start instead of exactly 10.0s
    if host_start >= (441000 - 44100):
        score += 15
        feedback.append("PASS: Pre-roll trimmed successfully.")
    else:
        feedback.append(f"FAIL: Pre-roll not fully trimmed. Host region starts at {host_start/44100:.2f}s into file.")

    # ================================================================
    # 6. TIMELINE RESET (10 points)
    # Both regions moved to position 0 (allow up to 1 second / 44100 samples)
    # ================================================================
    if host_pos <= 44100 and guest_pos <= 44100:
        score += 10
        feedback.append("PASS: Timeline reset (regions dragged to start).")
    else:
        feedback.append(f"FAIL: Regions not moved to start. Host at {host_pos/44100:.1f}s, Guest at {guest_pos/44100:.1f}s.")

    # ================================================================
    # 7. FADES APPLIED (10 points)
    # ================================================================
    if has_active_fade_in(reg_host) and has_active_fade_in(reg_guest):
        score += 10
        feedback.append("PASS: Fade-ins applied to both regions.")
    else:
        feedback.append("FAIL: Missing fade-ins on one or both regions.")

    # ================================================================
    # 8. VLM TRAJECTORY VERIFICATION (20 points)
    # Prove the agent actually interacted with the DAW interface.
    # ================================================================
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these chronological screenshots from a DAW (Ardour).
Did the user/agent actively manipulate audio tracks?
Look for:
1. Audio regions (blocks with waveforms) being moved or edited on the timeline.
2. Two separate tracks visible in the arrangement view.

Respond in JSON format:
{
    "manipulated_regions": true/false,
    "multiple_tracks_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
            try:
                result = query_vlm(prompt=prompt, images=frames)
                if result.get("success"):
                    parsed = result.get("parsed", {})
                    if parsed.get("manipulated_regions", False) and parsed.get("multiple_tracks_visible", False):
                        vlm_passed = True
                        score += 20
                        feedback.append("PASS: VLM verified UI interaction.")
                    else:
                        feedback.append(f"VLM: Missing UI interaction evidence. ({parsed.get('reasoning', '')})")
            except Exception as e:
                logger.error(f"VLM query failed: {e}")
                feedback.append("VLM Error: Ignored.")

    # Final scoring
    passed = (score >= 70) and sync_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "sync_value_samples": sync_value,
            "host_start": host_start,
            "guest_start": guest_start,
            "host_pos": host_pos,
            "guest_pos": guest_pos,
            "vlm_passed": vlm_passed
        }
    }