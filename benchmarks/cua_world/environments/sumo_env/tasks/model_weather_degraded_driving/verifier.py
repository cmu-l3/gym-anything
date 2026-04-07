#!/usr/bin/env python3
"""
Verifier for model_weather_degraded_driving task.

Verifies:
1. vType XML modifications (tau, minGap, speedFactor).
2. Configuration XML pointing to the new vTypes.
3. Simulation XML outputs containing valid timeLoss.
4. Physical effect of rain causing higher timeLoss.
5. Analytical calculation correctness in the text report.
"""

import json
import os
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_xml_safe(filepath):
    try:
        tree = ET.parse(filepath)
        return tree.getroot()
    except Exception as e:
        logger.error(f"Failed to parse XML {filepath}: {e}")
        return None

def calculate_average_time_loss(root):
    if root is None:
        return None
    time_losses = []
    for trip in root.findall('tripinfo'):
        val = trip.get('timeLoss')
        if val is not None:
            try:
                time_losses.append(float(val))
            except ValueError:
                continue
    if not time_losses:
        return None
    return sum(time_losses) / len(time_losses)

def extract_report_values(filepath):
    """Extract baseline avg, rain avg, and percentage from report."""
    res = {"baseline": None, "rain": None, "percentage": None}
    if not os.path.exists(filepath):
        return res
    
    with open(filepath, 'r') as f:
        content = f.read()

    b_match = re.search(r"Baseline Average Time Loss:\s*([\d\.]+)", content, re.IGNORECASE)
    r_match = re.search(r"Rain Average Time Loss:\s*([\d\.]+)", content, re.IGNORECASE)
    p_match = re.search(r"Percentage Increase:\s*([\d\.]+)", content, re.IGNORECASE)

    if b_match: res["baseline"] = float(b_match.group(1))
    if r_match: res["rain"] = float(r_match.group(1))
    if p_match: res["percentage"] = float(p_match.group(1))

    return res

def verify_weather_degraded_driving(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Files exported to /tmp/ in container
    files_to_copy = {
        "result_meta": ("/tmp/task_result.json", ".json"),
        "vtypes": ("/tmp/vtypes_rain.xml", ".xml"),
        "config": ("/tmp/run_rain.sumocfg", ".sumocfg"),
        "trip_base": ("/tmp/tripinfo_baseline.xml", ".xml"),
        "trip_rain": ("/tmp/tripinfo_rain.xml", ".xml"),
        "report": ("/tmp/weather_impact.txt", ".txt")
    }
    
    local_files = {}
    for name, (remote_path, suffix) in files_to_copy.items():
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        try:
            copy_from_env(remote_path, tmp.name)
            if os.path.getsize(tmp.name) > 0:
                local_files[name] = tmp.name
            else:
                os.unlink(tmp.name)
        except Exception as e:
            logger.warning(f"Could not copy {remote_path}: {e}")
            os.unlink(tmp.name)

    # 1. Check basic meta
    if "result_meta" not in local_files:
        return {"passed": False, "score": 0, "feedback": "Result metadata not found"}
    
    with open(local_files["result_meta"], 'r') as f:
        meta = json.load(f)

    # Criterion 1: vType Modification (20 pts)
    vtype_ok = False
    if "vtypes" in local_files:
        root = parse_xml_safe(local_files["vtypes"])
        if root is not None:
            vtypes = root.findall('.//vType')
            if vtypes:
                all_modified = True
                for vt in vtypes:
                    if vt.get('tau') != "1.8" or vt.get('minGap') != "4.0" or vt.get('speedFactor') != "0.8":
                        all_modified = False
                        break
                if all_modified:
                    vtype_ok = True
                    score += 20
                    feedback_parts.append("vType params successfully updated")
                else:
                    feedback_parts.append("Not all vTypes had the required tau, minGap, and speedFactor")
            else:
                feedback_parts.append("No vType elements found in rain vtypes file")
        else:
            feedback_parts.append("vtypes_rain file is invalid XML")
    else:
        feedback_parts.append("vtypes_rain file missing")

    # Criterion 2: Config file (20 pts)
    config_ok = False
    if "config" in local_files:
        root = parse_xml_safe(local_files["config"])
        if root is not None:
            add_files = root.find('.//additional-files')
            if add_files is not None and add_files.get('value'):
                val = add_files.get('value')
                if 'pasubio_vtypes_rain.add.xml' in val:
                    config_ok = True
                    score += 20
                    feedback_parts.append("run_rain.sumocfg correctly references new vTypes")
                else:
                    feedback_parts.append("run_rain.sumocfg does not reference pasubio_vtypes_rain.add.xml")
            else:
                feedback_parts.append("No additional-files defined in run_rain.sumocfg")
    else:
        feedback_parts.append("run_rain.sumocfg missing")

    # Criterion 3 & 4: Simulation Execution & Physical Validation (40 pts)
    sims_ok = False
    physical_ok = False
    actual_base_avg = None
    actual_rain_avg = None

    if "trip_base" in local_files and "trip_rain" in local_files:
        root_base = parse_xml_safe(local_files["trip_base"])
        root_rain = parse_xml_safe(local_files["trip_rain"])
        
        actual_base_avg = calculate_average_time_loss(root_base)
        actual_rain_avg = calculate_average_time_loss(root_rain)

        if actual_base_avg is not None and actual_rain_avg is not None:
            sims_ok = True
            score += 20
            feedback_parts.append(f"Simulations ran (Base: {actual_base_avg:.2f}s, Rain: {actual_rain_avg:.2f}s)")
            
            if actual_rain_avg > actual_base_avg:
                physical_ok = True
                score += 20
                feedback_parts.append("Physical validation passed: rain caused higher delays")
            else:
                feedback_parts.append("Physical validation failed: rain did not increase delays")
        else:
            feedback_parts.append("tripinfo XMLs do not contain valid timeLoss data")
    else:
        feedback_parts.append("One or both tripinfo files missing")

    # Criterion 5: Analytical Accuracy (20 pts)
    report_ok = False
    if "report" in local_files and actual_base_avg and actual_rain_avg:
        report_vals = extract_report_values(local_files["report"])
        
        rep_base = report_vals["baseline"]
        rep_rain = report_vals["rain"]
        rep_pct = report_vals["percentage"]
        
        if rep_base is not None and rep_rain is not None and rep_pct is not None:
            # Calculate true percentage
            true_pct = ((actual_rain_avg - actual_base_avg) / actual_base_avg) * 100
            
            # Check tolerances (allow 1% relative error for rounding differences)
            def is_close(val1, val2, tol=0.01):
                if val1 == 0: return val2 == 0
                return abs((val1 - val2) / val1) <= tol

            if is_close(rep_base, actual_base_avg) and \
               is_close(rep_rain, actual_rain_avg) and \
               is_close(rep_pct, true_pct):
                report_ok = True
                score += 20
                feedback_parts.append("Analytical math in report is accurate")
            else:
                feedback_parts.append(f"Math error in report. Expected Pct: {true_pct:.2f}%, Got: {rep_pct}")
        else:
            feedback_parts.append("Could not parse required values from weather_impact.txt")
    else:
        if "report" not in local_files:
            feedback_parts.append("weather_impact.txt missing")

    # Clean up local temporary files
    for path in local_files.values():
        if os.path.exists(path):
            os.unlink(path)

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }