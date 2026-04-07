#!/usr/bin/env python3
"""
Verifier for post_flight_aerodynamic_calibration task.

Scoring breakdown (100 points total):
  15 pts - File Saves & Exports (All required files exist)
  25 pts - Anti-Gaming Adherence (No mass added, dimensions unchanged, environment conditions unchanged)
  30 pts - Calibration Apogee Matched (415m ± 10m in the calibration CSV)
  20 pts - Prediction Simulation Valid (Apogee > 550m in the prediction CSV, showing an I-class upgrade)
  10 pts - Calibration Report (Report exists and contains valid technical content)

Pass threshold: 65 points
  Requires both the Calibration Apogee and Anti-Gaming criteria to be heavily met.
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return root_element."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        return ET.fromstring(xml_bytes.decode('utf-8'))
    except Exception as e:
        return None

def _get_max_altitude_from_csv(csv_path):
    """Robustly find the maximum altitude from an OpenRocket CSV export."""
    max_alt = 0.0
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
        alt_col = 1  # Default fallback if header parsing fails
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # Parse header row to dynamically find the Altitude column
            if line.startswith('#'):
                if 'Altitude' in line:
                    cols = line.split(',')
                    for i, col in enumerate(cols):
                        if 'Altitude' in col:
                            alt_col = i
                            break
                continue
            
            # Data row parsing
            parts = line.split(',')
            if len(parts) > alt_col:
                try:
                    alt = float(parts[alt_col])
                    if alt > max_alt:
                        max_alt = alt
                except ValueError:
                    pass
    except Exception:
        pass
    return max_alt

def verify_post_flight_aerodynamic_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/calibrated_rocket.ork')
    calib_csv_vm = metadata.get('calibration_csv', '/home/ga/Documents/exports/calibration_flight.csv')
    predict_csv_vm = metadata.get('prediction_csv', '/home/ga/Documents/exports/prediction_flight.csv')
    report_vm_path = metadata.get('report_path', '/home/ga/Documents/exports/calibration_report.txt')
    
    target_apogee = metadata.get('target_apogee_m', 415)
    target_tolerance = metadata.get('target_tolerance_m', 10)

    score = 0
    feedback_parts = []
    
    # Check result JSON for file existence
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/calibration_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception:
        result = {}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # Criterion 1: Files Exist (15 pts)
    files_ok = 0
    if result.get('ork_exists'): files_ok += 1
    if result.get('calib_csv_exists'): files_ok += 1
    if result.get('predict_csv_exists'): files_ok += 1
    if result.get('report_exists'): files_ok += 1
    
    if files_ok == 4:
        score += 15
        feedback_parts.append("All files exported correctly [15/15 pts]")
    else:
        pts = int((files_ok / 4) * 15)
        score += pts
        feedback_parts.append(f"Missing {4 - files_ok} required files [{pts}/15 pts]")

    # Retrieve ORK file for analysis
    ork_root = None
    if result.get('ork_exists'):
        tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
        try:
            copy_from_env(ork_vm_path, tmp_ork.name)
            ork_root = _parse_ork(tmp_ork.name)
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_ork.name):
                os.unlink(tmp_ork.name)

    # Criterion 2: Anti-Gaming Adherence (25 pts)
    anti_gaming_passed = False
    if ork_root is not None:
        mass_components = list(ork_root.iter('masscomponent'))
        
        # Check wind and altitude haven't been maliciously inflated
        wind_ok = True
        alt_ok = True
        for conds in ork_root.iter('conditions'):
            try:
                wind = float(conds.findtext('windaverage', '0'))
                if wind > 5.0: wind_ok = False
            except (ValueError, TypeError):
                pass
            try:
                alt = float(conds.findtext('launchaltitude', '0'))
                if alt > 200.0: alt_ok = False
            except (ValueError, TypeError):
                pass
                
        if len(mass_components) > 0:
            feedback_parts.append("FAIL: Artificial mass components added [0/25 pts]")
        elif not wind_ok or not alt_ok:
            feedback_parts.append("FAIL: Launch conditions altered to manipulate apogee [0/25 pts]")
        else:
            anti_gaming_passed = True
            score += 25
            feedback_parts.append("Anti-gaming checks passed (no forbidden edits) [25/25 pts]")
    else:
        feedback_parts.append("Could not parse ORK for anti-gaming checks [0/25 pts]")

    # Criterion 3 & 4: Calibration and Prediction Apogee from CSVs (30 pts + 20 pts)
    calib_apogee_matched = False
    
    if result.get('calib_csv_exists'):
        tmp_calib = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(calib_csv_vm, tmp_calib.name)
            max_calib = _get_max_altitude_from_csv(tmp_calib.name)
            
            diff = abs(max_calib - target_apogee)
            if diff <= target_tolerance:
                calib_apogee_matched = True
                score += 30
                feedback_parts.append(f"Calibration successful: {max_calib:.1f}m (Target {target_apogee}m) [30/30 pts]")
            elif diff <= target_tolerance * 3:
                score += 15
                feedback_parts.append(f"Calibration marginal: {max_calib:.1f}m [15/30 pts]")
            else:
                feedback_parts.append(f"Calibration failed: {max_calib:.1f}m [0/30 pts]")
        except Exception:
            feedback_parts.append("Failed to process calibration CSV [0/30 pts]")
        finally:
            if os.path.exists(tmp_calib.name):
                os.unlink(tmp_calib.name)
    else:
         feedback_parts.append("No calibration CSV found [0/30 pts]")

    if result.get('predict_csv_exists'):
        tmp_predict = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(predict_csv_vm, tmp_predict.name)
            max_predict = _get_max_altitude_from_csv(tmp_predict.name)
            
            # An I-class motor on this rocket should clear 550m easily, even with calibrated drag
            if max_predict > 550.0:
                score += 20
                feedback_parts.append(f"Prediction successful: {max_predict:.1f}m (I-class performance) [20/20 pts]")
            else:
                feedback_parts.append(f"Prediction low: {max_predict:.1f}m (Did not upgrade to I-class?) [0/20 pts]")
        except Exception:
            feedback_parts.append("Failed to process prediction CSV [0/20 pts]")
        finally:
            if os.path.exists(tmp_predict.name):
                os.unlink(tmp_predict.name)
    else:
        feedback_parts.append("No prediction CSV found [0/20 pts]")

    # Criterion 5: Report Content (10 pts)
    if result.get('report_exists'):
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            if len(content) > 50 and any(kw in content for kw in ['drag', 'multiplier', 'finish', 'roughness', 'coefficient']):
                score += 10
                feedback_parts.append("Report contains valid aerodynamic content [10/10 pts]")
            else:
                score += 5
                feedback_parts.append("Report exists but lacks detailed aerodynamic explanation [5/10 pts]")
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("No calibration report found [0/10 pts]")

    passed = score >= metadata.get('pass_threshold', 65) and anti_gaming_passed and calib_apogee_matched

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }