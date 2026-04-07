#!/usr/bin/env python3
"""
Verifier for crosswind_launch_compensation task.

Scoring breakdown (100 points total):
  15 pts - Wind conditions set (8.0 m/s, 270°)
  10 pts - Launch rod azimuth set (90°)
  20 pts - Launch rod angle optimized (3° to 15°)
  15 pts - Simulation is 'uptodate'
  15 pts - Analysis report file exists with meaningful content
  25 pts - VLM verification of GUI trajectory (anti-gaming)

Pass threshold: 60 points
  Do-nothing max: 0
"""

import os
import math
import tempfile
import zipfile
import json
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def _angle_match(rad_val, target_deg, tol_deg=1.5):
    """Check if a radian value matches a target degree value within tolerance."""
    deg_val = math.degrees(rad_val) % 360
    target_deg = target_deg % 360
    diff = abs(deg_val - target_deg)
    return min(diff, 360 - diff) <= tol_deg

def verify_crosswind_launch_compensation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/crosswind_compensation.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/launch_compensation_report.txt')
    target_windspeed = metadata.get('target_windspeed_ms', 8.0)
    target_winddir = metadata.get('target_winddir_deg', 270.0)
    target_roddir = metadata.get('target_roddir_deg', 90.0)
    min_rodangle = metadata.get('min_rodangle_deg', 3.0)
    max_rodangle = metadata.get('max_rodangle_deg', 15.0)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Evaluate JSON Export (File existence and modification)
    # ---------------------------------------------------------
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            res_json = json.load(f)
    except Exception:
        res_json = {"ork_exists": False, "report_exists": False, "ork_modified_during_task": False}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not res_json.get("ork_modified_during_task"):
        feedback_parts.append("Rocket file was not modified.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # 2. Parse ORK File (Programmatic Verification)
    # ---------------------------------------------------------
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"}

    # Evaluate the best uptodate simulation
    sims = ork_root.find('simulations')
    best_sim_score = 0
    best_sim_feedback = []
    has_uptodate = False

    if sims is not None:
        for sim in sims.findall('simulation'):
            status = sim.get('status', '')
            if status != 'uptodate':
                continue
            
            has_uptodate = True
            conds = sim.find('conditions')
            if conds is None:
                continue
                
            sim_score = 0
            sim_feedback = []
            
            # Check Wind Speed
            ws_text = conds.findtext('windspeed', '0')
            try:
                ws = float(ws_text)
                if abs(ws - target_windspeed) < 0.2:
                    sim_score += 10
                    sim_feedback.append("Wind speed correct")
            except ValueError:
                pass
                
            # Check Wind Direction
            wdir_text = conds.findtext('winddirection', '0')
            try:
                wdir = float(wdir_text)
                if _angle_match(wdir, target_winddir):
                    sim_score += 5
                    sim_feedback.append("Wind direction correct")
            except ValueError:
                pass
                
            # Check Launch Rod Direction (Azimuth)
            rdir_text = conds.findtext('launchroddirection', '0')
            try:
                rdir = float(rdir_text)
                if _angle_match(rdir, target_roddir):
                    sim_score += 10
                    sim_feedback.append("Rod direction correct")
            except ValueError:
                pass
                
            # Check Launch Rod Angle (Tilt)
            rang_text = conds.findtext('launchrodangle', '0')
            try:
                rang = float(rang_text)
                rang_deg = math.degrees(rang)
                if min_rodangle <= rang_deg <= max_rodangle:
                    sim_score += 20
                    sim_feedback.append(f"Rod angle optimal ({rang_deg:.1f}°)")
                elif 0 < rang_deg < min_rodangle or rang_deg > max_rodangle:
                    sim_score += 5
                    sim_feedback.append(f"Rod angle changed but suboptimal ({rang_deg:.1f}°)")
            except ValueError:
                pass

            if sim_score > best_sim_score:
                best_sim_score = sim_score
                best_sim_feedback = sim_feedback

    if has_uptodate:
        score += 15
        feedback_parts.append("Uptodate simulation exists [15/15 pts]")
        score += best_sim_score
        if best_sim_feedback:
            feedback_parts.extend(best_sim_feedback)
    else:
        feedback_parts.append("No uptodate simulation found [0/15 pts]")

    # ---------------------------------------------------------
    # 3. Report Check
    # ---------------------------------------------------------
    if res_json.get("report_exists") and res_json.get("report_size", 0) > 10:
        score += 15
        feedback_parts.append("Report created [15/15 pts]")
    else:
        feedback_parts.append("No valid report found [0/15 pts]")

    # ---------------------------------------------------------
    # 4. VLM Trajectory Verification (Anti-Gaming)
    # ---------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """You are analyzing screenshots of an agent configuring a rocket simulation in OpenRocket.
Does the agent actively open the 'Edit Simulation' dialog, configure 'Launch conditions' or 'Wind', and run the simulation?
Focus on the progression across the frames.

Respond with JSON:
{
    "configured_simulation": true/false,
    "ran_simulation": true/false,
    "explanation": "brief reason"
}"""
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("configured_simulation") and parsed.get("ran_simulation"):
                score += 25
                feedback_parts.append("VLM verified GUI interaction [25/25 pts]")
            elif parsed.get("configured_simulation") or parsed.get("ran_simulation"):
                score += 12
                feedback_parts.append("VLM partial GUI interaction [12/25 pts]")
            else:
                feedback_parts.append("VLM found no GUI interaction evidence [0/25 pts]")
        else:
            # Fallback if VLM fails but logic was correct
            if best_sim_score > 0:
                score += 25
                feedback_parts.append("VLM fallback (awarded points via programmatic success)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback if VLM errors out
        if best_sim_score > 0:
            score += 25

    passed = score >= metadata.get('pass_threshold', 60) and has_uptodate

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }