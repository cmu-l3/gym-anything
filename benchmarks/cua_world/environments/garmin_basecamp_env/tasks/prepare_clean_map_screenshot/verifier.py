#!/usr/bin/env python3
"""
Verifier for prepare_clean_map_screenshot task.

HYBRID VERIFICATION: Combines programmatic checks with VLM-based visual verification.

Programmatic checks:
- GPX file exists and was created during the task timeframe
- GPX contains valid Track XML but exactly 0 Waypoints
- GPX Track contains Garmin extension setting the color to Red

VLM checks:
- Verifies the BaseCamp UI is the active visual
- Validates the track visually renders as Red
- Confirms the map interface is clear of waypoint markers
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_clean_map_screenshot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    
    # 1. Read task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. GPX verification (Programmatic XML checks)
    gpx_exists = result_data.get('gpx_exists', False)
    gpx_created = result_data.get('gpx_created_during_task', False)
    
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    gpx_valid = False
    gpx_wpts = -1
    gpx_trks = -1
    gpx_colors = []
    
    if gpx_exists:
        if gpx_created:
            score += 10
            feedback.append("GPX file exists and created during task")
        else:
            feedback.append("GPX file exists but was NOT created during task (possible gaming)")
            
        try:
            copy_from_env("C:\\workspace\\output\\presentation_map.gpx", temp_gpx.name)
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
            
            wpts = root.findall('.//{http://www.topografix.com/GPX/1/1}wpt')
            trks = root.findall('.//{http://www.topografix.com/GPX/1/1}trk')
            gpx_wpts = len(wpts)
            gpx_trks = len(trks)
            
            for trk in trks:
                # Garmin specifically uses GpxExtensions to set color styles
                for color in trk.findall('.//{http://www.garmin.com/xmlschemas/GpxExtensions/v3}DisplayColor'):
                    gpx_colors.append(color.text)
                    
            gpx_valid = True
        except Exception as e:
            feedback.append(f"Failed to parse GPX: {e}")
        finally:
            if os.path.exists(temp_gpx.name):
                os.unlink(temp_gpx.name)
            
        if gpx_valid:
            if gpx_trks > 0 and gpx_wpts == 0:
                score += 20
                feedback.append("GPX contains track(s) but 0 waypoints")
            else:
                feedback.append(f"GPX issue: {gpx_trks} tracks, {gpx_wpts} waypoints (expected 0 wpts)")
                
            if "Red" in gpx_colors:
                score += 20
                feedback.append("GPX track color is Red")
            else:
                feedback.append(f"GPX track color is not Red: {gpx_colors}")

    # 3. PNG Verification (VLM Visual Check)
    png_exists = result_data.get('png_exists', False)
    png_created = result_data.get('png_created_during_task', False)
    
    if png_exists:
        if png_created:
            score += 10
            feedback.append("Screenshot file exists and created during task")
        else:
            feedback.append("Screenshot file exists but was NOT created during task")
            
        # Copy PNG for VLM analysis
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("C:\\workspace\\output\\clean_map.png", temp_png.name)
            
            try:
                from gym_anything.vlm import query_vlm
                vlm_prompt = """You are evaluating a screenshot of Garmin BaseCamp.
Analyze the image and return a JSON object evaluating these criteria:
1. Is the Garmin BaseCamp application visible?
2. Is there a GPS track visible on the map, and is it distinctly colored RED?
3. Are there NO waypoints (flags, dots, or location markers) visible on the map? (The map should just be the trail and track without waypoint clutter).

Return ONLY valid JSON:
{
    "basecamp_visible": true/false,
    "track_is_red": true/false,
    "no_waypoints_visible": true/false
}"""
                vlm_resp = query_vlm(image=temp_png.name, prompt=vlm_prompt)
                
                if vlm_resp and vlm_resp.get("success") and "parsed" in vlm_resp:
                    parsed = vlm_resp["parsed"]
                    if parsed.get("basecamp_visible"):
                        score += 10
                        feedback.append("VLM: BaseCamp visible")
                    if parsed.get("track_is_red"):
                        score += 15
                        feedback.append("VLM: Track is Red")
                    if parsed.get("no_waypoints_visible"):
                        score += 15
                        feedback.append("VLM: Waypoints Hidden")
                else:
                    feedback.append("VLM query failed or returned invalid response")
            except Exception as e:
                feedback.append(f"VLM Exception: {e}")
        finally:
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)

    passed = score >= 75 and gpx_wpts == 0 and gpx_trks > 0 and gpx_created and png_created
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }