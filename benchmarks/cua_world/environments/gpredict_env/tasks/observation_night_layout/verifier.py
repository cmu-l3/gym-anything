#!/usr/bin/env python3
"""
Verifier for observation_night_layout task.

Task: Configure GPredict modules and views for a satellite photography session.
  1. Create BrightSats module with ISS/CSS (25544, 48274, 49044) and 2 views (Map=0, Polar=2)
  2. Reconfigure Amateur module to 3 views (Map=0, List=1, Polar=2) while keeping its satellites
  3. Add CherrySprings ground station (41.6628 N, 77.8239 W, 700m)
  4. Enable UTC time display

Scoring (100 points, pass >= 70):
  - BrightSats module: 35 points total
      - 5 pts each for satellites (15 pts total)
      - 10 pts for NVIEWS=2
      - 10 pts for View types Map(0) and Polar(2)
  - Amateur module: 35 points total
      - 10 pts for NVIEWS=3
      - 15 pts for View types Map(0), List(1), Polar(2)
      - 10 pts for preserving satellites and modified during task (anti-gaming)
  - Cherry Springs ground station: 15 points
  - UTC time enabled: 10 points
  - Modules exist: 5 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_observation_night_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/observation_night_layout_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start_timestamp', 0)

    # --- Both modules exist (5 pts) ---
    bright_exists = result.get('brightsats_exists', False)
    amateur_exists = result.get('amateur_exists', False)
    if bright_exists and amateur_exists:
        score += 5
        feedback_parts.append("Both BrightSats and Amateur modules found")

    # --- BrightSats Module (35 pts) ---
    if bright_exists:
        bright_mtime = result.get('brightsats_mtime', 0)
        if bright_mtime >= task_start:
            # Satellites (15 pts)
            sats = result.get('brightsats_satellites', '')
            found_sats = 0
            for req_sat in [25544, 48274, 49044]:
                if str(req_sat) in sats:
                    score += 5
                    found_sats += 1
            feedback_parts.append(f"BrightSats sats found: {found_sats}/3")

            # Layout NVIEWS=2 (10 pts)
            nviews = str(result.get('brightsats_nviews', '')).strip()
            if nviews == '2':
                score += 10
                feedback_parts.append("BrightSats NVIEWS=2 correct")
            else:
                feedback_parts.append(f"BrightSats NVIEWS incorrect ({nviews})")

            # Views Map(0) and Polar(2) (10 pts)
            views_str = result.get('brightsats_views', '')
            view_types = [v.strip() for v in views_str.split(',') if v.strip()]
            if '0' in view_types and '2' in view_types:
                score += 10
                feedback_parts.append("BrightSats Map & Polar views correct")
            elif '0' in view_types or '2' in view_types:
                score += 5
                feedback_parts.append("BrightSats partial views correct")
            else:
                feedback_parts.append("BrightSats views missing Map or Polar")
        else:
            feedback_parts.append("BrightSats module created before task start (ignored)")
    else:
        feedback_parts.append("BrightSats module NOT FOUND")

    # --- Amateur Module (35 pts) ---
    if amateur_exists:
        amateur_mtime = result.get('amateur_mtime', 0)
        # Verify it was modified
        if amateur_mtime >= task_start:
            # Layout NVIEWS=3 (10 pts)
            nviews = str(result.get('amateur_nviews', '')).strip()
            if nviews == '3':
                score += 10
                feedback_parts.append("Amateur NVIEWS=3 correct")
            else:
                feedback_parts.append(f"Amateur NVIEWS incorrect ({nviews})")

            # Views Map(0), List(1), Polar(2) (15 pts)
            views_str = result.get('amateur_views', '')
            view_types = [v.strip() for v in views_str.split(',') if v.strip()]
            matched = sum(1 for v in ['0', '1', '2'] if v in view_types)
            if matched == 3:
                score += 15
                feedback_parts.append("Amateur Map, List, & Polar views correct")
            else:
                score += (matched * 5)
                feedback_parts.append(f"Amateur views found {matched}/3 expected types")

            # Preservation of satellites (10 pts)
            init_sats = result.get('initial_amateur_satellites', '').strip()
            curr_sats = result.get('amateur_satellites', '').strip()
            
            if curr_sats and curr_sats == init_sats:
                score += 10
                feedback_parts.append("Amateur satellites preserved correctly")
            elif curr_sats and len(curr_sats.split(';')) > 10:
                score += 5
                feedback_parts.append("Amateur satellites partially modified but still populated")
            else:
                feedback_parts.append("Amateur satellites were wiped or severely modified")
        else:
            feedback_parts.append("Amateur module not modified during task (0 points)")
    else:
        feedback_parts.append("Amateur module NOT FOUND")

    # --- Cherry Springs QTH (15 pts) ---
    if result.get('cherry_exists'):
        lat_ok = _close_enough(result.get('cherry_lat', ''), 41.6628, 0.05)
        lon_ok = _close_enough(result.get('cherry_lon', ''), -77.8239, 0.05)
        alt_ok = _close_enough(result.get('cherry_alt', ''), 700, 20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Cherry Springs QTH correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Cherry Springs QTH coords ok, alt wrong")
        else:
            score += 5
            feedback_parts.append("Cherry Springs QTH found, coordinates incorrect")
    else:
        feedback_parts.append("Cherry Springs QTH NOT FOUND")

    # --- UTC Time Enabled (10 pts) ---
    if result.get('utc_enabled', False):
        score += 10
        feedback_parts.append("UTC time enabled")
    else:
        feedback_parts.append("UTC time NOT enabled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }