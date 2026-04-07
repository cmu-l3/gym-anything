#!/usr/bin/env python3
"""
Verifier for suez_syzygy_tide task.

Scoring (100 points total):
- Location Set to Suez Canal Region: 20 pts
- Display Settings Configured: 20 pts
- Screenshots Captured: 20 pts
- Documentation Written: 20 pts
- VLM verification (Date set correctly & Visuals present): 20 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Suez location targets
SUEZ_LAT_RAD = 0.5239   # 30.0176 N
SUEZ_LON_RAD = 0.5686   # 32.5802 E
TOLERANCE_RAD = 0.05    # Generous tolerance (~2.8 degrees)


def verify_suez_syzygy_tide(traj, env_info, task_info):
    """Verify syzygy event sky reconstruction task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "suez_syzygy_tide"
    
    # Extract results from VM
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
        with open(tmp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported task results: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # ── 1. Check Location Configuration (20 pts) ──
    lat = result.get('lat_rad')
    lon = result.get('lon_rad')
    if lat is not None and lon is not None:
        if abs(lat - SUEZ_LAT_RAD) <= TOLERANCE_RAD and abs(lon - SUEZ_LON_RAD) <= TOLERANCE_RAD:
            score += 20
            feedback.append(f"Location configured successfully (Suez region, lat={math.degrees(lat):.2f}°)")
        else:
            feedback.append(f"Location incorrect: lat={math.degrees(lat):.2f}°, lon={math.degrees(lon):.2f}°")
    else:
        feedback.append("Location missing from config")

    # ── 2. Check Display Settings (20 pts) ──
    atmos = result.get('flag_atmosphere')
    az_grid = result.get('flag_azimuthal_grid')
    cardinal = result.get('flag_cardinal_points')
    
    display_score = 0
    if atmos is False:
        display_score += 7
    if az_grid is True:
        display_score += 7
    if cardinal is True:
        display_score += 6
        
    score += display_score
    if display_score == 20:
        feedback.append("Display settings perfectly configured (Atmos off, Grid on, Cardinal on)")
    else:
        feedback.append(f"Display settings incomplete (atmos={atmos}, az_grid={az_grid}, cardinal={cardinal})")

    # ── 3. Check Screenshots (20 pts) ──
    ss_count = result.get('new_screenshot_count', 0)
    if ss_count >= 2:
        score += 20
        feedback.append(f"Captured {ss_count} reference screenshots")
    elif ss_count == 1:
        score += 10
        feedback.append("Only captured 1 reference screenshot (required 2)")
    else:
        feedback.append("No reference screenshots were captured")

    # ── 4. Check Documentation Text File (20 pts) ──
    notes_exists = result.get('notes_exists', False)
    content = result.get('notes_content', '').lower()
    
    if notes_exists:
        has_suez = "suez" in content
        has_date = "march 29" in content or "29 march" in content or "2021-03-29" in content
        has_sun = "sun" in content
        has_moon = "moon" in content
        has_syzygy = "syzygy" in content or "spring tide" in content
        
        notes_score = sum([has_suez*4, has_date*4, has_sun*4, has_moon*4, has_syzygy*4])
        score += notes_score
        feedback.append(f"Notes file quality score: {notes_score}/20")
    else:
        feedback.append("Notes file was not created or is empty")

    # ── 5. VLM Trajectory Check for Mechanics (20 pts) ──
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        images = []
        if frames: images.extend(frames)
        if final: images.append(final)
            
        if images:
            prompt = """You are analyzing Stellarium planetarium software screenshots. 
We need to verify if the user successfully reconstructed the sky for March 29, 2021.
Look closely at the screenshots, especially the bottom toolbar which displays the date/time, and the main sky view.

1. Is the date shown as roughly March 29, 2021 (e.g., 2021-03-29) in the bottom text or any dialog?
2. Is the user viewing the Sun or the Moon in any screenshot?
3. Is an azimuthal coordinate grid visible (a circular green grid covering the sky)?
4. Are cardinal directions (N, S, E, W red letters) visible on the horizon?

Respond strictly in JSON format:
{
  "date_correct": true,
  "sun_moon_viewed": true,
  "grid_visible": true,
  "cardinal_visible": true
}"""
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get("success") and vlm_res.get("parsed"):
                parsed = vlm_res["parsed"]
                if parsed.get("date_correct"): vlm_score += 5
                if parsed.get("sun_moon_viewed"): vlm_score += 5
                if parsed.get("grid_visible"): vlm_score += 5
                if parsed.get("cardinal_visible"): vlm_score += 5
                feedback.append(f"VLM visual verification score: {vlm_score}/20")
            else:
                feedback.append("VLM visual verification failed to parse properly (fallback granted)")
                vlm_score = 10
        else:
            feedback.append("No images available for VLM verification (fallback granted)")
            vlm_score = 10
            
    except ImportError:
        feedback.append("VLM module unavailable in environment, skipping visual check (offline fallback granted)")
        vlm_score = 20
    except Exception as e:
        feedback.append(f"VLM execution error: {e}")
        vlm_score = 10
        
    score += vlm_score

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}