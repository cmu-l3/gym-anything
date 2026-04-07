#!/usr/bin/env python3
"""
Verifier for commercial_crew_splashdown_climatology task.
"""

import json
import os
import tempfile
import re

def verify_commercial_crew_splashdown_climatology(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/commercial_crew_splashdown_climatology_result.json', tmp.name)
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

    # 1. SST Plot Exported (20 pts)
    sst_exists = result.get('sst_plot_exists', False)
    sst_mtime = int(result.get('sst_plot_mtime', 0))
    sst_size = int(result.get('sst_plot_size', 0))

    if sst_exists and sst_mtime >= task_start and sst_size >= 15000:
        score += 20
        feedback.append(f"SST plot exported ({sst_size} bytes)")
    elif sst_exists and sst_mtime >= task_start and sst_size >= 5000:
        score += 10
        feedback.append(f"SST plot present but small ({sst_size} bytes)")
    else:
        feedback.append("SST plot missing or not created during task")

    # 2. Precipitation Plot Exported (20 pts)
    precip_exists = result.get('precip_plot_exists', False)
    precip_mtime = int(result.get('precip_plot_mtime', 0))
    precip_size = int(result.get('precip_plot_size', 0))

    if precip_exists and precip_mtime >= task_start and precip_size >= 15000:
        score += 20
        feedback.append(f"Precipitation plot exported ({precip_size} bytes)")
    elif precip_exists and precip_mtime >= task_start and precip_size >= 5000:
        score += 10
        feedback.append(f"Precipitation plot present but small ({precip_size} bytes)")
    else:
        feedback.append("Precipitation plot missing or not created during task")

    # 3. Correct Site Recommendation (20 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    recommended_site = result.get('recommended_site', '').strip().lower()

    if report_exists and report_mtime >= task_start:
        if 'bravo' in recommended_site or 'baja' in recommended_site:
            score += 20
            feedback.append(f"Correct site recommended: {recommended_site}")
        else:
            feedback.append(f"Incorrect or missing recommendation: '{recommended_site}'")
    else:
        feedback.append("Report missing or not created during task")

    # 4. Quantitative Accuracy - SST Data Extraction (40 pts)
    alpha_sst_raw = result.get('alpha_sst', '')
    bravo_sst_raw = result.get('bravo_sst', '')
    
    alpha_score = 0
    bravo_score = 0

    if report_exists and report_mtime >= task_start:
        # Extract numerics from the report's strings
        alpha_match = re.search(r'[-+]?\d*\.\d+|\d+', alpha_sst_raw)
        bravo_match = re.search(r'[-+]?\d*\.\d+|\d+', bravo_sst_raw)

        if alpha_match:
            try:
                alpha_val = float(alpha_match.group())
                if 28.0 <= alpha_val <= 31.0:
                    alpha_score = 20
                    feedback.append(f"Site Alpha SST ({alpha_val}°C) within correct range (28.0-31.0°C)")
                else:
                    feedback.append(f"Site Alpha SST ({alpha_val}°C) out of expected bounds")
            except ValueError:
                feedback.append(f"Could not parse Site Alpha SST: {alpha_sst_raw}")
        else:
            feedback.append("Site Alpha SST missing")

        if bravo_match:
            try:
                bravo_val = float(bravo_match.group())
                if 19.0 <= bravo_val <= 24.0:
                    bravo_score = 20
                    feedback.append(f"Site Bravo SST ({bravo_val}°C) within correct range (19.0-24.0°C)")
                else:
                    feedback.append(f"Site Bravo SST ({bravo_val}°C) out of expected bounds")
            except ValueError:
                feedback.append(f"Could not parse Site Bravo SST: {bravo_sst_raw}")
        else:
            feedback.append("Site Bravo SST missing")

    score += alpha_score + bravo_score

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }