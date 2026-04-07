#!/usr/bin/env python3
"""
Verifier for multimission_payload_matrix task.

Verification Strategy (Verification by Physics + XML Analysis):
1. Mass Components Created (20 pts): Parse XML for 3 mass components matching Atmos, Bio, Dummy.
2. Configurations Created (20 pts): Parse XML for configs matching Alpha, Beta, Gamma.
3. Matrix Isolation / Overrides (30 pts): Analyzes the flightdata `launchmass` of up-to-date sims. 
   If overrides are correct, the 3 sims will have distinct launch masses differing exactly by 
   the payload deltas (Beta-Alpha ~150g, Alpha-Gamma ~100g).
4. Simulations Current (15 pts): Are there >=3 uptodate simulations?
5. Report (15 pts): Checks if mission_matrix_report.txt mentions the missions and altitudes.

Pass threshold: 65 points
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

def verify_multimission_payload_matrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/multimission_payload.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/mission_matrix_report.txt')

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------
    # Read result.json
    # ----------------------------------------------------
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not result.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file multimission_payload.ork not found. Agent did not save the design to the correct location."
        }

    # ----------------------------------------------------
    # Read and parse .ork
    # ----------------------------------------------------
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
    except Exception as e:
        parse_err = str(e)
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": f"Could not parse rocket file: {parse_err}"}

    # ----------------------------------------------------
    # Check 1: Payload Masses (20 pts)
    # ----------------------------------------------------
    found_masses = {'atmos': False, 'bio': False, 'dummy': False}
    for mc in ork_root.iter('masscomponent'):
        name = mc.findtext('name', '').lower()
        try:
            mass_val = float(mc.findtext('mass', '0'))
        except:
            mass_val = 0.0

        if 'atmos' in name and 0.135 <= mass_val <= 0.165:
            found_masses['atmos'] = True
        if 'bio' in name and 0.270 <= mass_val <= 0.330:
            found_masses['bio'] = True
        if 'dummy' in name and 0.040 <= mass_val <= 0.060:
            found_masses['dummy'] = True

    mass_count = sum(1 for v in found_masses.values() if v)
    if mass_count == 3:
        score += 20
        feedback_parts.append("All 3 payload masses created [20/20]")
    elif mass_count > 0:
        pts = int((mass_count/3)*20)
        score += pts
        feedback_parts.append(f"{mass_count}/3 payload masses created [{pts}/20]")
    else:
        feedback_parts.append("Expected payload masses not found [0/20]")

    # ----------------------------------------------------
    # Check 2: Flight Configurations (20 pts)
    # ----------------------------------------------------
    # OpenRocket configuration names could be in <flightconfiguration> or <configuration>
    found_configs = {'alpha': False, 'beta': False, 'gamma': False}
    for tag in ['flightconfiguration', 'configuration']:
        for fc in ork_root.iter(tag):
            name = (fc.get('name', '') or fc.findtext('name', '')).lower()
            if 'alpha' in name: found_configs['alpha'] = True
            if 'beta' in name: found_configs['beta'] = True
            if 'gamma' in name: found_configs['gamma'] = True

    config_count = sum(1 for v in found_configs.values() if v)
    if config_count == 3:
        score += 20
        feedback_parts.append("All 3 flight configurations created [20/20]")
    elif config_count > 0:
        pts = int((config_count/3)*20)
        score += pts
        feedback_parts.append(f"{config_count}/3 flight configurations created [{pts}/20]")
    else:
        feedback_parts.append("Expected flight configurations not found [0/20]")

    # ----------------------------------------------------
    # Check 3 & 4: Simulations & Physics Matrix Isolation (15 + 30 pts)
    # ----------------------------------------------------
    sims = ork_root.find('simulations')
    uptodate_count = 0
    launch_masses = set()
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        # Round to 3 decimal places (grams) to group identical masses
                        m = round(float(fd.get('launchmass', '0')), 3)
                        if m > 0.5: # Realistic mass
                            launch_masses.add(m)
                    except:
                        pass

    # Scoring Simulations Current (15 pts)
    if uptodate_count >= 3:
        score += 15
        feedback_parts.append(f"{uptodate_count} simulations are uptodate [15/15]")
    elif uptodate_count > 0:
        score += 5
        feedback_parts.append(f"Only {uptodate_count} simulations uptodate [5/15]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15]")

    # Scoring Matrix Isolation via Physics (30 pts)
    # We expect 3 distinct launch masses. 
    # M_beta (300g) - M_alpha (150g) = 150g delta
    # M_alpha (150g) - M_dummy (50g) = 100g delta
    sorted_masses = sorted(list(launch_masses))
    if len(sorted_masses) >= 3:
        score += 30
        feedback_parts.append("Physics check: Overrides verified (3 distinct isolated launch masses) [30/30]")
    elif len(sorted_masses) == 2:
        score += 10
        feedback_parts.append("Physics check: Partial isolation (only 2 distinct launch masses) [10/30]")
    else:
        feedback_parts.append("Physics check: Isolation failed (Payloads not overriding correctly) [0/30]")

    # ----------------------------------------------------
    # Check 5: Mission Report (15 pts)
    # ----------------------------------------------------
    report_pts = 0
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r') as f:
            content = f.read().lower()
            
            # Check for mention of the missions
            has_alpha = 'alpha' in content
            has_beta = 'beta' in content
            has_gamma = 'gamma' in content
            # Check if any digits are present (likely altitude)
            has_numbers = bool(re.search(r'\d+', content))
            
            if has_alpha and has_beta and has_gamma and has_numbers:
                report_pts = 15
                feedback_parts.append("Report contains all missions and altitude data [15/15]")
            elif (has_alpha or has_beta or has_gamma) and has_numbers:
                report_pts = 8
                feedback_parts.append("Report partially complete [8/15]")
            else:
                feedback_parts.append("Report exists but missing mission details [0/15]")
    except Exception:
        feedback_parts.append("Report file not found [0/15]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)
            
    score += report_pts

    # ----------------------------------------------------
    # Final Result
    # ----------------------------------------------------
    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }