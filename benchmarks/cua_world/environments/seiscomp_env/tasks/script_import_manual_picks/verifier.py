#!/usr/bin/env python3
"""
Verifier for script_import_manual_picks task.
Verifies that the Python script was created and the specific picks were injected into the SeisComP DB.
"""

import os
import json
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_db_time(time_str):
    """Parse SeisComP DB timestamp into datetime object."""
    if not time_str:
        return None
    try:
        # DB format is typically "YYYY-MM-DD HH:MM:SS.xxxxxx"
        # Truncate fractional to max 6 chars if needed
        if '.' in time_str:
            base, frac = time_str.split('.')
            frac = frac[:6]
            time_str = f"{base}.{frac}"
            return datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S.%f")
        else:
            return datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S")
    except Exception as e:
        logger.warning(f"Failed to parse time {time_str}: {e}")
        return None

def verify_script_import_picks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_picks = metadata.get('expected_picks', [])
    tolerance = metadata.get('time_tolerance_sec', 0.1)
    
    # Defaults based on task description
    expected_network = metadata.get('expected_network', 'GE')
    expected_channel = metadata.get('expected_channel', 'BHZ')
    expected_phase = metadata.get('expected_phase', 'P')
    expected_mode = metadata.get('expected_mode', 'MANUAL')

    score = 0
    feedback_parts = []

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    picks = result.get('picks', [])
    script_created = result.get('script_created', False)
    scripts = result.get('scripts', [])

    # 1. Check Script Usage (10 points)
    if script_created:
        score += 10
        feedback_parts.append(f"Python script created ({len(scripts)} found)")
    else:
        feedback_parts.append("No new Python scripts found during task time")

    # 2. Check DB connection / Presence of picks (10 points)
    if len(picks) > 0:
        score += 10
        feedback_parts.append("Picks successfully saved to database")
    else:
        feedback_parts.append("No picks with agencyID 'ExternalSource' found in database")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Check Exact Object Count (20 points)
    if len(picks) == 3:
        score += 20
        feedback_parts.append("Correct total number of picks (3)")
    else:
        # Partial credit if they over-inserted or under-inserted
        if 1 <= len(picks) <= 5:
            score += 10
        feedback_parts.append(f"Expected 3 picks, found {len(picks)}")

    # 4 & 5. Verify Data and Metadata Accuracy (60 points total, scaled down per pick)
    # Group found picks by station for easy checking
    found_by_station = {}
    for p in picks:
        sta = p.get('waveformID_stationCode', '')
        if sta not in found_by_station:
            found_by_station[sta] = []
        found_by_station[sta].append(p)

    data_score = 0     # Max 40
    metadata_score = 0 # Max 20
    
    data_pts_per_pick = 40 / len(expected_picks)
    meta_pts_per_pick = 20 / len(expected_picks)

    for expected in expected_picks:
        sta = expected['station']
        expected_time_str = expected['time']
        expected_dt = parse_db_time(expected_time_str)

        matched_data = False
        matched_meta = False

        if sta in found_by_station:
            for p in found_by_station[sta]:
                actual_dt = parse_db_time(p.get('time_value'))
                
                # Check Time Accuracy
                if actual_dt and expected_dt:
                    diff = abs((actual_dt - expected_dt).total_seconds())
                    if diff <= tolerance:
                        matched_data = True
                
                # Check Metadata Accuracy
                if (p.get('waveformID_networkCode') == expected_network and
                    p.get('waveformID_channelCode') == expected_channel and
                    p.get('phaseHint') == expected_phase and
                    p.get('evaluationMode') == expected_mode):
                    matched_meta = True

                if matched_data and matched_meta:
                    break

        if matched_data:
            data_score += data_pts_per_pick
        else:
            feedback_parts.append(f"Incorrect/Missing timestamp for station {sta}")

        if matched_meta:
            metadata_score += meta_pts_per_pick
        else:
            feedback_parts.append(f"Incorrect/Missing metadata (net/chan/phase/mode) for station {sta}")

    score += int(data_score)
    score += int(metadata_score)

    if int(data_score) == 40 and int(metadata_score) == 20:
        feedback_parts.append("All pick timestamps and metadata are correct")

    # Evaluate Pass/Fail
    # To pass, they must have achieved at least 80% and successfully created the script.
    passed = score >= 80 and script_created

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }