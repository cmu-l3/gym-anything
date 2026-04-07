#!/usr/bin/env python3
"""
Verifier for simulate_micromobility_escooters task.

Verifies:
1. eScooter Physics XML (15 pts) - Correct vClass and parameters
2. Demand Generation (20 pts) - Sufficient escooter routed trips
3. Mixed SUMOCFG (20 pts) - Links baseline and new scenario files
4. Simulation Outputs (20 pts) - Valid tripinfos.xml containing both vehicle types
5. Accurate Analysis (25 pts) - Agent correctly extracted and computed average durations
"""

import json
import os
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def fetch_file_content(env_info, remote_path):
    """Safely fetch file content from container environment."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return None
        
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.close()
    try:
        copy_from_env(remote_path, tmp.name)
        with open(tmp.name, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        logger.error(f"Failed to fetch {remote_path}: {e}")
        return None
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def fetch_xml(env_info, remote_path):
    """Fetch and parse XML file from container."""
    content = fetch_file_content(env_info, remote_path)
    if content:
        try:
            return ET.fromstring(content)
        except Exception as e:
            logger.warning(f"Failed to parse XML from {remote_path}: {e}")
            pass
    return None


def verify_simulate_micromobility_escooters(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    # Read export results
    result_content = fetch_file_content(env_info, "/tmp/task_result.json")
    if not result_content:
        return {"passed": False, "score": 0, "feedback": "Failed to read task result metadata."}
    
    try:
        result = json.loads(result_content)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Corrupted task result metadata."}

    files_status = result.get("files_status", {})
    output_dir = "/home/ga/SUMO_Output"

    # CRITERION 1: Valid E-Scooter vType (15 points)
    if files_status.get("escooter_add_xml") == "true":
        add_xml = fetch_xml(env_info, f"{output_dir}/escooter.add.xml")
        if add_xml is not None:
            vtype = add_xml.find(".//vType[@id='escooter']")
            if vtype is not None:
                if vtype.get('vClass') == 'bicycle':
                    score += 10
                    feedback_parts.append("Valid escooter vClass")
                try:
                    speed = float(vtype.get('maxSpeed', '0'))
                    if 5.0 <= speed <= 6.0:
                        score += 5
                        feedback_parts.append("Valid escooter physics")
                except ValueError:
                    pass
            else:
                feedback_parts.append("Missing 'escooter' vType definition")
        else:
            feedback_parts.append("escooter.add.xml is malformed")
    else:
        feedback_parts.append("escooter.add.xml missing or not created during task")

    # CRITERION 2: Valid Demand Generation (20 points)
    if files_status.get("escooter_rou_xml") == "true":
        rou_xml = fetch_xml(env_info, f"{output_dir}/escooter_demand.rou.xml")
        if rou_xml is not None:
            trips = rou_xml.findall(".//trip") + rou_xml.findall(".//vehicle")
            escooter_trips = [t for t in trips if t.get('type') == 'escooter']
            num_trips = len(escooter_trips)
            if num_trips >= 50:
                score += 20
                feedback_parts.append(f"Demand generated ({num_trips} trips)")
            elif num_trips > 0:
                score += 10
                feedback_parts.append(f"Partial demand generated ({num_trips} trips)")
            else:
                feedback_parts.append("No escooter trips found in routing file")
        else:
            feedback_parts.append("escooter_demand.rou.xml is malformed")

    # CRITERION 3: Composite Configuration (20 points)
    if files_status.get("mixed_mobility_sumocfg") == "true":
        cfg_text = fetch_file_content(env_info, f"{output_dir}/mixed_mobility.sumocfg")
        if cfg_text:
            has_baseline_net = "pasubio_buslanes.net.xml" in cfg_text
            has_baseline_rou = "pasubio.rou.xml" in cfg_text
            has_new_add = "escooter.add.xml" in cfg_text
            has_new_rou = "escooter_demand.rou.xml" in cfg_text
            
            if has_baseline_net and has_baseline_rou and has_new_add and has_new_rou:
                score += 20
                feedback_parts.append("Composite config accurately links baseline and new files")
            elif has_new_add and has_new_rou:
                score += 10
                feedback_parts.append("Composite config links new files but missed baseline links")
            else:
                feedback_parts.append("Composite config missing key file references")

    # CRITERION 4: Simulation Outputs Present (20 points)
    true_esc_avg, true_oth_avg = 0.0, 0.0
    if files_status.get("tripinfos_xml") == "true":
        tripinfo_xml = fetch_xml(env_info, f"{output_dir}/tripinfos.xml")
        if tripinfo_xml is not None:
            tripinfos = tripinfo_xml.findall(".//tripinfo")
            
            esc_durs = [float(t.get('duration', 0)) for t in tripinfos if t.get('vType') == 'escooter']
            oth_durs = [float(t.get('duration', 0)) for t in tripinfos if t.get('vType') != 'escooter']
            
            if esc_durs:
                true_esc_avg = sum(esc_durs) / len(esc_durs)
            if oth_durs:
                true_oth_avg = sum(oth_durs) / len(oth_durs)

            if len(esc_durs) > 0 and len(oth_durs) > 0:
                score += 20
                feedback_parts.append("Tripinfos generated for mixed traffic")
            elif len(esc_durs) > 0 or len(oth_durs) > 0:
                score += 10
                feedback_parts.append("Tripinfos generated but missing one traffic class")
            else:
                feedback_parts.append("Tripinfos generated but empty")

    # CRITERION 5: Accurate Analysis Report (25 points)
    if files_status.get("micromobility_report_txt") == "true":
        report_text = fetch_file_content(env_info, f"{output_dir}/micromobility_report.txt")
        if report_text and true_esc_avg > 0 and true_oth_avg > 0:
            # Extract all float values from report
            nums = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", report_text)]
            
            # Check if extracted numbers match true calculations (5% tolerance)
            esc_match = any(abs(n - true_esc_avg) / true_esc_avg < 0.05 for n in nums if n > 0)
            oth_match = any(abs(n - true_oth_avg) / true_oth_avg < 0.05 for n in nums if n > 0)
            
            if esc_match and oth_match:
                score += 25
                feedback_parts.append("Analysis report accurate")
            elif esc_match or oth_match:
                score += 12
                feedback_parts.append("Analysis report partially accurate")
            else:
                feedback_parts.append(f"Analysis numbers did not match ground truth ({true_esc_avg:.1f}, {true_oth_avg:.1f})")
        else:
            if not report_text:
                feedback_parts.append("Analysis report empty")
            else:
                feedback_parts.append("Simulation failed to produce data for analysis")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No valid steps completed."
    }