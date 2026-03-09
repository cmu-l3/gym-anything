#!/usr/bin/env python3
"""
Verifier for audit_channel_stability task.

Checks:
1. Did the agent create the CSV file? (10 pts)
2. Is the CSV well-formed with correct headers? (10 pts)
3. Is the filtering correct (only > 4.0 ft/s)? (25 pts)
4. Are the velocity values accurate compared to ground truth? (25 pts)
5. Is the sort order correct? (10 pts)
6. Did the agent create the plot? (10 pts)
7. Was the simulation actually run? (10 pts)
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_channel_stability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    threshold = metadata.get('velocity_threshold', 4.0)
    
    score = 0
    feedback = []
    
    # 1. Retrieve Artifacts
    files = {
        "result": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "csv": "/tmp/agent_output.csv",
        # We don't strictly need to download the plot content for programmatic check, existence is enough
    }
    
    local_files = {}
    with tempfile.TemporaryDirectory() as tmpdir:
        for name, path in files.items():
            local_path = os.path.join(tmpdir, os.path.basename(path))
            try:
                copy_from_env(path, local_path)
                local_files[name] = local_path
            except Exception:
                local_files[name] = None

        # Load JSONs
        try:
            with open(local_files["result"]) as f:
                task_result = json.load(f)
            with open(local_files["ground_truth"]) as f:
                ground_truth = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSONs: {str(e)}"}

        # === EVALUATION ===

        # 1. Simulation Run (10 pts)
        if ground_truth.get("simulation_run", False):
            score += 10
            feedback.append("Simulation verified run.")
        else:
            feedback.append("Simulation results not found (HDF missing or unreadable).")

        # 2. Plot Created (10 pts)
        if task_result.get("plot_exists") and task_result.get("plot_created_during_task"):
            score += 10
            feedback.append("Profile plot created.")
        elif task_result.get("plot_exists"):
            score += 5
            feedback.append("Profile plot exists but timestamp suggests old file.")
        else:
            feedback.append("Profile plot not found.")

        # 3. CSV Existence (10 pts)
        if task_result.get("csv_exists") and task_result.get("csv_created_during_task"):
            score += 10
            feedback.append("CSV report created.")
        elif task_result.get("csv_exists"):
            score += 5
            feedback.append("CSV report exists but timestamp suggests old file.")
        else:
            return {"passed": False, "score": score, "feedback": "\n".join(feedback) + " | CSV report missing."}

        # 4. CSV Analysis (Headers, Filtering, Accuracy, Sorting)
        if local_files["csv"]:
            try:
                with open(local_files["csv"], 'r') as f:
                    # Sniff format
                    sample = f.read(1024)
                    f.seek(0)
                    dialect = csv.Sniffer().sniff(sample)
                    reader = csv.DictReader(f)
                    headers = reader.fieldnames
                    
                    rows = list(reader)

                # Headers (10 pts)
                required_headers = ['River_Station', 'Max_Channel_Vel_fps', 'Excess_fps']
                # Allow minor variations like case or underscores
                normalized_headers = [h.lower().replace(' ', '_') for h in headers] if headers else []
                normalized_required = [h.lower().replace(' ', '_') for h in required_headers]
                
                if all(req in normalized_headers for req in normalized_required):
                    score += 10
                    feedback.append("CSV headers correct.")
                else:
                    feedback.append(f"CSV headers incorrect. Found: {headers}")

                # Prepare Ground Truth Data for Comparison
                gt_cross_sections = ground_truth.get("cross_sections", [])
                
                # Filter GT for compliance check (> 4.0)
                gt_failing = [xs for xs in gt_cross_sections if xs['max_velocity'] > threshold]
                gt_failing_stations = set(str(xs['station']) for xs in gt_failing)
                
                # Agent Data
                agent_stations = []
                value_errors = []
                false_positives = []
                false_negatives = []
                
                # Map headers to standard keys
                h_map = {h.lower().replace(' ', '_'): h for h in headers}
                key_station = h_map.get('river_station', headers[0]) # fallback to first col
                key_max_vel = h_map.get('max_channel_vel_fps', headers[1] if len(headers)>1 else '')
                
                for row in rows:
                    st = str(row.get(key_station, '')).strip()
                    agent_stations.append(st)
                    
                    try:
                        val = float(row.get(key_max_vel, 0))
                    except ValueError:
                        val = 0.0
                    
                    # Find matching GT
                    gt_match = next((x for x in gt_cross_sections if str(x['station']) == st), None)
                    
                    if gt_match:
                        # Check accuracy
                        if abs(val - gt_match['max_velocity']) > 0.1: # 0.1 tolerance
                            value_errors.append(f"{st}: Agent {val} vs GT {gt_match['max_velocity']:.2f}")
                        
                        # Check filtering logic (False Positive)
                        if gt_match['max_velocity'] <= threshold:
                            false_positives.append(st)
                    else:
                        feedback.append(f"Unknown station in CSV: {st}")

                # Check False Negatives
                agent_stations_set = set(agent_stations)
                false_negatives = [st for st in gt_failing_stations if st not in agent_stations_set]

                # Filtering Logic Score (25 pts)
                # Deduct for missing stations or extra stations
                filter_score = 25
                if false_negatives:
                    feedback.append(f"Missed {len(false_negatives)} failing stations.")
                    filter_score -= (5 * len(false_negatives))
                if false_positives:
                    feedback.append(f"Included {len(false_positives)} passing stations (should be excluded).")
                    filter_score -= (5 * len(false_positives))
                
                score += max(0, filter_score)

                # Accuracy Score (25 pts)
                accuracy_score = 25
                if value_errors:
                    feedback.append(f"Value errors in {len(value_errors)} rows.")
                    accuracy_score -= (5 * len(value_errors))
                
                # If no rows but there should be, accuracy is 0
                if not rows and gt_failing:
                    accuracy_score = 0
                    
                score += max(0, accuracy_score)

                # Sorting Score (10 pts)
                # Check if stations are descending
                # Convert to float for numeric sort comparison
                try:
                    agent_stations_float = [float(s) for s in agent_stations]
                    is_sorted = all(agent_stations_float[i] >= agent_stations_float[i+1] for i in range(len(agent_stations_float)-1))
                    if is_sorted:
                        score += 10
                        feedback.append("Sorting correct.")
                    else:
                        feedback.append("CSV not sorted by River Station (descending).")
                except ValueError:
                    feedback.append("Could not verify sorting (non-numeric stations).")

            except Exception as e:
                feedback.append(f"Error parsing CSV: {str(e)}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }