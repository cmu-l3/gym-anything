#!/usr/bin/env python3
"""
Verifier for Evaluate Navigation App Penetration task.
"""

import os
import json
import csv
import math
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_tripinfo(filepath):
    """Parse SUMO tripinfo XML to calculate average duration and device presence."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        durations = []
        routing_devices = 0
        total_vehicles = 0
        
        for child in root.findall('tripinfo'):
            total_vehicles += 1
            durations.append(float(child.get('duration', 0)))
            
            # Check for routing device attribute (modern SUMO behavior)
            devices = child.get('devices', '')
            if 'routing' in devices or 'rerouting' in devices:
                routing_devices += 1
                
        avg_duration = sum(durations) / len(durations) if durations else 0
        penetration_rate = (routing_devices / total_vehicles) if total_vehicles else 0
        
        return {
            "success": True,
            "total_vehicles": total_vehicles,
            "avg_duration": avg_duration,
            "penetration_rate": penetration_rate
        }
    except Exception as e:
        logger.error(f"Failed to parse XML {filepath}: {e}")
        return {"success": False, "total_vehicles": 0, "avg_duration": 0, "penetration_rate": 0}

def read_csv_report(filepath):
    """Parse the agent's CSV report."""
    results = {}
    try:
        with open(filepath, mode='r') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            if not headers or headers[0].strip().lower() != 'penetration' or headers[1].strip().lower() != 'avgduration':
                return {"success": False, "error": "Invalid headers"}
            
            for row in reader:
                if len(row) >= 2:
                    try:
                        pen = int(row[0].strip())
                        avg = float(row[1].strip())
                        results[pen] = avg
                    except ValueError:
                        continue
        return {"success": True, "data": results}
    except Exception as e:
        logger.error(f"Failed to read CSV {filepath}: {e}")
        return {"success": False, "error": str(e)}

def verify_evaluate_nav_app_penetration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read execution metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files_meta = result_meta.get('files', {})
    score = 0
    feedback_parts = []
    
    xml_0_meta = files_meta.get('tripinfo_0', {})
    xml_25_meta = files_meta.get('tripinfo_25', {})
    xml_75_meta = files_meta.get('tripinfo_75', {})
    csv_meta = files_meta.get('csv_report', {})

    if xml_0_meta.get('exists') and xml_25_meta.get('exists') and xml_75_meta.get('exists'):
        score += 30
        feedback_parts.append("All simulation XML files generated.")
    else:
        feedback_parts.append("Missing one or more required simulation XML files.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Extract and analyze the XMLs directly
    xml_data = {}
    for pen, path in [(0, metadata['expected_xml_0']), (25, metadata['expected_xml_25']), (75, metadata['expected_xml_75'])]:
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(path, temp_xml.name)
            xml_data[pen] = parse_tripinfo(temp_xml.name)
        except Exception:
            xml_data[pen] = {"success": False, "total_vehicles": 0, "avg_duration": 0, "penetration_rate": 0}
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)

    # Basic simulation validity checks (Anti-gaming)
    for pen in [0, 25, 75]:
        if xml_data[pen]['total_vehicles'] < 100:
            return {"passed": False, "score": score, "feedback": f"Tripinfo_{pen}.xml has too few vehicles. Simulation failed or forged."}
            
    # Penetration Configuration Scoring
    # Baseline
    if xml_data[0]['penetration_rate'] == 0:
        score += 10
        feedback_parts.append("Baseline config correct.")
    
    # 25% Config (allow wide margin for statistical variance or missing explicit 'devices' attribute tracking)
    # If the SUMO version tracks devices attribute:
    if xml_data[25]['penetration_rate'] > 0:
        if 0.15 <= xml_data[25]['penetration_rate'] <= 0.35:
            score += 15
            feedback_parts.append("25% penetration achieved accurately.")
        else:
            score += 5
            feedback_parts.append(f"25% penetration off (actual {xml_data[25]['penetration_rate']:.2f}).")
    else:
        # Fallback if device string isn't printed: check if durations changed from baseline
        if abs(xml_data[25]['avg_duration'] - xml_data[0]['avg_duration']) > 0.1:
            score += 15
            feedback_parts.append("25% config differs from baseline (assumed valid).")
            
    # 75% Config
    if xml_data[75]['penetration_rate'] > 0:
        if 0.60 <= xml_data[75]['penetration_rate'] <= 0.90:
            score += 15
            feedback_parts.append("75% penetration achieved accurately.")
        else:
            score += 5
            feedback_parts.append(f"75% penetration off (actual {xml_data[75]['penetration_rate']:.2f}).")
    else:
        # Fallback if device string isn't printed: check if durations changed from baseline and 25%
        if abs(xml_data[75]['avg_duration'] - xml_data[25]['avg_duration']) > 0.1:
            score += 15
            feedback_parts.append("75% config differs from 25% config (assumed valid).")

    # 3. Process CSV Report
    if not csv_meta.get('exists'):
        feedback_parts.append("CSV report missing.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_results = {}
    try:
        copy_from_env(metadata['expected_csv'], temp_csv.name)
        csv_results = read_csv_report(temp_csv.name)
    except Exception:
        csv_results = {"success": False, "error": "Failed to pull CSV."}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if not csv_results.get('success'):
        feedback_parts.append(f"CSV format error: {csv_results.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    score += 10
    feedback_parts.append("CSV format and headers correct.")

    # 4. Mathematical Data Extraction Accuracy Check
    agent_data = csv_results['data']
    accuracy_score = 0
    checks_passed = 0
    for pen in [0, 25, 75]:
        if pen in agent_data:
            expected_val = xml_data[pen]['avg_duration']
            agent_val = agent_data[pen]
            # allow 0.05 rounding tolerance
            if math.isclose(expected_val, agent_val, abs_tol=0.05):
                checks_passed += 1
                
    if checks_passed == 3:
        accuracy_score = 20
        feedback_parts.append("All computed averages perfectly match raw simulation data.")
    elif checks_passed > 0:
        accuracy_score = 5 * checks_passed
        feedback_parts.append(f"Some computed averages match ({checks_passed}/3).")
    else:
        feedback_parts.append("Computed averages do not match the raw XML data.")

    score += accuracy_score
    
    passed = score >= 70 and checks_passed >= 2
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}