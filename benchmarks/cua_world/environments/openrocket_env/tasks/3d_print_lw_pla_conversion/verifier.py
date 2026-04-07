#!/usr/bin/env python3
"""
Verifier for 3d_print_lw_pla_conversion task.

Scoring breakdown (100 points total):
  10 pts - Nose Cone density set to ~650 kg/m³
  10 pts - Exterior Body Tube density set to ~650 kg/m³
  10 pts - Fin Set density set to ~650 kg/m³
  25 pts - Mass component (ballast) added to the Nose Cone
  10 pts - Ballast mass is sufficient (>= 10g)
  15 pts - At least one simulation is marked 'uptodate'
  20 pts - lw_pla_report.txt exists and contains keywords (0.65/LW-PLA, ballast, stability)

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


def _get_density(elem):
    """Extract density from an OpenRocket XML element's material tag."""
    mat = elem.find('material')
    if mat is not None:
        try:
            return float(mat.get('density', 0))
        except ValueError:
            pass
    return 0.0


def verify_3d_print_lw_pla_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    output_ork = metadata.get('output_ork_path', '/home/ga/Documents/rockets/janus_lw_pla.ork')
    output_report = metadata.get('output_report_path', '/home/ga/Documents/exports/lw_pla_report.txt')
    target_density = metadata.get('target_density_kgm3', 650.0)
    density_tol = metadata.get('density_tolerance_kgm3', 20.0)
    min_ballast = metadata.get('min_ballast_mass_kg', 0.01)

    score = 0
    feedback_parts = []
    
    # ---- Read Exported Result JSON ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception:
        result = {"ork_exists": False, "report_exists": False}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get('ork_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output .ork file not found at {output_ork}"
        }

    # ---- Copy .ork file from VM ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(output_ork, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Failed to read XML"}

    # ---- Check 1: Nose Cone Density (10 pts) ----
    nc_density = 0.0
    for nc in ork_root.iter('nosecone'):
        d = _get_density(nc)
        if d > 0:
            nc_density = d
            break
            
    if abs(nc_density - target_density) <= density_tol:
        score += 10
        feedback_parts.append(f"Nose Cone density updated to {nc_density} kg/m³ [10/10]")
    else:
        feedback_parts.append(f"Nose Cone density is {nc_density} (expected ~{target_density}) [0/10]")

    # ---- Check 2: Body Tube Density (10 pts) ----
    bt_densities = []
    for bt in ork_root.iter('bodytube'):
        d = _get_density(bt)
        if d > 0:
            bt_densities.append(d)
            
    # We pass if at least one exterior body tube matches (ignoring internal motor mounts that might be standard)
    bt_success = any(abs(d - target_density) <= density_tol for d in bt_densities)
    if bt_success:
        score += 10
        feedback_parts.append("Body Tube density successfully updated [10/10]")
    else:
        feedback_parts.append(f"No Body Tube has the target density [0/10]")

    # ---- Check 3: Fin Set Density (10 pts) ----
    fin_density = 0.0
    for fin_tag in ['trapezoidfinset', 'freeformfinset', 'ellipticalfinset']:
        for fin in ork_root.iter(fin_tag):
            d = _get_density(fin)
            if d > 0:
                fin_density = d
                break
                
    if abs(fin_density - target_density) <= density_tol:
        score += 10
        feedback_parts.append(f"Fin Set density updated to {fin_density} kg/m³ [10/10]")
    else:
        feedback_parts.append(f"Fin Set density is {fin_density} [0/10]")

    # ---- Check 4 & 5: Nose Ballast Added & Sufficient (25 pts + 10 pts) ----
    ballast_found = False
    max_ballast_mass = 0.0
    for nc in ork_root.iter('nosecone'):
        for mc in nc.iter('masscomponent'):
            ballast_found = True
            m_text = mc.findtext('mass', '0')
            try:
                max_ballast_mass = max(max_ballast_mass, float(m_text))
            except ValueError:
                pass

    if ballast_found:
        score += 25
        feedback_parts.append("Mass component (ballast) added to Nose Cone [25/25]")
        
        if max_ballast_mass >= min_ballast:
            score += 10
            feedback_parts.append(f"Ballast mass is sufficient: {max_ballast_mass*1000:.1f}g [10/10]")
        else:
            feedback_parts.append(f"Ballast mass is too small: {max_ballast_mass*1000:.1f}g (needs >= 10g) [0/10]")
    else:
        feedback_parts.append("No Mass component found inside the Nose Cone [0/35]")

    # ---- Check 6: Simulation Status (15 pts) ----
    sims_elem = ork_root.find('simulations')
    uptodate_count = 0
    if sims_elem is not None:
        for sim in sims_elem.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                
    if uptodate_count > 0:
        score += 15
        feedback_parts.append("Simulation successfully re-run [15/15]")
    else:
        feedback_parts.append("No up-to-date simulation found [0/15]")

    # ---- Check 7: Conversion Report (20 pts) ----
    report_pts = 0
    if result.get('report_exists'):
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(output_report, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                content = f.read().lower()
            
            has_density = '0.65' in content or 'lw-pla' in content or '650' in content
            has_ballast = 'ballast' in content or 'mass' in content or 'weight' in content
            has_stability = '1.5' in content or 'stability' in content or 'margin' in content
            
            if has_density and has_ballast and has_stability:
                report_pts = 20
                feedback_parts.append("Report contains all required metrics [20/20]")
            elif has_density or has_ballast or has_stability:
                report_pts = 10
                feedback_parts.append("Report is missing some metrics [10/20]")
            else:
                report_pts = 5
                feedback_parts.append("Report exists but lacks specific engineering metrics [5/20]")
        except Exception as e:
            feedback_parts.append(f"Could not read report file: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report file not found [0/20]")
        
    score += report_pts

    # Final pass determination
    passed = score >= metadata.get('pass_threshold', 65)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }