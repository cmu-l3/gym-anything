#!/usr/bin/env python3
"""
Verifier for compute_corridor_emissions task.
Evaluates SUMO configuration modification, simulation execution, and accurate data extraction.
"""

import json
import os
import re
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_metric(text, metric_name):
    """Extract numeric value for a given metric label from the report text."""
    match = re.search(rf'{metric_name}:\s*([\d\.]+)', text, re.IGNORECASE)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            return None
    return None

def verify_compute_corridor_emissions(traj, env_info, task_info):
    """
    Verify that the emissions were computed and accurately reported.
    Uses copy_from_env to securely fetch target files.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch the export result JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    task_start = result.get('task_start', 0)
    stats_exists = result.get('stats_exists', False)
    report_exists = result.get('report_exists', False)

    # 2. Check Statistics XML
    stats_valid = False
    has_emissions_data = False
    
    if stats_exists:
        if result.get('stats_mtime', 0) > task_start:
            score += 10
            feedback_parts.append("statistics.xml created during task")
            
            # Fetch and parse XML
            temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
            try:
                copy_from_env("/home/ga/SUMO_Output/statistics.xml", temp_xml.name)
                tree = ET.parse(temp_xml.name)
                root = tree.getroot()
                if root.tag == 'statistics':
                    stats_valid = True
                    score += 10
                    feedback_parts.append("statistics.xml is valid SUMO output")
                    
                    # Check for emissions element (SUMO puts this in <emissions> or inside <vehicleTripStatistics>)
                    emissions_node = root.find('emissions')
                    if emissions_node is not None and 'CO2_abs' in emissions_node.attrib:
                        has_emissions_data = True
                    
                    # Alternative location in some SUMO versions
                    if not has_emissions_data:
                        vts = root.find('vehicleTripStatistics')
                        if vts is not None and 'emissions' in vts.attrib:
                            has_emissions_data = True
                            
                    if has_emissions_data:
                        score += 10
                        feedback_parts.append("emissions data found in statistics XML")
                    else:
                        feedback_parts.append("WARNING: No emissions data found in XML. Was device.emissions.probability set?")
            except Exception as e:
                feedback_parts.append(f"Invalid statistics XML: {e}")
            finally:
                if os.path.exists(temp_xml.name):
                    os.unlink(temp_xml.name)
        else:
            feedback_parts.append("statistics.xml exists but was NOT modified during the task (cheating detected)")
    else:
        feedback_parts.append("statistics.xml not found")

    # 3. Check Emissions Report TXT
    metrics = {}
    if report_exists:
        if result.get('report_mtime', 0) > task_start:
            score += 10
            feedback_parts.append("emissions_report.txt created during task")
            
            temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/home/ga/SUMO_Output/emissions_report.txt", temp_txt.name)
                with open(temp_txt.name, 'r') as f:
                    content = f.read()
                
                # Extract required metrics
                required_labels = ["CO2_mg", "CO_mg", "NOx_mg", "PMx_mg", "Fuel_mL", "Vehicle_Count"]
                for label in required_labels:
                    val = extract_metric(content, label)
                    if val is not None:
                        metrics[label] = val
                
                if len(metrics) == 6:
                    score += 15
                    feedback_parts.append("All 6 metrics found in report")
                else:
                    feedback_parts.append(f"Found {len(metrics)}/6 metrics in report")

                # Plausibility and Positivity Checks
                all_positive = all(v > 0 for v in metrics.values())
                if len(metrics) > 0 and all_positive:
                    score += 10
                    feedback_parts.append("Extracted metrics are positive numbers")
                
                # Check ranges
                if metrics.get("CO2_mg", 0) > 1_000_000:
                    score += 5
                if metrics.get("CO_mg", 0) > 100:
                    score += 5
                if metrics.get("NOx_mg", 0) > 100:
                    score += 5
                if metrics.get("PMx_mg", 0) > 1:
                    score += 5
                if metrics.get("Fuel_mL", 0) > 100:
                    score += 5
                if 10 < metrics.get("Vehicle_Count", 0) < 100_000:
                    score += 5
                    
                # Proportionality Check (Detect totally fabricated numbers)
                co2 = metrics.get("CO2_mg", 0)
                fuel = metrics.get("Fuel_mL", 0)
                if co2 > 0 and fuel > 0:
                    ratio = co2 / fuel
                    # ~2300 mg CO2 per mL fuel is physically realistic
                    if 1000 < ratio < 4000:
                        score += 5
                        feedback_parts.append("Physical relationship between Fuel and CO2 is plausible")
                    else:
                        feedback_parts.append(f"WARNING: CO2/Fuel ratio ({ratio:.1f}) implies physically impossible data fabrication")
                        score = max(0, score - 20)  # Penalize fabricated data

            except Exception as e:
                feedback_parts.append(f"Error reading report: {e}")
            finally:
                if os.path.exists(temp_txt.name):
                    os.unlink(temp_txt.name)
        else:
            feedback_parts.append("emissions_report.txt exists but was NOT modified during the task")
    else:
        feedback_parts.append("emissions_report.txt not found")

    # Determine Pass/Fail
    # To pass: Need at least 60 points, stats.xml must exist, and report must have >=4 metrics
    key_criteria_met = (stats_valid and has_emissions_data and len(metrics) >= 4)
    passed = (score >= 60) and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS: Valid SUMO execution and emissions data extracted.")
    else:
        feedback_parts.insert(0, "FAILED: Core requirements not met.")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }