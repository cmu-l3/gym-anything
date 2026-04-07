#!/usr/bin/env python3
"""
Verifier for evaluate_network_capacity_mfd task.

Checks:
1. Agent generated 5 valid SUMO summary XML files (20 points).
2. Agent produced the CSV file with correct headers (10 points).
3. Verifier dynamically calculates the ground truth NMFD metrics directly from the 
   agent's generated XML files to ensure the agent's XML parsing is accurate.
4. Accuracy of agent's calculated metrics against the ground truth (70 points).
   - 14 points per scale factor (7 for max_running, 7 for avg_speed).
"""

import os
import csv
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def compute_truth_from_xml(xml_path):
    """
    Parses a SUMO summary XML to calculate true max_running and avg_speed.
    Returns (max_running, avg_speed).
    """
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        max_running = 0
        speeds = []
        
        for step in root.findall('step'):
            running = int(step.get('running', 0))
            if running > max_running:
                max_running = running
            if running > 0:
                speeds.append(float(step.get('meanSpeed', 0.0)))
                
        if len(speeds) > 0:
            avg_speed = sum(speeds) / len(speeds)
        else:
            avg_speed = 0.0
            
        return max_running, round(avg_speed, 2)
    except Exception as e:
        logger.error(f"Failed to parse XML {xml_path}: {e}")
        return None, None


def verify_evaluate_network_capacity_mfd(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    score = 0
    feedback_parts = []
    scales = ["0.5", "1.0", "1.5", "2.0", "3.0"]
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # Retrieve main task result metadata
        result_json_path = os.path.join(temp_dir, 'task_result.json')
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_metadata = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        # 1. Retrieve XML files and calculate Truth
        truth_data = {}
        valid_xml_count = 0
        
        for scale in scales:
            xml_filename = f"summary_{scale}.xml"
            xml_remote_path = f"/tmp/mfd_export/{xml_filename}"
            xml_local_path = os.path.join(temp_dir, xml_filename)
            
            try:
                copy_from_env(xml_remote_path, xml_local_path)
                true_max_run, true_avg_spd = compute_truth_from_xml(xml_local_path)
                
                if true_max_run is not None:
                    # Sanity check: ensure it's a real simulation, not a blank XML forgery
                    if true_max_run < 5 and scale != "0.0":
                        feedback_parts.append(f"Scale {scale} XML seems invalid/trivial (max_running={true_max_run}).")
                    else:
                        valid_xml_count += 1
                        truth_data[scale] = {"max_running": true_max_run, "avg_speed": true_avg_spd}
            except FileNotFoundError:
                pass  # File missing

        # Score XML files generated (4 points per valid file, max 20)
        score += valid_xml_count * 4
        feedback_parts.append(f"Generated {valid_xml_count}/5 valid summary XMLs.")
        
        if valid_xml_count == 0:
            feedback_parts.append("No valid XML files generated. Cannot verify data extraction.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # 2. Retrieve and Validate CSV
        csv_remote_path = "/tmp/mfd_export/mfd_data.csv"
        csv_local_path = os.path.join(temp_dir, "mfd_data.csv")
        agent_data = {}
        csv_valid = False
        
        try:
            copy_from_env(csv_remote_path, csv_local_path)
            with open(csv_local_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                headers = [h.strip() for h in reader.fieldnames] if reader.fieldnames else []
                
                if headers == ['scale', 'max_running', 'avg_speed']:
                    csv_valid = True
                    score += 10
                    feedback_parts.append("CSV formatting/headers correct.")
                    
                    for row in reader:
                        s = row.get('scale', '').strip()
                        if s in scales:
                            try:
                                agent_data[s] = {
                                    "max_running": int(row.get('max_running', 0)),
                                    "avg_speed": float(row.get('avg_speed', 0.0))
                                }
                            except ValueError:
                                pass # Malformed numbers
                else:
                    feedback_parts.append(f"CSV headers incorrect. Expected ['scale', 'max_running', 'avg_speed'], got {headers}")
        except FileNotFoundError:
            feedback_parts.append("mfd_data.csv not found.")
        except Exception as e:
            feedback_parts.append(f"Error reading CSV: {e}")

        # 3. Evaluate Data Accuracy against the dynamic Ground Truth
        if csv_valid:
            for scale in scales:
                if scale not in truth_data:
                    feedback_parts.append(f"Scale {scale}: Skipped (XML missing).")
                    continue
                    
                if scale not in agent_data:
                    feedback_parts.append(f"Scale {scale}: Missing in CSV.")
                    continue
                    
                truth = truth_data[scale]
                agent = agent_data[scale]
                
                # Check max_running (Tolerance +/- 2)
                if abs(truth["max_running"] - agent["max_running"]) <= 2:
                    score += 7
                    run_pass = True
                else:
                    run_pass = False
                    
                # Check avg_speed (Tolerance +/- 0.05)
                if abs(truth["avg_speed"] - agent["avg_speed"]) <= 0.05:
                    score += 7
                    spd_pass = True
                else:
                    spd_pass = False

                if run_pass and spd_pass:
                    feedback_parts.append(f"Scale {scale}: Perfect metrics.")
                else:
                    err_msg = f"Scale {scale} errors ->"
                    if not run_pass:
                        err_msg += f" max_running (Expected {truth['max_running']}, got {agent['max_running']})."
                    if not spd_pass:
                        err_msg += f" avg_speed (Expected {truth['avg_speed']}, got {agent['avg_speed']})."
                    feedback_parts.append(err_msg)

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }