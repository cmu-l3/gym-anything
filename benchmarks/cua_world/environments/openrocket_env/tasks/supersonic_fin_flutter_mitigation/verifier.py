#!/usr/bin/env python3
"""
Verifier for supersonic_fin_flutter_mitigation task.

Scoring breakdown (100 points total):
  20 pts - Aerotech K550W motor selected
  20 pts - Trapezoidal fins thickened to >= 5.0mm
  15 pts - Fin material changed to composite (Fiberglass/Carbon fiber, density >= 1500)
  20 pts - Nose ballast >= 0.3kg added inside nose cone
  15 pts - At least one simulation run and 'uptodate'
  10 pts - Engineering report written

Pass threshold: 70 points
  Requires Motor + Fins + Ballast mitigations to pass, preventing partial credit gaming.
"""

import os
import re
import tempfile
import zipfile
import json
import xml.etree.ElementTree as ET


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


def verify_supersonic_fin_flutter_mitigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    upgrade_ork_path = metadata.get('upgrade_ork_vm_path', '/home/ga/Documents/rockets/supersonic_upgrade.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/flutter_report.txt')
    
    expected_motor = metadata.get('expected_motor', 'K550')
    min_fin_thick = metadata.get('min_fin_thickness_m', 0.0049)
    min_density = metadata.get('min_composite_density', 1500.0)
    min_ballast = metadata.get('min_ballast_mass_kg', 0.29)

    score = 0
    feedback_parts = []
    
    # ---- Read Exported Result ----
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    result_data = {}
    try:
        copy_from_env("/tmp/flutter_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    if not result_data.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target .ork file was not saved to the correct location."
        }

    # ---- Copy .ork file from VM ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(upgrade_ork_path, tmp_ork.name)
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
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve rocket file."
        }

    # ---- Check 1: Motor Assignment (20 pts) ----
    has_motor = False
    for motor in ork_root.iter('motor'):
        desig = motor.findtext('designation', '').upper()
        if expected_motor in desig:
            has_motor = True
            break
            
    if has_motor:
        score += 20
        feedback_parts.append(f"Motor {expected_motor} assigned [20/20]")
    else:
        feedback_parts.append(f"Motor {expected_motor} not found [0/20]")

    # ---- Check 2 & 3: Fin Thickness and Material (20 + 15 pts) ----
    is_thick = False
    is_composite = False
    max_thickness = 0.0
    max_density = 0.0
    
    for fin in ork_root.iter('trapezoidfinset'):
        try:
            t = float(fin.findtext('thickness', '0'))
            max_thickness = max(max_thickness, t)
            if t >= min_fin_thick:
                is_thick = True
        except:
            pass
            
        mat = fin.find('material')
        if mat is not None:
            try:
                d = float(mat.get('density', '0'))
                max_density = max(max_density, d)
                if d >= min_density:
                    is_composite = True
            except:
                pass

    if is_thick:
        score += 20
        feedback_parts.append(f"Fins thickened to {max_thickness*1000:.1f}mm [20/20]")
    else:
        feedback_parts.append(f"Fins only {max_thickness*1000:.1f}mm (needs >= 5.0mm) [0/20]")
        
    if is_composite:
        score += 15
        feedback_parts.append(f"Fin material is composite (density {max_density:.0f}) [15/15]")
    else:
        feedback_parts.append(f"Fin material not composite (density {max_density:.0f}) [0/15]")

    # ---- Check 4: Nose Ballast (20 pts) ----
    has_ballast = False
    max_mass = 0.0
    
    for nc in ork_root.iter('nosecone'):
        for mc in nc.iter('masscomponent'):
            try:
                m = float(mc.findtext('mass', '0'))
                max_mass = max(max_mass, m)
                if m >= min_ballast:
                    has_ballast = True
            except:
                pass
                
    if has_ballast:
        score += 20
        feedback_parts.append(f"Nose ballast of {max_mass:.2f}kg found [20/20]")
    else:
        feedback_parts.append(f"Insufficient nose ballast ({max_mass:.2f}kg) [0/20]")

    # ---- Check 5: Simulation Run (15 pts) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count > 0:
        score += 15
        feedback_parts.append(f"Simulation is uptodate [15/15]")
    else:
        feedback_parts.append("No uptodate simulation found [0/15]")

    # ---- Check 6: Engineering Report (10 pts) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_content = ""
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.getsize(tmp_report.name) > 10:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read().lower()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    if len(report_content) > 20:
        # Check for presence of required keywords
        kws = sum(1 for kw in ['k550', 'thick', 'mm', 'fiber', 'ballast', 'mass', 'kg', 'stabil'] if kw in report_content)
        if kws >= 3:
            score += 10
            feedback_parts.append("Engineering report is valid [10/10]")
        else:
            score += 5
            feedback_parts.append("Engineering report exists but lacks keywords [5/10]")
    else:
        feedback_parts.append("Report missing or empty [0/10]")

    # ---- Final Evaluation ----
    pass_threshold = metadata.get('pass_threshold', 70)
    
    # Must fix the core engineering problem to pass (Motor + Fins + Ballast)
    core_fixes = has_motor and is_thick and has_ballast
    passed = (score >= pass_threshold) and core_fixes
    
    if not core_fixes and score >= pass_threshold:
        feedback_parts.append("FAILED: Did not implement all required engineering fixes (Motor, Fins, and Ballast)")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }