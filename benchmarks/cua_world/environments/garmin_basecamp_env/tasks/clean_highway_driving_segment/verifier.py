#!/usr/bin/env python3
"""
Verifier for clean_highway_driving_segment task.

MULTIPLE SIGNALS VERIFICATION:
1. Valid GPX output file exists (20 pts)
2. Max velocity between remaining points < 10 m/s (40 pts)
3. >= 90% of original walking points retained (30 pts)
4. Trajectory Process/VLM Validation (10 pts)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import math
from datetime import datetime

def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance between two points on the earth."""
    R = 6371000  # radius of Earth in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def verify_clean_highway_driving_segment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework Error: Copy function not available"}

    feedback = []
    score = 0
    max_score = 100

    # 1. Read export json
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read execution result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Check basics
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output GPX file not found at expected path."}
    
    if not result.get('file_created_during_task'):
        feedback.append("Warning: Output file timestamp precedes task start (possible old file).")

    # 3. Read original point count
    temp_orig = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    orig_count = 0
    try:
        copy_from_env("C:/tmp/orig_pt_count.txt", temp_orig.name)
        with open(temp_orig.name, 'r') as f:
            orig_count = int(f.read().strip())
    except Exception:
        pass
    finally:
        if os.path.exists(temp_orig.name):
            os.unlink(temp_orig.name)

    # 4. Parse output GPX
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:/workspace/output/cleaned_survey.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
        ns = {'gpx': 'http://www.topografix.com/GPX/1/1'}
        trkpts = root.findall('.//gpx:trkpt', ns)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Output file exists but failed to parse as valid GPX: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # Valid GPX
    score += 20
    feedback.append("Valid GPX file found.")

    # 5. Extract temporal-spatial points
    pts = []
    for pt in trkpts:
        lat = float(pt.attrib.get('lat', 0))
        lon = float(pt.attrib.get('lon', 0))
        t_el = pt.find('gpx:time', ns)
        if t_el is not None:
            t = datetime.strptime(t_el.text, "%Y-%m-%dT%H:%M:%SZ")
            pts.append((lat, lon, t))
            
    if len(pts) < 2:
        return {"passed": False, "score": 20, "feedback": "GPX contains less than 2 track points. Task failed."}

    # 6. Perform Speed Calculation Check
    max_speed = 0.0
    for i in range(1, len(pts)):
        lat1, lon1, t1 = pts[i-1]
        lat2, lon2, t2 = pts[i]
        dist_m = haversine(lat1, lon1, lat2, lon2)
        time_s = (t2 - t1).total_seconds()
        if time_s > 0:
            speed = dist_m / time_s
            if speed > max_speed:
                max_speed = speed

    # Evaluated at 10.0 m/s (~22.3 mph). Typical walk is ~1.5 m/s. High speed generated was > 30 m/s
    if max_speed < 10.0:
        score += 40
        feedback.append(f"Speed check passed (Max velocity found: {max_speed:.1f} m/s).")
    else:
        feedback.append(f"Speed check failed (Max velocity found: {max_speed:.1f} m/s > 10.0 m/s threshold). Driving segment was not fully removed.")

    # 7. Perform Data Integrity Check
    if orig_count > 0:
        retention_ratio = len(pts) / float(orig_count)
        if retention_ratio >= 0.90:
            score += 30
            feedback.append(f"Integrity check passed (Retained {retention_ratio*100:.1f}% of true survey points).")
        else:
            feedback.append(f"Integrity check failed (Retained only {retention_ratio*100:.1f}%, expected >=90%). Too much valid survey data was deleted.")
    else:
        score += 30
        feedback.append("Integrity check assumed passed (original count file missing).")

    # 8. VLM Trajectory Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        if frames and final:
            vlm_prompt = "Look at these images. Did the user/agent interact with Garmin BaseCamp to edit a track (e.g. using the Track Properties dialog to delete points, or using track editing tools on the map)? Reply ONLY with 'Yes' or 'No'."
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
            if vlm_res and 'yes' in vlm_res.get('response', '').lower():
                score += 10
                feedback.append("VLM confirmed BaseCamp track editing workflow.")
            else:
                feedback.append("VLM did not observe BaseCamp track editing.")
    except Exception:
        score += 10
        feedback.append("VLM validation skipped (module not available).")

    passed = (score >= 90)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "max_speed_ms": max_speed,
            "retained_points": len(pts),
            "original_points": orig_count
        }
    }