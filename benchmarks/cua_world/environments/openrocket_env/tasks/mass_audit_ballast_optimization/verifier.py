#!/usr/bin/env python3
"""
Verifier for mass_audit_ballast_optimization task.

Scoring breakdown (100 points total):
  25 pts - Ballast mass component added (was NOT in original file)
  15 pts - Ballast mass is reasonable (between 30g and 300g)
  15 pts - Electronics payload preserved (mass >= 100g, agent didn't just delete it)
  20 pts - At least one simulation has 'uptodate' status (re-run after fixes)
  15 pts - Adequate stability (Ground hit velocity <= 15 m/s or via flight data)
  10 pts - Mass budget report file exists with meaningful content (>=200 chars + keywords)

Pass threshold: 60 points
  Anti-gaming: If the ORK file hash is unchanged, score is 0. If Electronics Payload is missing, 
               fails preservation criterion (lose 15 pts).
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

def verify_mass_audit_ballast_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/mass_audit_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/mass_budget_report.txt')
    
    min_ballast = metadata.get('min_ballast_mass_kg', 0.030)
    max_ballast = metadata.get('max_ballast_mass_kg', 0.300)

    score = 0
    feedback_parts = []
    details = {}

    # ---- Fetch Result JSON for Anti-Gaming and Fast-Fails ----
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    try:
        copy_from_env("/tmp/mass_audit_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception:
        result_data = {}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # Check Anti-Gaming Initial Hash
    tmp_hash = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_hash.close()
    initial_hash = ""
    try:
        copy_from_env("/tmp/initial_ork_hash.txt", tmp_hash.name)
        with open(tmp_hash.name, 'r') as f:
            initial_hash = f.read().strip()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_hash.name):
            os.unlink(tmp_hash.name)

    current_hash = result_data.get('ork_hash', '')
    if current_hash and initial_hash and current_hash == initial_hash:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Agent made no modifications to the .ork file (hash unchanged)."
        }

    # ---- Copy .ork file from VM ----
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

    # ---- Analyze Mass Components ----
    elec_mass = 0.0
    ballast_mass = 0.0
    
    # Check general mass components
    for mc in ork_root.iter('masscomponent'):
        name = mc.findtext('name', '').lower()
        try:
            mass = float(mc.findtext('mass', '0'))
        except ValueError:
            mass = 0.0
            
        if 'electronic' in name or 'payload' in name or 'altimeter' in name:
            elec_mass = max(elec_mass, mass)
        else:
            ballast_mass = max(ballast_mass, mass)

    # Sometimes agents put it strictly inside the nosecone element directly
    for nc in ork_root.iter('nosecone'):
        for mc in nc.iter('masscomponent'):
            name = mc.findtext('name', '').lower()
            try:
                mass = float(mc.findtext('mass', '0'))
            except ValueError:
                mass = 0.0
                
            if not ('electronic' in name or 'payload' in name):
                ballast_mass = max(ballast_mass, mass)

    details['electronics_mass_kg'] = elec_mass
    details['ballast_mass_kg'] = ballast_mass

    # Criterion 1: Ballast added (25 pts)
    if ballast_mass > 0.0:
        score += 25
        feedback_parts.append(f"Ballast component found ({ballast_mass*1000:.1f}g) [25/25 pts]")
    else:
        feedback_parts.append("No new mass component (ballast) found [0/25 pts]")

    # Criterion 2: Ballast reasonable (15 pts)
    if ballast_mass > 0.0:
        if min_ballast <= ballast_mass <= max_ballast:
            score += 15
            feedback_parts.append(f"Ballast mass is in reasonable range ({min_ballast*1000}-{max_ballast*1000}g) [15/15 pts]")
        elif ballast_mass < min_ballast:
            score += 5
            feedback_parts.append(f"Ballast mass ({ballast_mass*1000:.1f}g) is suspiciously light [5/15 pts]")
        else:
            score += 5
            feedback_parts.append(f"Ballast mass ({ballast_mass*1000:.1f}g) is unnecessarily heavy [5/15 pts]")
    else:
        feedback_parts.append("Ballast mass check failed [0/15 pts]")

    # Criterion 3: Electronics payload preserved (15 pts)
    if elec_mass >= 0.100:  # Allow slight rounding variation from 120g
        score += 15
        feedback_parts.append(f"Electronics payload correctly preserved ({elec_mass*1000:.1f}g) [15/15 pts]")
    elif elec_mass > 0:
        score += 5
        feedback_parts.append(f"Electronics payload present but mass altered severely ({elec_mass*1000:.1f}g) [5/15 pts]")
    else:
        feedback_parts.append("Electronics payload deleted/missing (Agent evaded problem) [0/15 pts]")

    # Criterion 4: Simulation Re-Run (20 pts)
    sims = ork_root.find('simulations')
    uptodate_count = 0
    ghv_values = []
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        ghv_values.append(float(fd.get('groundhitvelocity', '999')))
                    except (ValueError, TypeError):
                        pass

    details['uptodate_sims'] = uptodate_count
    if uptodate_count >= 1:
        score += 20
        feedback_parts.append(f"Simulation correctly re-run ({uptodate_count} up-to-date) [20/20 pts]")
    else:
        feedback_parts.append("No up-to-date simulations found. Simulations must be re-run after fix [0/20 pts]")

    # Criterion 5: Safe Ground Hit Velocity (15 pts)
    if ghv_values:
        min_ghv = min(ghv_values)
        if min_ghv <= 15.0:
            score += 15
            feedback_parts.append(f"Safe Ground Hit Velocity verified ({min_ghv:.1f} m/s) [15/15 pts]")
        else:
            feedback_parts.append(f"Ground Hit Velocity dangerously high ({min_ghv:.1f} m/s) [0/15 pts]")
    elif uptodate_count >= 1:
        # Give partial credit if simulation ran but flight data extraction failed
        score += 8
        feedback_parts.append("Simulation re-run but flight data couldn't be evaluated for GHV [8/15 pts]")
    else:
        feedback_parts.append("Cannot verify safe flight data without a simulation run [0/15 pts]")

    # Criterion 6: Mass Budget Report (10 pts)
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_content = ""
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name):
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)
            
    # Check for report content
    if len(report_content) >= 150:
        keywords = ['mass', 'ballast', 'weight', 'stabil', 'margin', 'cg', 'cp', 'simulat', 'velocit', 'altitud']
        hits = sum(1 for kw in keywords if kw.lower() in report_content.lower())
        
        if hits >= 4:
            score += 10
            feedback_parts.append(f"Mass budget report found with relevant technical content ({hits} keywords) [10/10 pts]")
        elif hits >= 2:
            score += 5
            feedback_parts.append(f"Mass budget report found but missing some detail ({hits} keywords) [5/10 pts]")
        else:
            feedback_parts.append(f"Mass budget report lacks expected technical keywords [0/10 pts]")
    else:
        feedback_parts.append("Mass budget report missing or too short [0/10 pts]")

    # Final tally
    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }