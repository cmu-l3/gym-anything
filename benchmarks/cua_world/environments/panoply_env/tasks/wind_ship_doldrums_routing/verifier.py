#!/usr/bin/env python3
"""
Verifier for wind_ship_doldrums_routing task.

Occupation: Meteorological Routing Analyst
Industry: Maritime Logistics / Wind-Assisted Shipping
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 75):
  1. Plot Exported (20 pts): atlantic_slp_september.png exists, >= 15KB.
  2. Report Complete (20 pts): doldrums_crossing_report.txt has all keys populated.
  3. Latitude Accuracy (20 pts): parsed DOLDRUMS_LATITUDE_N between 3.0 and 12.0.
  4. Pressure Plausibility (20 pts): parsed MIN_EQUATORIAL_SLP_HPA between 1008 and 1014.
  5. VLM Process Check (20 pts): Trajectory verification shows Panoply usage and map interaction.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wind_ship_doldrums_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/wind_ship_doldrums_routing_result.json', tmp.name)
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
    # Criterion 1: Plot Exported (20 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 15000:
        score += 20
        feedback.append(f"Plot exported successfully ({plot_size} bytes)")
    elif plot_exists and plot_size > 0:
        score += 10
        feedback.append(f"Plot exists but has suspicious size or timestamp ({plot_size} bytes, mtime={plot_mtime})")
    else:
        feedback.append(f"Plot missing or empty (exists={plot_exists}, size={plot_size})")

    # ----------------------------------------------------------------
    # Criterion 2: Report Complete (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    analysis_month = result.get('analysis_month', '').strip()
    ocean_basin = result.get('ocean_basin', '').strip()
    doldrums_lat = result.get('doldrums_lat', '').strip()
    min_slp = result.get('min_slp', '').strip()
    offset = result.get('equator_offset', '').strip()

    fields_populated = sum(1 for f in [analysis_month, ocean_basin, doldrums_lat, min_slp, offset] if f)

    if report_exists and report_mtime >= task_start and fields_populated == 5:
        score += 20
        feedback.append("Report is complete with all 5 required fields.")
    elif report_exists and fields_populated > 0:
        score += int(20 * (fields_populated / 5.0))
        feedback.append(f"Report is partially complete ({fields_populated}/5 fields).")
    else:
        feedback.append("Report missing or empty.")

    # ----------------------------------------------------------------
    # Criterion 3: Latitude Accuracy (20 pts)
    # The true climatological ITCZ in the Atlantic in September is roughly 5-10°N.
    # Accept 3.0 to 12.0 for flexibility.
    # ----------------------------------------------------------------
    lat_val = None
    if doldrums_lat:
        try:
            # Clean string (e.g. '7', '7.5', '8N', '8 degrees')
            clean_lat = doldrums_lat.lower().replace('n', '').replace('degrees', '').replace('°', '').strip()
            lat_val = float(clean_lat)
            if 3.0 <= lat_val <= 12.0:
                score += 20
                feedback.append(f"Latitude ({lat_val}°N) is scientifically accurate for September Atlantic doldrums.")
            else:
                feedback.append(f"Latitude ({lat_val}°N) is outside the plausible ITCZ range (3°N to 12°N).")
        except ValueError:
            feedback.append(f"Could not parse latitude value: '{doldrums_lat}'")
    else:
        feedback.append("No latitude value provided to verify.")

    # ----------------------------------------------------------------
    # Criterion 4: Pressure Plausibility (20 pts)
    # The true minimum pressure in this trough is ~1011-1012 hPa.
    # Accept 1008 to 1014.
    # ----------------------------------------------------------------
    if min_slp:
        try:
            # Clean string
            clean_slp = min_slp.lower().replace('hpa', '').replace('mb', '').replace('millibars', '').strip()
            slp_val = float(clean_slp)
            if 1008.0 <= slp_val <= 1014.0:
                score += 20
                feedback.append(f"Pressure ({slp_val} hPa) is scientifically plausible for the equatorial trough.")
            else:
                feedback.append(f"Pressure ({slp_val} hPa) is outside plausible range (1008 to 1014 hPa).")
        except ValueError:
            feedback.append(f"Could not parse pressure value: '{min_slp}'")
    else:
        feedback.append("No pressure value provided to verify.")

    # Validate Offset logic (must be North)
    if 'north' in offset.lower() and lat_val and lat_val > 0:
        # Extra confirmation
        pass
    elif offset and 'north' not in offset.lower():
        feedback.append("Warning: Meteorological equator offset should be 'North' in September.")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Process Check (20 pts)
    # ----------------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images and query_vlm:
            prompt = """You are verifying if an agent successfully completed a climate data analysis task in NASA Panoply.
TASK: Visualize Sea Level Pressure ('slp'), navigate to 'Sep' (September), and view the equatorial Atlantic Ocean map.

Look at these trajectory frames and determine:
1. Did the agent use NASA Panoply to create a plot?
2. Is the plotted variable Sea Level Pressure (slp)?
3. Did the agent zoom or pan the map to view the Atlantic Ocean near the equator?

Respond in JSON format:
{
    "panoply_plot_created": true/false,
    "slp_plotted": true/false,
    "atlantic_viewed": true/false,
    "confidence": "low/medium/high"
}"""
            vlm_result = query_vlm(images=images, prompt=prompt)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('panoply_plot_created') and parsed.get('slp_plotted'):
                score += 10
                feedback.append("VLM confirmed Panoply and SLP usage.")
                if parsed.get('atlantic_viewed'):
                    score += 10
                    feedback.append("VLM confirmed Atlantic Ocean viewed.")
            else:
                feedback.append("VLM did not clearly detect correct Panoply SLP workflow.")
        else:
            feedback.append("VLM skipped: Missing images or query function.")
    except Exception as e:
        feedback.append(f"VLM verification failed/skipped: {e}")

    # ----------------------------------------------------------------
    # Final Result Compilation
    # ----------------------------------------------------------------
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }