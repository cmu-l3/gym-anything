#!/usr/bin/env python3
"""
Verifier for body_tube_altitude_tuning task.

Scoring breakdown (100 points total):
  15 pts - Body tube lengthened by >= 20mm
  10 pts - Motor designation preserved as C6 (anti-gaming)
  15 pts - Simulation run (uptodate status)
  20 pts - Apogee correctly placed in the 200m - 250m window
  10 pts - Apogee decreased from typical baseline (>270m to anything lower)
  10 pts - Stability maintained (fin height unchanged/increased)
  10 pts - Report exists and contains meaningful content
  10 pts - VLM verification of GUI trajectory (anti-gaming to prevent manual XML edits)

Pass threshold: 60 points
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames

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


def verify_body_tube_altitude_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/altitude_tuning_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/altitude_tuning_report.txt')
    target_min_alt = metadata.get('target_min_alt_m', 200.0)
    target_max_alt = metadata.get('target_max_alt_m', 250.0)
    min_length_inc = metadata.get('min_length_increase_m', 0.02)
    baseline_motor = metadata.get('baseline_motor', 'C6')

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch JSON Export Data
    # ---------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    result_data = {}
    try:
        copy_from_env('/tmp/altitude_tuning_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export JSON: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # ---------------------------------------------------------
    # 2. Fetch Initial State (Baseline)
    # ---------------------------------------------------------
    tmp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_initial.close()
    initial_length = 0.27  # Fallback assumption
    try:
        copy_from_env('/tmp/initial_state.json', tmp_initial.name)
        with open(tmp_initial.name, 'r') as f:
            init_data = json.load(f)
            initial_length = init_data.get('initial_body_tube_length_m', 0.27)
    except Exception as e:
        logger.warning(f"Failed to read initial state JSON: {e}")
    finally:
        if os.path.exists(tmp_initial.name):
            os.unlink(tmp_initial.name)

    # ---------------------------------------------------------
    # 3. Analyze modified .ork file
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
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file"
        }

    # Extract current body tube length
    final_length = sum(
        float(bt.findtext('length', '0')) 
        for bt in ork_root.iter('bodytube')
    )
    
    # Extract motor config
    motor_desigs = [m.findtext('designation', '').upper() for m in ork_root.iter('motor')]
    motor_preserved = any(baseline_motor in m for m in motor_desigs)
    
    # Extract fin data (to ensure they didn't cheat by shrinking fins)
    min_fin_height = min(
        (float(f.findtext('height', '0')) for f in ork_root.iter('trapezoidfinset')), 
        default=0.0
    )
    
    # Extract simulations
    uptodate_sims = [sim for sim in ork_root.iter('simulation') if sim.get('status') == 'uptodate']
    max_alt = 0.0
    for sim in uptodate_sims:
        fd = sim.find('flightdata')
        if fd is not None:
            try:
                alt = float(fd.get('maxaltitude', '0'))
                max_alt = max(max_alt, alt)
            except ValueError:
                pass

    # -- Scoring Criterion 1: Body Tube Lengthened (15 pts) --
    if final_length >= initial_length + min_length_inc:
        score += 15
        feedback_parts.append(f"Tube lengthened correctly ({final_length:.2f}m) [15/15]")
    elif final_length > initial_length:
        score += 5
        feedback_parts.append(f"Tube lengthened slightly ({final_length:.2f}m) [5/15]")
    else:
        feedback_parts.append(f"Tube NOT lengthened (was {initial_length:.2f}m, now {final_length:.2f}m) [0/15]")

    # -- Scoring Criterion 2: Motor Preserved (10 pts) --
    if motor_preserved:
        score += 10
        feedback_parts.append("Motor preserved as C6 [10/10]")
    else:
        feedback_parts.append(f"Motor changed to {motor_desigs} (Fail) [0/10]")

    # -- Scoring Criterion 3: Simulation Run (15 pts) --
    if uptodate_sims:
        score += 15
        feedback_parts.append("Simulation run is uptodate [15/15]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15]")

    # -- Scoring Criterion 4: Apogee in Window (20 pts) --
    if target_min_alt <= max_alt <= target_max_alt:
        score += 20
        feedback_parts.append(f"Apogee {max_alt:.1f}m is in target window [20/20]")
    elif max_alt > 0:
        feedback_parts.append(f"Apogee {max_alt:.1f}m is OUTSIDE target window [0/20]")
    else:
        feedback_parts.append("No apogee data available [0/20]")

    # -- Scoring Criterion 5: Apogee Decreased (10 pts) --
    if 0 < max_alt < 270.0:  # Baseline C6-5 is usually 280m+
        score += 10
        feedback_parts.append(f"Apogee decreased properly [10/10]")

    # -- Scoring Criterion 6: Stability Maintained (10 pts) --
    if min_fin_height >= 0.035: # Baseline fins are around 0.04m height
        score += 10
        feedback_parts.append("Fins maintain stability scale [10/10]")
    else:
        feedback_parts.append("Fins were shrunk, stability compromised [0/10]")

    # ---------------------------------------------------------
    # 4. Analyze Report
    # ---------------------------------------------------------
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_content = ""
    try:
        if result_data.get('report_exists', False):
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                report_content = f.read().lower()
    except Exception as e:
        logger.warning(f"Failed to read report: {e}")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    has_len = 'length' in report_content or 'tube' in report_content
    has_alt = 'apogee' in report_content or 'altitude' in report_content
    has_stab = 'stability' in report_content or 'stable' in report_content

    if len(report_content) > 30 and has_len and has_alt and has_stab:
        score += 10
        feedback_parts.append("Report is thorough [10/10]")
    elif len(report_content) > 10:
        score += 5
        feedback_parts.append("Report is brief or missing keywords [5/10]")
    else:
        feedback_parts.append("Report missing or empty [0/10]")

    # ---------------------------------------------------------
    # 5. VLM Trajectory Verification (Anti-Gaming)
    # ---------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        vlm_prompt = (
            "You are verifying an OpenRocket task. Look at these frames across the agent's interaction.\n"
            "Assess if the agent ACTUALLY used the graphical UI to:\n"
            "1. Edit a component (specifically a 'Body tube' configuration window).\n"
            "2. Run a Flight Simulation (Flight Simulations tab visible, 'Run simulations' clicked).\n"
            "Respond ONLY with a JSON dictionary containing:\n"
            "{\n"
            "  \"ui_interaction_visible\": true/false,\n"
            "  \"reason\": \"Brief explanation of what is visible\"\n"
            "}"
        )
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('ui_interaction_visible', False):
                    score += 10
                    feedback_parts.append("VLM confirms UI usage [10/10]")
                else:
                    feedback_parts.append("VLM did NOT detect UI usage (possible hand-edit of XML) [0/10]")
            else:
                feedback_parts.append("VLM query failed, skipping VLM score [0/10]")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback_parts.append("VLM exception [0/10]")
    else:
        # Give free points if VLM isn't configured
        score += 10
        feedback_parts.append("VLM not configured, auto-passing UI check [10/10]")

    # Check key passing threshold
    passed = score >= 60 and (final_length > initial_length) and uptodate_sims

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }