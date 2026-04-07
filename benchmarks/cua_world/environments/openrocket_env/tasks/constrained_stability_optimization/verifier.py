#!/usr/bin/env python3
"""
Verifier for constrained_stability_optimization task.

Scoring breakdown (100 points total):
  15 pts - Payload Preserved: "GPS Tracker" mass component exists with ~0.150kg
  15 pts - Height Constrained: Fin height remains at 0.045m
  15 pts - Root Constrained: Fin root chord remains at 0.080m
  25 pts - Sweep Increased: Fin sweep length >= 0.055m (35mm increase)
  15 pts - Simulation Run: At least one simulation has 'uptodate' status
  15 pts - Engineering Memo: Memo exists and contains relevant analysis keywords

Pass threshold: 70 points
  Requires the agent to successfully navigate the engineering constraint trade-off.
"""

import os
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


def verify_constrained_stability_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    saved_ork_path = metadata.get('saved_ork_path', '/home/ga/Documents/rockets/stable_swept_rocket.ork')
    memo_path = metadata.get('memo_path', '/home/ga/Documents/exports/sweep_optimization_memo.txt')
    
    # Baselines and thresholds
    baseline_root = metadata.get('baseline_root_chord_m', 0.080)
    baseline_height = metadata.get('baseline_height_m', 0.045)
    target_sweep = metadata.get('target_sweep_m', 0.055)
    expected_gps_mass = metadata.get('gps_mass_kg', 0.150)
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON check
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception:
        export_result = {}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not export_result.get("ork_exists"):
        return {"passed": False, "score": 0, "feedback": "Saved rocket file 'stable_swept_rocket.ork' not found."}

    # 2. Retrieve the .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(saved_ork_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to read rocket XML."}

    # --- Criteria 1: Payload Preserved (15 pts) ---
    gps_tracker_found = False
    gps_mass = 0.0
    for mc in ork_root.iter('masscomponent'):
        name = mc.findtext('name', '').lower()
        if 'gps tracker' in name:
            gps_tracker_found = True
            try:
                gps_mass = float(mc.findtext('mass', '0'))
            except (ValueError, TypeError):
                gps_mass = 0.0

    if gps_tracker_found and gps_mass >= (expected_gps_mass - 0.005):
        score += 15
        feedback_parts.append("Payload preserved [15/15 pts]")
    else:
        feedback_parts.append("Payload reduced or missing (Constraint Violated) [0/15 pts]")

    # --- Extract Fin Metrics ---
    fin_height = 0.0
    fin_root = 0.0
    fin_sweep = 0.0
    fin_count = 0
    
    for fin in ork_root.iter('trapezoidfinset'):
        fin_count += 1
        try:
            fin_height = float(fin.findtext('height', '0'))
            fin_root = float(fin.findtext('rootchord', '0'))
            fin_sweep = float(fin.findtext('sweeplength', '0'))
        except (ValueError, TypeError):
            pass

    if fin_count == 0:
        feedback_parts.append("No trapezoidal fins found in rocket! [0 pts]")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criteria 2: Height Constrained (15 pts) ---
    # Tolerance of 2mm
    if abs(fin_height - baseline_height) <= 0.002:
        score += 15
        feedback_parts.append("Height constrained [15/15 pts]")
    else:
        feedback_parts.append(f"Height changed to {fin_height*1000:.1f}mm (Constraint Violated) [0/15 pts]")

    # --- Criteria 3: Root Constrained (15 pts) ---
    if abs(fin_root - baseline_root) <= 0.002:
        score += 15
        feedback_parts.append("Root constrained [15/15 pts]")
    else:
        feedback_parts.append(f"Root changed to {fin_root*1000:.1f}mm (Constraint Violated) [0/15 pts]")

    # --- Criteria 4: Sweep Increased (25 pts) ---
    if fin_sweep >= target_sweep:
        score += 25
        feedback_parts.append(f"Sweep increased to >= target ({fin_sweep*1000:.1f}mm) [25/25 pts]")
    elif fin_sweep > 0.025:
        score += 10
        feedback_parts.append(f"Sweep slightly increased but below target [10/25 pts]")
    else:
        feedback_parts.append("Sweep not significantly increased [0/25 pts]")

    # --- Criteria 5: Simulation Run (15 pts) ---
    sims = ork_root.find('simulations')
    uptodate = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate = True
                break

    if uptodate:
        score += 15
        feedback_parts.append("Simulation is uptodate [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulation found [0/15 pts]")

    # --- Criteria 6: Engineering Memo (15 pts) ---
    tmp_memo = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_memo.close()
    memo_content = ""
    try:
        copy_from_env(memo_path, tmp_memo.name)
        if os.path.exists(tmp_memo.name):
            with open(tmp_memo.name, 'r') as f:
                memo_content = f.read().lower()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_memo.name):
            os.unlink(tmp_memo.name)

    if len(memo_content) > 20 and ('sweep' in memo_content or 'stability' in memo_content or 'caliber' in memo_content):
        score += 15
        feedback_parts.append("Engineering memo found and valid [15/15 pts]")
    elif len(memo_content) > 0:
        score += 5
        feedback_parts.append("Engineering memo found but lacks keywords [5/15 pts]")
    else:
        feedback_parts.append("Engineering memo missing [0/15 pts]")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }