#!/usr/bin/env python3
"""
Verifier for transfer_strategy_tradeoff@1

Validates that the agent correctly simulated and compared a Hohmann transfer
and a bi-elliptic transfer, correctly identifying Hohmann as the superior
strategy for this orbit ratio.

Scoring (total 100 pts, pass >= 60):
  - script_created (5): GMAT script(s) created during the task
  - hohmann_two_burns (10): Script contains 2+ ImpulsiveBurns
  - bielliptic_three_burns (10): Script contains 3+ ImpulsiveBurns (Combined checked via 5 total burns)
  - targeting_logic (10): DifferentialCorrector / Vary / Achieve present
  - report_written (5): Report text file exists and has content
  - hohmann_deltav_valid (15): Hohmann DeltaV in expected range
  - bielliptic_deltav_valid (15): Bi-elliptic DeltaV in expected range
  - hohmann_time_valid (5): Hohmann time in expected range
  - bielliptic_time_valid (5): Bi-elliptic time in expected range
  - correct_recommendation (10): Explicitly recommends Hohmann
  - deltav_ordering (10): Math consistently shows Bi-elliptic > Hohmann

Pass condition: score >= 60 AND correct_recommendation AND (hohmann_deltav_valid OR bielliptic_deltav_valid)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_value(pattern, text, default=None):
    match = re.search(pattern, text, re.IGNORECASE)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            return match.group(1).strip()
    return default

def verify_transfer_strategy_tradeoff(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    h_dv_min = metadata.get('hohmann_dv_min', 3.70)
    h_dv_max = metadata.get('hohmann_dv_max', 4.10)
    be_dv_min = metadata.get('bielliptic_dv_min', 4.00)
    be_dv_max = metadata.get('bielliptic_dv_max', 4.55)
    h_time_min = metadata.get('hohmann_time_min', 4.5)
    h_time_max = metadata.get('hohmann_time_max', 6.5)
    be_time_min = metadata.get('bielliptic_time_min', 30.0)
    be_time_max = metadata.get('bielliptic_time_max', 50.0)

    scores = {
        "script_created": 5,
        "hohmann_burns": 10,
        "bielliptic_burns": 10,
        "targeting_logic": 10,
        "report_written": 5,
        "hohmann_deltav": 15,
        "bielliptic_deltav": 15,
        "hohmann_time": 5,
        "bielliptic_time": 5,
        "recommendation": 10,
        "ordering": 10
    }

    total_score = 0
    feedback = []
    recommendation_correct = False
    hdv_valid = False
    bedv_valid = False

    # Create temp files to hold copied data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_scripts = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
            
        copy_from_env("/tmp/report.txt", temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
            
        copy_from_env("/tmp/all_scripts.txt", temp_scripts.name)
        with open(temp_scripts.name, 'r', encoding='utf-8', errors='ignore') as f:
            scripts_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task artifacts: {e}"}
    finally:
        for tmp_file in [temp_result.name, temp_report.name, temp_scripts.name]:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)

    # 1. Check Script Properties
    script_info = task_result.get('script_file', {})
    if script_info.get('exists') and script_info.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append(f"Script created ({script_info.get('count')} files).")
    else:
        feedback.append("No new scripts created during task.")

    # 2. Analyze Script Logic
    burn_count = len(re.findall(r'(?:Create\s+ImpulsiveBurn|Maneuver)', scripts_content, re.IGNORECASE))
    
    # We expect 2 burns for Hohmann, 3 for Bi-elliptic, maybe in same or separate files.
    if burn_count >= 5:
        total_score += scores["hohmann_burns"] + scores["bielliptic_burns"]
        feedback.append(f"Found sufficient ImpulsiveBurns ({burn_count}).")
    elif burn_count >= 3:
        total_score += scores["hohmann_burns"] + (scores["bielliptic_burns"] // 2)
        feedback.append(f"Found partial ImpulsiveBurns ({burn_count}).")
    elif burn_count >= 2:
        total_score += scores["hohmann_burns"]
        feedback.append("Found only enough burns for Hohmann.")
    else:
        feedback.append("Missing required ImpulsiveBurns in scripts.")

    if re.search(r'DifferentialCorrector', scripts_content, re.IGNORECASE) and re.search(r'Target', scripts_content, re.IGNORECASE):
        total_score += scores["targeting_logic"]
        feedback.append("Targeting logic (DifferentialCorrector) found.")
    else:
        feedback.append("Targeting logic missing from scripts.")

    # 3. Analyze Report
    report_info = task_result.get('report_file', {})
    if report_info.get('exists') and report_info.get('size', 0) > 10 and report_info.get('created_during_task'):
        total_score += scores["report_written"]
        feedback.append("Trade study report written.")
    else:
        feedback.append("Trade study report missing or empty.")

    # Extract values
    h_dv = extract_value(r'hohmann_total_deltav_km_s:\s*([0-9]+\.?[0-9]*|NaN)', report_content, -1.0)
    be_dv = extract_value(r'bielliptic_total_deltav_km_s:\s*([0-9]+\.?[0-9]*|NaN)', report_content, -1.0)
    h_time = extract_value(r'hohmann_transfer_time_hours:\s*([0-9]+\.?[0-9]*|NaN)', report_content, -1.0)
    be_time = extract_value(r'bielliptic_transfer_time_hours:\s*([0-9]+\.?[0-9]*|NaN)', report_content, -1.0)
    rec_strat = extract_value(r'recommended_strategy:\s*([A-Za-z\-]+)', report_content, "")

    if isinstance(h_dv, float) and h_dv_min <= h_dv <= h_dv_max:
        total_score += scores["hohmann_deltav"]
        hdv_valid = True
        feedback.append(f"Hohmann Delta-V valid ({h_dv} km/s).")
    elif h_dv != -1.0:
        feedback.append(f"Hohmann Delta-V invalid ({h_dv} km/s, expected {h_dv_min}-{h_dv_max}).")

    if isinstance(be_dv, float) and be_dv_min <= be_dv <= be_dv_max:
        total_score += scores["bielliptic_deltav"]
        bedv_valid = True
        feedback.append(f"Bi-elliptic Delta-V valid ({be_dv} km/s).")
    elif be_dv != -1.0:
        feedback.append(f"Bi-elliptic Delta-V invalid ({be_dv} km/s, expected {be_dv_min}-{be_dv_max}).")

    if isinstance(h_time, float) and h_time_min <= h_time <= h_time_max:
        total_score += scores["hohmann_time"]
        feedback.append(f"Hohmann time valid ({h_time} hrs).")
    elif h_time != -1.0:
        # Give partial if they supplied full period instead of transfer time (half period)
        if (h_time_min*2) <= h_time <= (h_time_max*2):
            total_score += scores["hohmann_time"] // 2
            feedback.append(f"Hohmann time partial credit (provided full orbit period).")

    if isinstance(be_time, float) and be_time_min <= be_time <= be_time_max:
        total_score += scores["bielliptic_time"]
        feedback.append(f"Bi-elliptic time valid ({be_time} hrs).")
    elif be_time != -1.0:
        if (be_time_min*2) <= be_time <= (be_time_max*2):
            total_score += scores["bielliptic_time"] // 2
            feedback.append(f"Bi-elliptic time partial credit (provided full orbit periods).")

    if "hohmann" in str(rec_strat).lower() and "bi" not in str(rec_strat).lower():
        total_score += scores["recommendation"]
        recommendation_correct = True
        feedback.append("Correctly recommended Hohmann transfer.")
    else:
        feedback.append(f"Incorrect recommendation: {rec_strat} (expected Hohmann).")

    if isinstance(h_dv, float) and isinstance(be_dv, float) and h_dv > 0 and be_dv > 0:
        if be_dv > h_dv:
            total_score += scores["ordering"]
            feedback.append("Delta-V ordering physically correct (Bi-elliptic > Hohmann).")
        else:
            feedback.append("Delta-V ordering physically incorrect.")

    # Determine Pass/Fail
    passed = (total_score >= 60) and recommendation_correct and (hdv_valid or bedv_valid)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }