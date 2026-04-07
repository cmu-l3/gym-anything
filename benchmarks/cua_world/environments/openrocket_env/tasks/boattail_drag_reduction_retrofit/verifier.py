#!/usr/bin/env python3
"""
Verifier for boattail_drag_reduction_retrofit task.

Scoring breakdown (100 points total):
  10 pts - Modified .ork file exists and was created during the task
  25 pts - A Transition component was added acting as a boattail (aft radius < fore radius)
  15 pts - Transition dimensions are physically reasonable (length 15-150mm)
  20 pts - At least one simulation is 'uptodate' in the modified file
  30 pts - VLM verification of trajectory (shows Transition in component tree & report activity)
           OR programmatic fallback: Report exists with numeric altitude values and required keywords.

Pass threshold: 60 points AND a boattail transition must exist.
"""

import os
import re
import json
import tempfile
import zipfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def _vlm_query(query_vlm, prompt, images):
    """Run VLM query with multiple trajectory images."""
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


VLM_TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent adding a boattail to a model rocket in OpenRocket and writing a report.

The images are sampled chronologically from the agent's interaction.

Assess the workflow progress:
1. TRANSITION_ADDED: In the OpenRocket component tree (top left panel), does a 'Transition' component appear at the bottom/aft of the rocket?
2. SIMULATION_RUN: Is there evidence of the agent running a simulation (e.g., flight data dialog, 'Simulations' tab active)?
3. REPORT_WRITING: Is there evidence of the agent writing a text report comparing altitudes?

Respond in JSON format:
{
    "transition_added": true/false,
    "simulation_run": true/false,
    "report_writing_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of agent actions observed"
}
"""


def verify_boattail_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_export_path = metadata.get('ork_export_path', '/home/ga/Documents/exports/boattail_retrofit.ork')
    report_export_path = metadata.get('report_export_path', '/home/ga/Documents/exports/boattail_report.txt')
    body_tube_radius = metadata.get('body_tube_radius_m', 0.0133)
    min_length = metadata.get('min_length_m', 0.015)
    max_length = metadata.get('max_length_m', 0.150)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON export metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env('/tmp/boattail_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    ork_exists = export_data.get('ork_exists', False)
    ork_created = export_data.get('ork_created_during_task', False)
    report_exists = export_data.get('report_exists', False)

    if not ork_exists:
        return {"passed": False, "score": 0, "feedback": "Required .ork file not exported"}
        
    if ork_created:
        score += 10
        feedback_parts.append(".ork saved [10/10]")
    else:
        feedback_parts.append(".ork exists but not modified during task [0/10]")

    # 2. Parse the modified .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_export_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Failed to retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Analyze Transitions
    boattail_found = False
    valid_dimensions = False
    
    for transition in ork_root.iter('transition'):
        # Parse radii
        fore_str = transition.findtext('foreradius', 'auto')
        aft_str = transition.findtext('aftradius', 'auto')
        len_str = transition.findtext('length', '0')
        
        try:
            length_val = float(len_str)
        except ValueError:
            length_val = 0.0
            
        fore_val = body_tube_radius if fore_str == 'auto' else float(fore_str)
        aft_val = body_tube_radius if aft_str == 'auto' else float(aft_str)
        
        # A valid boattail has an aft radius less than the fore radius
        if aft_val < fore_val and aft_val > 0:
            boattail_found = True
            if min_length <= length_val <= max_length:
                valid_dimensions = True
            break

    if boattail_found:
        score += 25
        feedback_parts.append("Boattail geometry found [25/25]")
        if valid_dimensions:
            score += 15
            feedback_parts.append("Boattail dimensions reasonable [15/15]")
        else:
            feedback_parts.append("Boattail dimensions out of bounds [0/15]")
    else:
        feedback_parts.append("No valid boattail transition found [0/40]")

    # 4. Check for up-to-date simulation
    uptodate_sim = False
    sims_elem = ork_root.find('simulations')
    if sims_elem is not None:
        for sim in sims_elem.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_sim = True
                break
                
    if uptodate_sim:
        score += 20
        feedback_parts.append("Up-to-date simulation found [20/20]")
    else:
        feedback_parts.append("No up-to-date simulation found [0/20]")

    # 5. Programmatic Report Check
    report_content = ""
    report_valid = False
    if report_exists:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_export_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read().lower()
            
            # Look for numbers representing altitudes (e.g. 100-1000)
            numbers = re.findall(r'\b\d{2,5}(?:\.\d+)?\b', report_content)
            has_keywords = any(kw in report_content for kw in ['baseline', 'before']) and \
                           any(kw in report_content for kw in ['boattail', 'transition']) and \
                           any(kw in report_content for kw in ['stable', 'stability'])
            
            if len(numbers) >= 2 and has_keywords:
                report_valid = True
        except Exception as e:
            logger.warning(f"Failed to read report: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)

    # 6. VLM Trajectory Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        vlm_result = _vlm_query(query_vlm, VLM_TRAJECTORY_PROMPT, frames)
        
        if vlm_result:
            if vlm_result.get("transition_added", False): vlm_score += 15
            if vlm_result.get("report_writing_visible", False): vlm_score += 15
            
            feedback_parts.append(f"VLM: Workflow detected ({vlm_score}/30)")
    
    # Fallback to programmatic report check if VLM is unavailable or scored low
    if vlm_score < 30 and report_valid:
        vlm_score = 30
        feedback_parts.append("Programmatic: Valid report found [30/30]")
    elif vlm_score == 0 and not report_valid:
        feedback_parts.append("No valid report or visual workflow detected [0/30]")

    score += vlm_score

    # Determine final pass/fail
    passed = score >= metadata.get('pass_threshold', 60) and boattail_found
    
    if not boattail_found:
        feedback_parts.append("FAIL: Core requirement (adding a boattail) not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }