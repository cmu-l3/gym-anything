#!/usr/bin/env python3
"""
Verifier for preflight_mass_calibration task.

Scoring breakdown (100 points total):
  12 pts - Nose Cone mass override (28.5g ±2g)
  12 pts - Body Tube mass override (38.0g ±2g)
  12 pts - Fin Set mass override (12.5g ±2g)
  12 pts - Parachute mass override (15.0g ±2g)
  12 pts - Inner Tube mass override (5.5g ±2g)
  15 pts - Simulation run (at least one uptodate)
  15 pts - Mass properties report containing required keywords
  10 pts - File saved correctly (differs from original, created after start)

Pass threshold: 60 points
  Do-nothing max: 0
"""

import os
import re
import json
import tempfile
import zipfile
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
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"


def _check_component_override(root, tag_name, expected_g, tolerance_g=2.0):
    """Checks if the component has the correct override applied."""
    for elem in root.iter(tag_name):
        is_overridden = elem.findtext('massoverridden', 'false').lower() == 'true'
        try:
            # OpenRocket stores mass in kg
            mass_g = float(elem.findtext('overridemass', '0')) * 1000.0
        except (ValueError, TypeError):
            mass_g = 0.0

        if is_overridden and abs(mass_g - expected_g) <= tolerance_g:
            return True, mass_g
        return False, mass_g
    return False, 0.0


def verify_preflight_mass_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    output_ork_vm = metadata.get('output_ork', '/home/ga/Documents/rockets/calibrated_simple_rocket.ork')
    report_vm = metadata.get('output_report', '/home/ga/Documents/exports/mass_properties_report.txt')
    targets = metadata.get('components', {})
    tolerance = metadata.get('tolerance_g', 2.0)

    score = 0
    feedback_parts = []
    
    # ---- Read Exported JSON ----
    result = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env('/tmp/mass_calibration_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result json: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    ork_exists = result.get('ork_exists', False)
    report_exists = result.get('report_exists', False)
    ork_mtime = result.get('ork_mtime', 0)
    task_start = result.get('task_start_ts', 0)
    ork_md5 = result.get('ork_md5', '')
    orig_md5 = result.get('orig_md5', '')

    if not ork_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_ork_vm}."
        }

    # ---- Copy Output .ork file ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(output_ork_vm, tmp_ork.name)
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

    # ---- Check 1-5: Component Mass Overrides (12 pts each) ----
    component_tags = {
        'nosecone': ('Nose Cone', targets.get('nosecone', 28.5)),
        'bodytube': ('Body Tube', targets.get('bodytube', 38.0)),
        'trapezoidfinset': ('Fin Set', targets.get('trapezoidfinset', 12.5)),
        'parachute': ('Parachute', targets.get('parachute', 15.0)),
        'innertube': ('Inner Tube', targets.get('innertube', 5.5))
    }

    for tag, (friendly_name, expected_g) in component_tags.items():
        ok, mass_g = _check_component_override(ork_root, tag, expected_g, tolerance)
        if ok:
            score += 12
            feedback_parts.append(f"{friendly_name} override correct ({mass_g:.1f}g) [12/12]")
        else:
            if mass_g > 0:
                feedback_parts.append(f"{friendly_name} override incorrect (found {mass_g:.1f}g, expected {expected_g}g) [0/12]")
            else:
                feedback_parts.append(f"{friendly_name} override not set [0/12]")

    # ---- Check 6: Simulation run (15 pts) ----
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
        feedback_parts.append("No uptodate simulations found [0/15]")

    # ---- Check 7: File saved correctly and modified (10 pts) ----
    # Must exist, must be modified after start, and must differ from original
    if ork_exists and ork_md5 != orig_md5 and ork_mtime >= task_start:
        score += 10
        feedback_parts.append("Calibrated file saved correctly [10/10]")
    else:
        feedback_parts.append("Calibrated file not genuinely modified/saved during task [0/10]")

    # ---- Check 8: Mass properties report (15 pts) ----
    if report_exists:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                
            # Keyword checks
            has_mass = any(word in content for word in ['mass', 'weight', 'gram', ' g'])
            has_cg = any(word in content for word in ['cg', 'center of gravity', 'centre'])
            has_stability = any(word in content for word in ['stability', 'margin', 'caliber', 'calibre'])
            has_apogee = any(word in content for word in ['apogee', 'altitude', 'height'])
            has_rec = any(word in content for word in ['go', 'safe', 'fly', 'recommend', 'stable'])
            
            if len(content) > 100 and has_mass and has_cg and has_stability and has_apogee and has_rec:
                score += 15
                feedback_parts.append("Report complete and comprehensive [15/15]")
            elif len(content) > 50 and (has_mass or has_stability):
                score += 7
                feedback_parts.append("Report partially complete [7/15]")
            else:
                feedback_parts.append("Report lacks required content/keywords [0/15]")
                
        except Exception as e:
            feedback_parts.append(f"Failed to read report: {e} [0/15]")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report file not found [0/15]")

    pass_threshold = metadata.get('pass_threshold', 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }