#!/usr/bin/env python3
"""
Verifier for transonic_drag_optimization task.

Scoring breakdown (100 points total):
  35 pts - Fin cross-sections changed to 'airfoil' (all fin sets)
  35 pts - External components surface finish changed to 'polished'
  15 pts - At least one simulation has 'uptodate' status (re-run after modifications)
  15 pts - Aerodynamic optimization report exists with meaningful content

Pass threshold: 70 points
  Requires applying at least one set of the aerodynamic changes, re-running
  the simulation, and writing the report.
"""

import os
import re
import tempfile
import zipfile
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


def verify_transonic_drag_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    baseline_ork_path = metadata.get('baseline_ork_path', '/home/ga/Documents/rockets/transonic_rocket.ork')
    optimized_ork_path = metadata.get('optimized_ork_path', '/home/ga/Documents/rockets/transonic_rocket_optimized.ork')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/aerodynamic_report.txt')
    expected_crosssection = metadata.get('expected_crosssection', 'airfoil')
    expected_finish = metadata.get('expected_finish', 'polished')

    score = 0
    feedback_parts = []
    details = {}

    # Check if the agent saved the optimized file, otherwise fallback to the baseline file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    file_used = optimized_ork_path
    
    try:
        copy_from_env(optimized_ork_path, tmp_ork.name)
        if os.path.getsize(tmp_ork.name) < 100:
            # File might not exist or be empty, try baseline
            copy_from_env(baseline_ork_path, tmp_ork.name)
            file_used = baseline_ork_path
            feedback_parts.append("Optimized .ork not found; evaluating original file.")
        
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

    ext_tags = ['nosecone', 'bodytube', 'transition', 'trapezoidfinset', 'ellipticalfinset', 'freeformfinset']
    fin_tags = ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']

    # ---- Check 1: Fin cross-sections (35 points) ----
    total_fins = 0
    airfoil_fins = 0
    for tag in fin_tags:
        for elem in ork_root.iter(tag):
            total_fins += 1
            cs = elem.findtext('crosssection', '').strip().lower()
            if cs == expected_crosssection:
                airfoil_fins += 1
                
    details['total_fins'] = total_fins
    details['airfoil_fins'] = airfoil_fins

    if total_fins > 0:
        ratio = airfoil_fins / total_fins
        if ratio >= 0.9:
            score += 35
            feedback_parts.append(f"Fin cross-sections optimized: {airfoil_fins}/{total_fins} [35/35 pts]")
        elif ratio > 0:
            pts = int(35 * ratio)
            score += pts
            feedback_parts.append(f"Fin cross-sections partially optimized: {airfoil_fins}/{total_fins} [{pts}/35 pts]")
        else:
            feedback_parts.append(f"No fins changed to airfoil [0/35 pts]")
    else:
        feedback_parts.append("No fins found in model [0/35 pts]")

    # ---- Check 2: External components finish (35 points) ----
    total_ext = 0
    polished_ext = 0
    for tag in ext_tags:
        for elem in ork_root.iter(tag):
            total_ext += 1
            finish = elem.findtext('finish', '').strip().lower()
            if finish == expected_finish:
                polished_ext += 1
                
    details['total_ext_components'] = total_ext
    details['polished_components'] = polished_ext

    if total_ext > 0:
        ratio = polished_ext / total_ext
        if ratio >= 0.9:
            score += 35
            feedback_parts.append(f"Surface finishes optimized: {polished_ext}/{total_ext} [35/35 pts]")
        elif ratio > 0:
            pts = int(35 * ratio)
            score += pts
            feedback_parts.append(f"Surface finishes partially optimized: {polished_ext}/{total_ext} [{pts}/35 pts]")
        else:
            feedback_parts.append(f"No components changed to polished [0/35 pts]")
    else:
        feedback_parts.append("No external components found [0/35 pts]")

    # ---- Check 3: At least one uptodate simulation (15 points) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1

    details['uptodate_sims'] = uptodate_count
    if uptodate_count >= 1:
        score += 15
        feedback_parts.append(f"{uptodate_count} uptodate simulation(s) [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15 pts]")

    # ---- Check 4: Aerodynamic report exists (15 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 10:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            has_keywords = any(kw in content for kw in ['mach', 'velocity', 'm/s', 'speed'])
            has_comparison = any(kw in content for kw in ['baseline', 'before', 'after', 'optimized', 'polished', 'airfoil'])
            
            if has_keywords and has_comparison:
                score += 15
                feedback_parts.append("Report found with comparison metrics [15/15 pts]")
            elif has_keywords or has_comparison:
                score += 10
                feedback_parts.append("Report found but lacks comprehensive comparison [10/15 pts]")
            else:
                score += 5
                feedback_parts.append("Report found but content is generic [5/15 pts]")
        else:
            feedback_parts.append("Report file missing or empty [0/15 pts]")
    except Exception:
        feedback_parts.append("Report file missing [0/15 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    # ---- Final Result ----
    pass_threshold = metadata.get('pass_threshold', 70)
    passed = score >= pass_threshold
    
    # Must have actually optimized at least something to pass
    if passed and (airfoil_fins == 0 and polished_ext == 0):
        passed = False
        feedback_parts.append("FAILED: Met points threshold, but no aerodynamic modifications were made.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }