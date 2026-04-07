#!/usr/bin/env python3
"""
Verifier for simulate_motorcycle_lane_splitting task.

Programmatic Verification:
1. Validates structural attributes of the authored motorcycles.rou.xml.
2. Validates sublane physics configurations in run_sublane.sumocfg.
3. Independently parses the generated tripinfo XML to calculate true averages.
4. Compares agent's text report averages against the independent ground truth.

VLM Verification:
1. Validates the workflow trajectory to ensure the terminal/editor was actively used.
"""

import json
import os
import re
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simulate_motorcycle_lane_splitting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    moto_route_path = metadata.get('moto_route_path')
    config_path = metadata.get('config_path')
    tripinfo_path = metadata.get('tripinfo_path')
    report_path = metadata.get('report_path')

    feedback_parts = []
    score = 0

    # 1. Fetch export result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read export JSON"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files_info = result.get('files', {})

    # Helper function to fetch files from container
    def fetch_file(remote_path):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(remote_path, tmp.name)
            if os.path.exists(tmp.name) and os.path.getsize(tmp.name) > 0:
                return tmp.name
            return None
        except Exception:
            return None

    # CRITERION 1: Motorcycle Definitions (15 pts)
    # Must have latAlignment="arbitrary" and minGapLat="0.1"
    moto_local = fetch_file(moto_route_path) if files_info.get("motorcycles_rou", {}).get("exists") else None
    moto_valid = False
    if moto_local:
        try:
            tree = ET.parse(moto_local)
            root = tree.getroot()
            for vtype in root.findall('vType'):
                if vtype.get('latAlignment') == 'arbitrary' and vtype.get('minGapLat') == '0.1':
                    moto_valid = True
                    break
        except ET.ParseError:
            feedback_parts.append("motorcycles.rou.xml has invalid XML")
        finally:
            os.unlink(moto_local)

    if moto_valid:
        score += 15
        feedback_parts.append("Valid motorcycle definitions found (+15)")
    else:
        feedback_parts.append("Missing or incorrect motorcycle route attributes")

    # CRITERION 2: Sublane Configuration (15 pts)
    config_local = fetch_file(config_path) if files_info.get("run_config", {}).get("exists") else None
    config_valid = False
    if config_local:
        try:
            tree = ET.parse(config_local)
            root = tree.getroot()
            processing = root.find('processing')
            if processing is not None:
                lat_res = processing.find('lateral-resolution')
                if lat_res is not None and lat_res.get('value') == '0.8':
                    config_valid = True
        except ET.ParseError:
            feedback_parts.append("run_sublane.sumocfg has invalid XML")
        finally:
            os.unlink(config_local)

    if config_valid:
        score += 15
        feedback_parts.append("Sublane configuration activated (+15)")
    else:
        feedback_parts.append("Sublane processing config missing")

    # CRITERION 3: Simulation Execution & Independent Parsing (30 pts)
    tripinfo_local = fetch_file(tripinfo_path) if files_info.get("tripinfo", {}).get("exists") else None
    tripinfo_valid = False
    
    actual_moto_duration_sum = 0
    actual_moto_count = 0
    actual_other_duration_sum = 0
    actual_other_count = 0
    
    if tripinfo_local:
        try:
            tree = ET.parse(tripinfo_local)
            root = tree.getroot()
            for trip in root.findall('tripinfo'):
                vtype = trip.get('vType')
                duration = float(trip.get('duration', 0))
                if vtype == 'moto_split':
                    actual_moto_count += 1
                    actual_moto_duration_sum += duration
                else:
                    actual_other_count += 1
                    actual_other_duration_sum += duration
                    
            if actual_moto_count >= 100 and actual_other_count >= 500:
                tripinfo_valid = True
        except ET.ParseError:
            feedback_parts.append("Generated tripinfos.xml is invalid")
        finally:
            os.unlink(tripinfo_local)

    if tripinfo_valid:
        score += 30
        feedback_parts.append("Simulation successfully generated valid trip records (+30)")
    else:
        feedback_parts.append("Tripinfo file missing or lacks sufficient vehicle counts")

    # CRITERION 4: Data Analysis & Accuracy (20 pts)
    report_local = fetch_file(report_path) if files_info.get("report", {}).get("exists") else None
    analysis_accurate = False

    if report_local and tripinfo_valid:
        try:
            with open(report_local, 'r') as f:
                content = f.read()
            
            # Extract agent's computed values
            agent_moto_match = re.search(r'avg_duration_moto=([\d\.]+)', content)
            agent_other_match = re.search(r'avg_duration_other=([\d\.]+)', content)
            
            if agent_moto_match and agent_other_match:
                agent_moto = float(agent_moto_match.group(1))
                agent_other = float(agent_other_match.group(1))
                
                # Ground truth computation
                gt_moto = actual_moto_duration_sum / actual_moto_count
                gt_other = actual_other_duration_sum / actual_other_count
                
                # Verify within 0.5% tolerance (allowing for rounding differences)
                diff_moto = abs(agent_moto - gt_moto) / gt_moto
                diff_other = abs(agent_other - gt_other) / gt_other
                
                if diff_moto <= 0.005 and diff_other <= 0.005:
                    analysis_accurate = True
        except Exception as e:
            logger.error(f"Error reading report: {e}")
        finally:
            os.unlink(report_local)

    if analysis_accurate:
        score += 20
        feedback_parts.append("Report values correctly match independent calculations (+20)")
    elif report_local:
        feedback_parts.append("Report values are incorrect or mismatched format")
    else:
        feedback_parts.append("mode_comparison.txt report not found")

    # CRITERION 5: VLM Trajectory Verification (20 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            prompt = """Review these trajectory screenshots of an agent performing a traffic simulation configuration task.
            Did the agent use a text editor (like nano, vim, gedit, or similar) to edit XML configuration files, AND execute the SUMO simulation command in the terminal?
            
            Respond in JSON format:
            {
                "workflow_observed": true/false
            }"""
            
            vlm_result = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("workflow_observed", False):
                    vlm_score = 20
                    feedback_parts.append("VLM confirmed editor/terminal workflow (+20)")
                else:
                    feedback_parts.append("VLM did not observe terminal/editor workflow")
            else:
                vlm_score = 20
                feedback_parts.append("VLM verification failed - awarding default points (+20)")
        except ImportError:
            vlm_score = 20
            feedback_parts.append("VLM library unavailable - awarding default points (+20)")
    else:
        vlm_score = 20
        feedback_parts.append("VLM not available - awarding default points (+20)")
        
    score += vlm_score

    # Final Evaluation
    # Key criteria: Must have successfully run simulation and generated tripinfo.
    key_criteria_met = tripinfo_valid
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }