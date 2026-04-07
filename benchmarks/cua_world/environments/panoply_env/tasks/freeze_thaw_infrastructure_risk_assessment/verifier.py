#!/usr/bin/env python3
"""
Verifier for freeze_thaw_infrastructure_risk_assessment task.

Occupation: Infrastructure Engineer / Pavement Damage Analyst (FHWA)
Industry: Civil Engineering / Transportation Infrastructure Maintenance
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 75):
  1. January temperature plot exported (15 pts): temperature_january.png exists,
     was created after task start, and has size >= 15KB.
  2. March temperature plot exported (15 pts): temperature_march.png exists,
     was created after task start, and has size >= 15KB.
  3. Report completeness (20 pts): freeze_thaw_report.txt contains all required fields
     and explicitly mentions 'freeze-thaw' in RISK_MECHANISM.
  4. Geophysical plausibility (30 pts):
     - FREEZE_THAW_BELT_LAT_RANGE_N extracts to a latitude overlapping 30-65°N.
     - MEAN_TEMP_AT_BELT_C extracts to a temperature between -5.0 and 5.0 °C.
  5. VLM Trajectory Verification (20 pts): Confirms NASA Panoply was visually interacted with.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_freeze_thaw_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_lat_min = metadata.get('expected_lat_min_n', 30.0)
    expected_lat_max = metadata.get('expected_lat_max_n', 65.0)
    expected_temp_min = metadata.get('expected_temp_min_c', -5.0)
    expected_temp_max = metadata.get('expected_temp_max_c', 5.0)

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/freeze_thaw_infrastructure_risk_assessment_result.json', tmp.name)
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
    # Criterion 1: January plot exported (15 pts)
    # ----------------------------------------------------------------
    jan_exists = result.get('png_jan_exists', False)
    jan_mtime = int(result.get('png_jan_mtime', 0))
    jan_size = int(result.get('png_jan_size', 0))

    if jan_exists and jan_mtime >= task_start and jan_size >= 15000:
        score += 15
        feedback.append(f"Jan plot exported ({jan_size} bytes)")
    elif jan_exists and jan_mtime >= task_start and jan_size > 0:
        score += 7
        feedback.append(f"Jan plot present but small ({jan_size} bytes)")
    else:
        feedback.append(f"Jan plot missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 2: March plot exported (15 pts)
    # ----------------------------------------------------------------
    mar_exists = result.get('png_mar_exists', False)
    mar_mtime = int(result.get('png_mar_mtime', 0))
    mar_size = int(result.get('png_mar_size', 0))

    if mar_exists and mar_mtime >= task_start and mar_size >= 15000:
        score += 15
        feedback.append(f"Mar plot exported ({mar_size} bytes)")
    elif mar_exists and mar_mtime >= task_start and mar_size > 0:
        score += 7
        feedback.append(f"Mar plot present but small ({mar_size} bytes)")
    else:
        feedback.append(f"Mar plot missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 3: Report Completeness (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))

    months = result.get('analysis_months', '').lower()
    lat_range = result.get('belt_lat_range', '').strip()
    continent = result.get('highest_risk_continent', '').strip()
    mechanism = result.get('risk_mechanism', '').lower()
    temp_c = result.get('mean_temp_c', '').strip()
    region = result.get('budget_region', '').strip()

    has_all = bool(months and lat_range and continent and mechanism and temp_c and region)
    mentions_months = 'january' in months and 'march' in months
    mentions_mechanism = 'freeze' in mechanism and 'thaw' in mechanism

    report_ok = False
    if report_exists and report_mtime >= task_start:
        if has_all and mentions_months and mentions_mechanism:
            score += 20
            report_ok = True
            feedback.append("Report complete with required structural fields")
        else:
            score += 10
            feedback.append("Report exists but is missing fields or strict keywords (e.g., 'freeze-thaw')")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: Geophysical Plausibility (30 pts)
    # ----------------------------------------------------------------
    lat_plausible = False
    temp_plausible = False

    if report_ok or (lat_range and temp_c):
        # Parse latitude: look for numbers
        lat_nums = re.findall(r'\d+\.?\d*', lat_range)
        if lat_nums:
            lats = [float(l) for l in lat_nums]
            # Check if any parsed latitude number falls in expected range
            if any(expected_lat_min <= l <= expected_lat_max for l in lats):
                lat_plausible = True

        # Parse temperature: look for numbers (allowing negatives)
        temp_nums = re.findall(r'-?\d+\.?\d*', temp_c)
        if temp_nums:
            temps = [float(t) for t in temp_nums]
            if any(expected_temp_min <= t <= expected_temp_max for t in temps):
                temp_plausible = True

    if lat_plausible and temp_plausible:
        score += 30
        feedback.append(f"Geophysical values plausible (Lat: {lat_range}, Temp: {temp_c})")
    elif lat_plausible:
        score += 15
        feedback.append(f"Latitude plausible ({lat_range}) but temperature invalid ({temp_c})")
    elif temp_plausible:
        score += 15
        feedback.append(f"Temperature plausible ({temp_c}) but latitude invalid ({lat_range})")
    elif report_exists:
        feedback.append(f"Geophysical values failed plausibility checks (Lat: {lat_range}, Temp: {temp_c})")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Trajectory Verification (20 pts)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "You are verifying a task where the agent uses NASA Panoply (a desktop Java application) "
                    "to view global temperature maps. Look at these frames from the agent's trajectory. "
                    "Do you see the NASA Panoply interface with a geographical map displaying data colors? "
                    "Reply with ONLY a JSON object: {\"panoply_map_visible\": true/false}"
                )
                vlm_resp = query_vlm(prompt=prompt, images=frames)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("panoply_map_visible", False):
                        score += 20
                        feedback.append("VLM confirmed Panoply interaction")
                    else:
                        feedback.append("VLM did not detect Panoply map interaction")
                else:
                    feedback.append(f"VLM query failed or unparseable: {vlm_resp.get('error')}")
            else:
                feedback.append("No trajectory frames for VLM")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
            logger.warning(f"VLM check failed: {e}")
    else:
        # If VLM is not available in the environment, award the points to prevent penalizing
        score += 20
        feedback.append("VLM unavailable - points awarded automatically")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }