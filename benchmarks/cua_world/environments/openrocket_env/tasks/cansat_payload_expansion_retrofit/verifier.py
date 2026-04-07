#!/usr/bin/env python3
"""
Verifier for CanSat Payload Expansion Retrofit task.
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return the root element."""
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


def verify_cansat_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_radius = metadata.get('expected_radius_m', 0.033)
    radius_tol = metadata.get('expected_radius_tolerance', 0.0015)
    original_radius = metadata.get('original_radius_m', 0.0124)
    orig_radius_tol = metadata.get('original_radius_tolerance', 0.0015)
    expected_mass = metadata.get('expected_mass_kg', 0.08)
    mass_tol = metadata.get('expected_mass_tolerance', 0.005)
    min_length = metadata.get('min_payload_length_m', 0.095)
    min_apogee = metadata.get('min_apogee_m', 50.0)

    score = 0
    feedback_parts = []
    
    # 1. Check basic export results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cansat_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get('ork_exists', False):
        return {"passed": False, "score": 0, "feedback": "Target ORK file not found. Task failed."}
    if not export_data.get('ork_created_during_task', False):
        feedback_parts.append("Warning: ORK file mtime is older than task start.")

    # 2. Extract and parse the .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(metadata.get('target_ork', '/home/ga/Documents/rockets/cansat_retrofit.ork'), tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse target ORK: {parse_err}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error extracting ORK: {e}"}
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    # 3. Analyze XML Structure
    
    # Check A: Transition Geometry (20 pts)
    # Looking for a transition that connects ~12.4mm to ~33mm radius
    transition_found = False
    for trans in ork_root.iter('transition'):
        try:
            fore_r = float(trans.findtext('foreradius', '0'))
            aft_r = float(trans.findtext('aftradius', '0'))
            # Transition could be oriented either way depending on how the agent built it
            if (abs(fore_r - expected_radius) <= radius_tol and abs(aft_r - original_radius) <= orig_radius_tol) or \
               (abs(aft_r - expected_radius) <= radius_tol and abs(fore_r - original_radius) <= orig_radius_tol):
                transition_found = True
                break
        except Exception:
            pass

    if transition_found:
        score += 20
        feedback_parts.append("Transition expanding to ~66mm diameter found [20/20]")
    else:
        feedback_parts.append("Valid Transition component to 66mm diameter NOT found [0/20]")

    # Check B: Payload Body Tube (20 pts)
    # Looking for a body tube with ~33mm radius and >= 95mm length
    payload_tube_found = False
    for bt in ork_root.iter('bodytube'):
        try:
            r = float(bt.findtext('radius', '0'))
            l = float(bt.findtext('length', '0'))
            if abs(r - expected_radius) <= radius_tol and l >= min_length:
                payload_tube_found = True
                break
        except Exception:
            pass

    if payload_tube_found:
        score += 20
        feedback_parts.append("Payload Body Tube (~66mm dia, >100mm len) found [20/20]")
    else:
        feedback_parts.append("Valid Payload Body Tube NOT found [0/20]")

    # Check C: Nose Cone Geometry (10 pts)
    # Looking for a nose cone with ~33mm radius
    nosecone_found = False
    for nc in ork_root.iter('nosecone'):
        try:
            r = float(nc.findtext('radius', '0'))
            # Exclude the original nose cone if it was accidentally left in
            if abs(r - expected_radius) <= radius_tol:
                nosecone_found = True
                break
        except Exception:
            pass
            
    if nosecone_found:
        score += 10
        feedback_parts.append("Wide Nose Cone (~66mm dia) found [10/10]")
    else:
        feedback_parts.append("Wide Nose Cone NOT found [0/10]")

    # Check D: CanSat Mass Integration (15 pts)
    # Looking for mass component ~80g
    mass_found = False
    for mc in ork_root.iter('masscomponent'):
        try:
            m = float(mc.findtext('mass', '0'))
            if abs(m - expected_mass) <= mass_tol:
                mass_found = True
                break
        except Exception:
            pass

    if mass_found:
        score += 15
        feedback_parts.append("80g Mass Component found [15/15]")
    else:
        feedback_parts.append("80g Mass Component NOT found [0/15]")

    # Check E: Propulsion Upgrade (15 pts)
    # The original is A8-3. We need a C, D, E, or F motor.
    upgraded_motor = False
    for motor in ork_root.iter('motor'):
        desig = motor.findtext('designation', '').upper().strip()
        if desig and desig[0] in ['C', 'D', 'E', 'F', 'G']:
            upgraded_motor = True
            break
            
    if upgraded_motor:
        score += 15
        feedback_parts.append("Upgraded motor configuration found [15/15]")
    else:
        feedback_parts.append("Upgraded motor (C-class or higher) NOT found [0/15]")

    # Check F: Flight Verification (10 pts)
    # Look for uptodate sim with apogee >= 50m
    valid_sim = False
    sims_elem = ork_root.find('simulations')
    if sims_elem is not None:
        for sim in sims_elem.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        apogee = float(fd.get('maxaltitude', '0'))
                        if apogee >= min_apogee:
                            valid_sim = True
                            break
                    except Exception:
                        pass

    if valid_sim:
        score += 10
        feedback_parts.append(f"Uptodate simulation with apogee >= {min_apogee}m found [10/10]")
    else:
        feedback_parts.append("Uptodate simulation with adequate apogee NOT found [0/10]")

    # Check G: Integration Report (10 pts)
    if export_data.get('report_exists', False):
        try:
            tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env(metadata.get('target_report', '/home/ga/Documents/exports/cansat_report.txt'), tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                content = f.read().lower()
            os.unlink(tmp_report.name)
            
            # Very basic checks: exists, has content, mentions 66 or 80
            if len(content) > 20 and ("80" in content or "66" in content):
                score += 10
                feedback_parts.append("Valid integration report found [10/10]")
            else:
                score += 5
                feedback_parts.append("Integration report found but lacks specific metrics [5/10]")
        except Exception:
            feedback_parts.append("Integration report exists but could not be parsed [0/10]")
    else:
        feedback_parts.append("Integration report NOT found [0/10]")

    # Determine pass/fail
    # Must get the geometry modifications right (transition + payload tube = 40) 
    # and either upgrade the motor or get the mass right to prove understanding of the retrofit.
    passed = score >= 70 and transition_found and payload_tube_found
    
    if passed:
        feedback_parts.insert(0, "SUCCESS: CanSat expansion retrofit successfully performed.")
    else:
        feedback_parts.insert(0, "FAILED: Required structural retrofits or flight metrics not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }