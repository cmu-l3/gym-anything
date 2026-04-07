#!/usr/bin/env python3
"""
Verifier for calibrate_car_following_behavior task.

Evaluates:
1. Valid parameter modification in new vehicle types XML.
2. Proper SUMO config referencing.
3. Successful generation of baseline/cautious tripinfo XMLs.
4. Correct extraction and computation of summary metrics (JSON).
5. Generation of visualization.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from math import isclose

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_tripinfo_xml(file_path):
    """Parses tripinfo.xml and calculates average duration and timeLoss."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        durations = []
        time_losses = []
        
        for trip in root.findall('tripinfo'):
            durations.append(float(trip.get('duration', 0)))
            time_losses.append(float(trip.get('timeLoss', 0)))
            
        if not durations:
            return None
            
        return {
            "avg_duration": sum(durations) / len(durations),
            "avg_timeLoss": sum(time_losses) / len(time_losses),
            "count": len(durations)
        }
    except Exception as e:
        logger.error(f"Failed to parse tripinfo {file_path}: {e}")
        return None

def verify_calibrate_car_following_behavior(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # Required parameters
    metadata = task_info.get('metadata', {})
    exp_tau = metadata.get('expected_tau', '1.8')
    exp_mingap = metadata.get('expected_minGap', '3.5')
    exp_sigma = metadata.get('expected_sigma', '0.8')
    
    # 1. Fetch metadata result
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    files_info = result.get('files', {})

    # ================================================================
    # Criterion 1: VType Modification (20 pts)
    # ================================================================
    vtypes_ok = False
    if files_info.get('vtypes', {}).get('exists'):
        tmp_vtype = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/home/ga/SUMO_Output/cautious_vtypes.add.xml", tmp_vtype.name)
            tree = ET.parse(tmp_vtype.name)
            root = tree.getroot()
            
            # Check for modifying main passenger vehicle
            found_cautious_params = False
            for vtype in root.findall('vType'):
                tau = vtype.get('tau')
                minGap = vtype.get('minGap')
                sigma = vtype.get('sigma')
                
                if tau == exp_tau and minGap == exp_mingap and sigma == exp_sigma:
                    found_cautious_params = True
                    break
            
            if found_cautious_params:
                score += 20
                vtypes_ok = True
                feedback_parts.append("VTypes modified correctly")
            else:
                feedback_parts.append("VTypes XML exists but Krauss parameters not correctly set")
        except Exception as e:
            feedback_parts.append(f"VTypes parsing failed: {e}")
        finally:
            if os.path.exists(tmp_vtype.name):
                os.unlink(tmp_vtype.name)
    else:
        feedback_parts.append("cautious_vtypes.add.xml missing")

    # ================================================================
    # Criterion 2: Config Management (15 pts)
    # ================================================================
    config_ok = False
    if files_info.get('config', {}).get('exists'):
        tmp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/home/ga/SUMO_Output/cautious_run.sumocfg", tmp_config.name)
            tree = ET.parse(tmp_config.name)
            root = tree.getroot()
            
            inputs = root.find('input')
            if inputs is not None:
                add_files = inputs.find('additional-files')
                if add_files is not None and add_files.get('value'):
                    if 'cautious_vtypes.add.xml' in add_files.get('value'):
                        score += 15
                        config_ok = True
                        feedback_parts.append("SUMO config configured correctly")
                    else:
                        feedback_parts.append("SUMO config missing cautious_vtypes reference")
        except Exception as e:
            feedback_parts.append(f"Config parsing failed: {e}")
        finally:
            if os.path.exists(tmp_config.name):
                os.unlink(tmp_config.name)
    else:
        feedback_parts.append("cautious_run.sumocfg missing")

    # ================================================================
    # Criterion 3: Simulation Execution (20 pts)
    # ================================================================
    sims_ok = False
    actual_base = None
    actual_caut = None
    
    base_exists = files_info.get('base_trip', {}).get('exists')
    caut_exists = files_info.get('cautious_trip', {}).get('exists')
    
    if base_exists and caut_exists:
        tmp_base = tempfile.NamedTemporaryFile(delete=False)
        tmp_caut = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/home/ga/SUMO_Output/baseline_tripinfo.xml", tmp_base.name)
            copy_from_env("/home/ga/SUMO_Output/cautious_tripinfo.xml", tmp_caut.name)
            
            actual_base = parse_tripinfo_xml(tmp_base.name)
            actual_caut = parse_tripinfo_xml(tmp_caut.name)
            
            if actual_base and actual_caut and actual_base['count'] > 50 and actual_caut['count'] > 50:
                score += 20
                sims_ok = True
                feedback_parts.append("Simulations executed successfully")
            else:
                feedback_parts.append("Simulations ran but generated insufficient trip data")
        except Exception as e:
            feedback_parts.append("Error parsing tripinfo output")
        finally:
            if os.path.exists(tmp_base.name): os.unlink(tmp_base.name)
            if os.path.exists(tmp_caut.name): os.unlink(tmp_caut.name)
    else:
        feedback_parts.append("One or both tripinfo files missing")

    # ================================================================
    # Criterion 4 & 5: JSON Report & Analytical Accuracy (10 + 20 pts)
    # ================================================================
    analytics_ok = False
    if files_info.get('json', {}).get('exists'):
        tmp_json = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env("/home/ga/SUMO_Output/calibration_impact.json", tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                agent_report = json.load(f)
                
            req_keys = ['baseline_avg_duration', 'baseline_avg_timeLoss', 'cautious_avg_duration', 'cautious_avg_timeLoss']
            
            if all(k in agent_report for k in req_keys):
                score += 10
                feedback_parts.append("JSON report correctly structured")
                
                if sims_ok:
                    # Check accuracy (allow 0.1 tolerance)
                    acc_checks = [
                        isclose(agent_report['baseline_avg_duration'], actual_base['avg_duration'], abs_tol=0.1),
                        isclose(agent_report['baseline_avg_timeLoss'], actual_base['avg_timeLoss'], abs_tol=0.1),
                        isclose(agent_report['cautious_avg_duration'], actual_caut['avg_duration'], abs_tol=0.1),
                        isclose(agent_report['cautious_avg_timeLoss'], actual_caut['avg_timeLoss'], abs_tol=0.1)
                    ]
                    
                    if all(acc_checks):
                        score += 20
                        analytics_ok = True
                        feedback_parts.append("Analytics perfectly match simulation outputs")
                    else:
                        feedback_parts.append("Analytics calculation incorrect")
            else:
                feedback_parts.append("JSON missing required keys")
        except Exception as e:
            feedback_parts.append(f"JSON verification failed: {e}")
        finally:
            if os.path.exists(tmp_json.name): os.unlink(tmp_json.name)
    else:
        feedback_parts.append("calibration_impact.json missing")

    # ================================================================
    # Criterion 6: Visualization (15 pts)
    # ================================================================
    chart_info = files_info.get('chart', {})
    if chart_info.get('exists') and chart_info.get('size_bytes', 0) > 1000:
        score += 15
        feedback_parts.append("Visualization chart generated")
    else:
        feedback_parts.append("Chart missing or empty")

    # Ensure anti-gaming
    if chart_info.get('exists') and not chart_info.get('created_during_task'):
        score = 0
        feedback_parts.append("FAIL: Chart file existed before task began (anti-gaming)")

    # Overall pass check
    key_criteria_met = vtypes_ok and analytics_ok
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }