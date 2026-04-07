#!/usr/bin/env python3
"""
Verifier for east_african_bimodal_rainfall task.

Occupation: Agricultural Climate Analyst (ICPAC)
Industry: Regional Climate Outlook / Food Security
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 75):
  1. Geo-mapped plot exported (25 pts): precip_map_april.png exists,
     was created after task start, size >= 15KB.
  2. Line plot exported (25 pts): annual_cycle_lineplot.png exists,
     created after task start, size >= 10KB. (Ensures agent created two distinct plots)
  3. Report structure complete (25 pts): rainfall_assessment.txt contains
     required fields (RAINFALL_PATTERN, LONG_RAINS_PEAK, SHORT_RAINS_PEAK, etc.).
  4. Scientific correctness (25 pts): Pattern is BIMODAL, peaks are correctly
     identified in MAM and OND respectively, and coordinates are near East Africa.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_float(s):
    """Extract first floating point number or integer from a string."""
    match = re.search(r'[-+]?\d*\.\d+|[-+]?\d+', s)
    if match:
        return float(match.group())
    return None

def verify_east_african_bimodal_rainfall(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/east_african_bimodal_rainfall_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # ----------------------------------------------------------------
    # Criterion 1: Geo-mapped April plot exported (25 pts)
    # ----------------------------------------------------------------
    map_exists = result.get('map_plot_exists', False)
    map_mtime = int(result.get('map_plot_mtime', 0))
    map_size = int(result.get('map_plot_size', 0))
    map_w = result.get('map_plot_width', 0)
    map_h = result.get('map_plot_height', 0)

    if map_exists and map_mtime >= task_start and map_size >= 15000:
        score += 25
        feedback.append(f"Geo-mapped plot exported ({map_size} bytes)")
    elif map_exists and map_mtime >= task_start and map_size >= 5000:
        score += 12
        feedback.append(f"Geo-mapped plot present but small ({map_size} bytes)")
    else:
        feedback.append(f"Geo-mapped plot missing/invalid (exists={map_exists}, size={map_size})")

    # ----------------------------------------------------------------
    # Criterion 2: Line plot exported (25 pts)
    # ----------------------------------------------------------------
    line_exists = result.get('line_plot_exists', False)
    line_mtime = int(result.get('line_plot_mtime', 0))
    line_size = int(result.get('line_plot_size', 0))
    line_w = result.get('line_plot_width', 0)
    line_h = result.get('line_plot_height', 0)

    # Anti-gaming: Ensure it's not literally the exact same file copied
    same_dimensions = (map_w == line_w and map_h == line_h and map_w > 0)
    same_size = (map_size == line_size and map_size > 0)

    if line_exists and line_mtime >= task_start and line_size >= 10000:
        if same_dimensions and same_size:
            score += 5
            feedback.append("Line plot appears to be an exact copy of the geo-mapped plot (gaming detected)")
        else:
            score += 25
            feedback.append(f"Line plot exported ({line_size} bytes, dimensions differ from map)")
    elif line_exists and line_mtime >= task_start and line_size >= 3000:
        score += 12
        feedback.append(f"Line plot present but small ({line_size} bytes)")
    else:
        feedback.append(f"Line plot missing/invalid (exists={line_exists}, size={line_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Report structure (25 pts)
    # ----------------------------------------------------------------
    pattern = result.get('rainfall_pattern', '').strip()
    long_peak = result.get('long_rains_peak', '').strip()
    short_peak = result.get('short_rains_peak', '').strip()
    lat_str = result.get('grid_point_lat', '').strip()
    lon_str = result.get('grid_point_lon', '').strip()

    has_all_fields = bool(pattern) and bool(long_peak) and bool(short_peak) and bool(lat_str) and bool(lon_str)

    if has_all_fields:
        score += 25
        feedback.append("Report structural fields complete")
    elif bool(pattern) or bool(long_peak) or bool(lat_str):
        score += 10
        feedback.append("Report is partially complete")
    else:
        feedback.append("Report missing or lacks required keys")

    # ----------------------------------------------------------------
    # Criterion 4: Scientific correctness (25 pts)
    # ----------------------------------------------------------------
    correct_science = 0
    
    # Check pattern
    if "bimodal" in pattern.lower():
        correct_science += 10
        feedback.append("Pattern identified correctly (BIMODAL)")
    else:
        feedback.append(f"Incorrect pattern: '{pattern}' (expected BIMODAL)")

    # Check peaks
    m_long = long_peak.lower()
    if any(x in m_long for x in ['mar', 'apr', 'may']):
        correct_science += 5
    m_short = short_peak.lower()
    if any(x in m_short for x in ['oct', 'nov', 'dec']):
        correct_science += 5

    if correct_science == 20:
        feedback.append("Peak months identified correctly (MAM and OND)")
    else:
        feedback.append(f"Peak months suboptimal/incorrect (Long: {long_peak}, Short: {short_peak})")

    # Check coordinates
    lat_val = extract_float(lat_str)
    lon_val = extract_float(lon_str)
    
    if lat_val is not None and lon_val is not None:
        if -5.0 <= lat_val <= 5.0 and 30.0 <= lon_val <= 45.0:
            correct_science += 5
            feedback.append(f"Coordinates ({lat_val}, {lon_val}) properly in East Africa")
        else:
            feedback.append(f"Coordinates ({lat_val}, {lon_val}) outside target East Africa box")
    else:
        feedback.append(f"Could not parse valid coordinates from '{lat_str}', '{lon_str}'")

    score += correct_science

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }