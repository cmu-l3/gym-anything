#!/usr/bin/env python3
import os
import csv
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_sensor_gains(traj, env_info, task_info):
    """
    Verify that the sensor gains CSV file was properly generated and contains 
    accurate data queried from the SeisComP database.
    
    Checks:
    1. File was created during the task run (10 pts)
    2. Header matches expected columns perfectly or case-insensitive (10 pts)
    3. Row count matches the ground truth (20 pts)
    4. Gain values are float-accurate within 1% tolerance (30 pts)
    5. GainFrequency values are float-accurate within 1% tolerance (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read task result metadata JSON
    result_json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_tmp.name)
        with open(result_json_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_json_tmp.name):
            os.unlink(result_json_tmp.name)

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file /home/ga/bhz_gains.csv does not exist."
        }

    if created_during_task:
        score += 10
        feedback_parts.append("File created/modified during task (+10)")
    else:
        feedback_parts.append("Warning: File was completely unmodified during task duration")

    # 2. Pull Agent's CSV and Ground Truth CSV for comparison
    agent_csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    gt_csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')

    try:
        copy_from_env("/home/ga/bhz_gains.csv", agent_csv_tmp.name)
        copy_from_env("/tmp/ground_truth.csv", gt_csv_tmp.name)

        agent_rows = []
        with open(agent_csv_tmp.name, 'r') as f:
            reader = csv.reader(f)
            try:
                agent_header = next(reader)
                for row in reader:
                    agent_rows.append(row)
            except Exception:
                return {"passed": False, "score": score, "feedback": "Failed to parse agent CSV - format is invalid."}

        gt_rows = []
        with open(gt_csv_tmp.name, 'r') as f:
            reader = csv.reader(f)
            gt_header = next(reader)
            for row in reader:
                gt_rows.append(row)

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV files from container: {e}"}
    finally:
        if os.path.exists(agent_csv_tmp.name): os.unlink(agent_csv_tmp.name)
        if os.path.exists(gt_csv_tmp.name): os.unlink(gt_csv_tmp.name)

    # 3. Check Header Formatting (10 points)
    expected_header = ['Network', 'Station', 'Location', 'Channel', 'Gain', 'GainFrequency']
    if agent_header == expected_header:
        score += 10
        feedback_parts.append("Exact CSV header match (+10)")
    elif [h.strip().lower() for h in agent_header] == [h.lower() for h in expected_header]:
        score += 5
        feedback_parts.append("Header matched (ignoring case/whitespace) (+5)")
    else:
        feedback_parts.append(f"Header mismatch. Expected {expected_header}, got {agent_header}")

    # 4. Check Row Count matches ground truth (20 points)
    if len(gt_rows) == 0:
        feedback_parts.append("Ground truth is empty. Environment configuration issue.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    if len(agent_rows) == len(gt_rows):
        score += 20
        feedback_parts.append(f"Correct row count: {len(agent_rows)} (+20)")
    else:
        feedback_parts.append(f"Row count mismatch. Expected {len(gt_rows)}, got {len(agent_rows)}")
        # Partial credit if they fetched some rows but not all
        if 0 < len(agent_rows) <= len(gt_rows):
            score += int((len(agent_rows) / len(gt_rows)) * 15)
            feedback_parts.append("Partial row count credit awarded")

    # 5. Check Content/Values Accuracy (60 points)
    gt_dict = {}
    for r in gt_rows:
        # Strip string columns to prevent formatting errors from causing mismatches
        net, sta, loc, cha, gain, freq = [x.strip() for x in r]
        key = f"{net}.{sta}.{loc}.{cha}"
        gt_dict[key] = {
            'gain': float(gain) if gain else 0.0, 
            'freq': float(freq) if freq else 0.0
        }

    correct_gains = 0
    correct_freqs = 0
    matched_keys = 0

    for r in agent_rows:
        if len(r) < 6:
            continue
            
        net, sta, loc, cha, gain_str, freq_str = [x.strip() for x in r[:6]]
        key = f"{net}.{sta}.{loc}.{cha}"

        if key in gt_dict:
            matched_keys += 1
            try:
                agent_gain = float(gain_str)
                agent_freq = float(freq_str)

                gt_gain = gt_dict[key]['gain']
                gt_freq = gt_dict[key]['freq']

                # Floating point equality check with 1% relative tolerance 
                # (accounts for scientific notation mapping)
                if abs(agent_gain - gt_gain) <= max(0.01 * abs(gt_gain), 1e-6):
                    correct_gains += 1
                if abs(agent_freq - gt_freq) <= max(0.01 * abs(gt_freq), 1e-6):
                    correct_freqs += 1
            except ValueError:
                pass # Unparseable values are treated as incorrect

    # Calculate precise accuracy points
    if len(gt_dict) > 0:
        gain_accuracy = correct_gains / len(gt_dict)
        freq_accuracy = correct_freqs / len(gt_dict)

        points_gain = int(gain_accuracy * 30)
        points_freq = int(freq_accuracy * 30)

        score += points_gain + points_freq

        feedback_parts.append(f"Gain values accurate: {correct_gains}/{len(gt_dict)} (+{points_gain})")
        feedback_parts.append(f"GainFrequency values accurate: {correct_freqs}/{len(gt_dict)} (+{points_freq})")

    # 6. Final Evaluation
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "matched_keys": matched_keys,
            "correct_gains": correct_gains,
            "correct_freqs": correct_freqs,
            "expected_total": len(gt_dict)
        }
    }