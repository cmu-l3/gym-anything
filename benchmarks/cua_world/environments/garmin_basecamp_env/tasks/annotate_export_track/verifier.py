#!/usr/bin/env python3
"""
Verifier for annotate_export_track task.

VERIFICATION METRICS & ANTI-GAMING:
1. File Existence & Timestamps (15 points) - Ensures a GPX file was exported DURING the task, not prior.
2. GPX Structural Integrity (15 points) - Ensures it's a valid GPS exchange format file with track data.
3. Track Data Authenticity (20 points) - Prevents gaming by checking track point count and geographic bounds.
4. Description Metadata (15 points) - Validates the 'invasive species' string exists in the export.
5. Color Metadata (15 points) - Validates the Garmin extension `<gpxx:DisplayColor>Red</gpxx:DisplayColor>`.
6. Visual/VLM Verification (20 points) - Validates the agent manipulated the BaseCamp UI appropriately.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_annotate_export_track(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Retrieve & Validate Task Result Metadata
    # -------------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Annotated GPX file was not exported to C:\\workspace\\output\\annotated_track.gpx"
        }

    score += 5
    feedback_parts.append("Output file exists (+5)")

    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File exported during task (+10)")
    else:
        feedback_parts.append("WARNING: File timestamp is older than task start")

    # -------------------------------------------------------------------------
    # 2. Retrieve & Validate GPX Contents
    # -------------------------------------------------------------------------
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    gpx_content = ""
    try:
        copy_from_env("C:\\workspace\\output\\annotated_track.gpx", temp_gpx.name)
        with open(temp_gpx.name, 'r', encoding='utf-8', errors='ignore') as f:
            gpx_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve GPX file: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # Criterion A: Valid GPX structure
    if "<gpx" in gpx_content.lower() and "</gpx>" in gpx_content.lower() and "<trk>" in gpx_content.lower():
        score += 15
        feedback_parts.append("Valid GPX structure (+15)")
    else:
        feedback_parts.append("Invalid or empty GPX structure")

    # Criterion B: Data Authenticity (Track Points & Geographic Bounds)
    trkpt_matches = re.findall(r'<trkpt', gpx_content, re.IGNORECASE)
    trkpt_count = len(trkpt_matches)
    
    if trkpt_count >= 20:
        score += 10
        feedback_parts.append(f"Track points validated ({trkpt_count}) (+10)")
        
        # Approximate bounds check to ensure they exported the right track (Middlesex Fells)
        lats = [float(x) for x in re.findall(r'lat=["\']([^"\']+)["\']', gpx_content)[:20]]
        lons = [float(x) for x in re.findall(r'lon=["\']([^"\']+)["\']', gpx_content)[:20]]
        if lats and lons:
            avg_lat = sum(lats) / len(lats)
            avg_lon = sum(lons) / len(lons)
            # Fells loop is around 42.44, -71.10
            if 42.40 <= avg_lat <= 42.50 and -71.15 <= avg_lon <= -71.05:
                score += 10
                feedback_parts.append("Geographic bounds correct (+10)")
            else:
                feedback_parts.append(f"Wrong track area (lat={avg_lat:.2f}, lon={avg_lon:.2f})")
    else:
        feedback_parts.append(f"Insufficient track points ({trkpt_count}) - gaming suspected")

    # Criterion C: Description metadata presence
    if re.search(r'invasive species', gpx_content, re.IGNORECASE):
        score += 15
        feedback_parts.append("Description annotation verified (+15)")
    else:
        feedback_parts.append("Target description text not found in GPX")

    # Criterion D: Color metadata presence (Garmin GPX extensions)
    if re.search(r'<gpxx:DisplayColor>Red</gpxx:DisplayColor>', gpx_content, re.IGNORECASE):
        score += 15
        feedback_parts.append("Red color metadata verified (+15)")
    else:
        feedback_parts.append("Red color metadata not found in GPX extensions")

    # -------------------------------------------------------------------------
    # 3. Visual Verification using VLM
    # -------------------------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        prompt = """
        Examine these screenshots of the Garmin BaseCamp UI captured during an automation task.
        
        Verify the following:
        1. Did the user open the properties/edit dialog for a track? (Look for a window with 'Properties', 'Notes', or 'Color' tabs).
        2. Is the track line visibly colored RED on the map view?
        
        Respond in strict JSON format:
        {
            "properties_dialog_opened": true/false,
            "red_track_visible": true/false
        }
        """
        
        vlm_result = query_vlm(images=frames, prompt=prompt)
        if vlm_result and vlm_result.get('parsed'):
            parsed = vlm_result['parsed']
            if parsed.get('properties_dialog_opened'):
                score += 10
                feedback_parts.append("VLM: Properties dialog usage confirmed (+10)")
            if parsed.get('red_track_visible'):
                score += 10
                feedback_parts.append("VLM: Red track display confirmed (+10)")
    except Exception as e:
        logger.warning(f"VLM verification step skipped or failed: {e}")
        feedback_parts.append("VLM verification unavailable")

    # -------------------------------------------------------------------------
    # Pass/Fail Thresholds
    # -------------------------------------------------------------------------
    # Must achieve at least 60 points, but fundamentally requires the GPX to have real points
    passed = (score >= 60) and (trkpt_count >= 20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }