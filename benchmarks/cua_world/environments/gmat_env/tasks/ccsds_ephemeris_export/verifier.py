#!/usr/bin/env python3
"""
Verifier for ccsds_ephemeris_export@1

Scoring (total 100 pts, pass >= 70):
  - oem_exists (10): OEM file generated
  - spk_exists_and_valid (15): SPK file generated with valid signature
  - oem_metadata (15): OEM has correct OBJECT_NAME and INTERPOLATION_DEGREE
  - oem_timespan (10): OEM covers 14 days
  - oem_step_size (15): Time delta between OEM data rows is 60s
  - low_fidelity_accuracy (10): Script has correct initial state and physical params
  - high_fidelity_accuracy (25): Script has complete force model (JGM-2 10x10, Sun, Luna, JacchiaRoberts, SRP)

Pass condition: score >= 70 AND oem_exists AND spk_exists
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ccsds_ephemeris_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    scores = {
        "oem_exists": 10,
        "spk_exists_and_valid": 15,
        "oem_metadata": 15,
        "oem_timespan": 10,
        "oem_step_size": 15,
        "low_fidelity_accuracy": 10,
        "high_fidelity_accuracy": 25,
    }

    total_score = 0
    feedback = []

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    oem_exists = task_result.get('oem_file', {}).get('exists', False)
    spk_exists = task_result.get('spk_file', {}).get('exists', False)

    # 1. OEM Exists
    if oem_exists:
        total_score += scores["oem_exists"]
        feedback.append("OEM file generated successfully.")
    else:
        feedback.append("OEM file not found.")

    # 2. SPK Exists and Valid
    if spk_exists:
        magic = task_result.get('spk_magic', '')
        if 'DAF/SPK' in magic:
            total_score += scores["spk_exists_and_valid"]
            feedback.append("SPK binary file generated with valid signature.")
        else:
            feedback.append(f"SPK file generated but invalid signature ({magic}).")
    else:
        feedback.append("SPK file not found.")

    # 3-5. Parse OEM
    if oem_exists:
        oem_path = task_result.get('oem_path')
        temp_oem = tempfile.NamedTemporaryFile(delete=False, suffix='.oem')
        try:
            copy_from_env(oem_path, temp_oem.name)
            with open(temp_oem.name, 'r', encoding='utf-8', errors='ignore') as f:
                oem_content = f.read()

            # Metadata
            obj_name = re.search(r'OBJECT_NAME\s*=\s*(.+)', oem_content)
            interp = re.search(r'INTERPOLATION_DEGREE\s*=\s*(\d+)', oem_content)
            
            meta_ok = 0
            if obj_name and 'MagSat2' in obj_name.group(1):
                meta_ok += 1
            if interp and interp.group(1) == '7':
                meta_ok += 1
            
            if meta_ok == 2:
                total_score += scores["oem_metadata"]
                feedback.append("OEM metadata (OBJECT_NAME and INTERPOLATION_DEGREE) correct.")
            elif meta_ok == 1:
                total_score += scores["oem_metadata"] // 2
                feedback.append("OEM metadata partially correct.")
            else:
                feedback.append("OEM metadata incorrect or missing.")

            # Timespan
            start_time_m = re.search(r'START_TIME\s*=\s*(\S+)', oem_content)
            stop_time_m = re.search(r'STOP_TIME\s*=\s*(\S+)', oem_content)
            if start_time_m and stop_time_m:
                try:
                    fmt = "%Y-%m-%dT%H:%M:%S.%f"
                    t1 = datetime.strptime(start_time_m.group(1), fmt)
                    t2 = datetime.strptime(stop_time_m.group(1), fmt)
                    days = (t2 - t1).total_seconds() / 86400.0
                    if 13.9 <= days <= 14.1:
                        total_score += scores["oem_timespan"]
                        feedback.append("OEM timespan is exactly 14 days.")
                    else:
                        feedback.append(f"OEM timespan incorrect: {days:.2f} days (expected 14.0).")
                except ValueError:
                    feedback.append("OEM timestamp format unparseable.")
            else:
                feedback.append("OEM START_TIME or STOP_TIME not found.")

            # Step Size
            data_lines = re.findall(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3})\s+', oem_content, re.MULTILINE)
            if len(data_lines) >= 2:
                try:
                    fmt = "%Y-%m-%dT%H:%M:%S.%f"
                    t1 = datetime.strptime(data_lines[0], fmt)
                    t2 = datetime.strptime(data_lines[1], fmt)
                    step_sec = (t2 - t1).total_seconds()
                    if abs(step_sec - 60.0) < 0.1:
                        total_score += scores["oem_step_size"]
                        feedback.append("OEM step size is exactly 60 seconds.")
                    else:
                        feedback.append(f"OEM step size incorrect: {step_sec}s (expected 60s).")
                except ValueError:
                    feedback.append("OEM data line format unparseable.")
            else:
                feedback.append("Not enough data lines to determine step size.")

        except Exception as e:
            feedback.append(f"Error parsing OEM file: {e}")
        finally:
            if os.path.exists(temp_oem.name):
                os.unlink(temp_oem.name)

    # 6-7. Parse Script for accuracy parameters
    script_exists = task_result.get('script_file', {}).get('exists', False)
    if script_exists:
        script_path = task_result.get('script_path')
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Physical params (Low fidelity accuracy)
            has_sma = bool(re.search(r'SMA\s*=\s*42000', script_content))
            has_ecc = bool(re.search(r'ECC\s*=\s*0\.82', script_content))
            has_mass = bool(re.search(r'DryMass\s*=\s*1200', script_content))
            has_drag = bool(re.search(r'DragArea\s*=\s*4(\.0)?\b', script_content))
            has_srp_area = bool(re.search(r'SRPArea\s*=\s*15(\.0)?\b', script_content))
            
            phys_count = sum([has_sma, has_ecc, has_mass, has_drag, has_srp_area])
            if phys_count == 5:
                total_score += scores["low_fidelity_accuracy"]
                feedback.append("Basic orbital elements and physical properties correct.")
            elif phys_count >= 3:
                total_score += scores["low_fidelity_accuracy"] // 2
                feedback.append("Basic orbital elements partially correct.")
            else:
                feedback.append("Basic orbital elements missing or incorrect.")

            # Force Model (High fidelity accuracy)
            has_deg = bool(re.search(r'GravityField\.Earth\.Degree\s*=\s*10', script_content))
            has_ord = bool(re.search(r'GravityField\.Earth\.Order\s*=\s*10', script_content))
            has_luna = bool(re.search(r'PointMasses\s*=\s*\{[^}]*Luna[^}]*\}', script_content))
            has_sun = bool(re.search(r'PointMasses\s*=\s*\{[^}]*Sun[^}]*\}', script_content))
            has_drag_model = bool(re.search(r'Drag\.AtmosphereModel\s*=\s*JacchiaRoberts', script_content))
            has_srp = bool(re.search(r'SRP\s*=\s*On', script_content))

            fm_count = sum([has_deg and has_ord, has_luna, has_sun, has_drag_model, has_srp])
            if fm_count == 5:
                total_score += scores["high_fidelity_accuracy"]
                feedback.append("High-fidelity force model exactly as requested.")
            else:
                partial = int(scores["high_fidelity_accuracy"] * (fm_count / 5.0))
                total_score += partial
                feedback.append(f"Force model partially correct ({fm_count}/5 required perturbations).")

        except Exception as e:
            feedback.append(f"Error parsing script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("GMAT script not saved, cannot verify physical accuracy parameters.")

    passed = total_score >= 70 and oem_exists and spk_exists
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }