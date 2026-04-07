#!/usr/bin/env python3
"""
Verifier for material_upgrade_for_hpr task.

Scoring breakdown (100 points total):
  20 pts - Body tube upgraded to Fiberglass (density >= 1100 kg/m^3)
  20 pts - Nose cone upgraded to Fiberglass (density >= 1100 kg/m^3)
  20 pts - Fins upgraded to Plywood/Birch (density >= 500 kg/m^3)
  15 pts - At least one simulation has 'uptodate' status (re-run after mass increase)
  10 pts - Design file properly saved to expected path
  15 pts - Report exists, >= 200 chars, discusses materials and mass/performance

Pass threshold: 60 points
"""

import os
import json
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

def get_max_density_for_tag(root, tag_name):
    """Finds the maximum material density applied to elements matching tag_name."""
    max_density = 0.0
    for elem in root.iter(tag_name):
        mat = elem.find('material')
        if mat is not None:
            try:
                d = float(mat.get('density', '0'))
                max_density = max(max_density, d)
            except (ValueError, TypeError):
                pass
    return max_density

def verify_material_upgrade_for_hpr(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_fiberglass = metadata.get('min_fiberglass_density', 1100)
    min_plywood = metadata.get('min_plywood_density', 500)
    pass_threshold = metadata.get('pass_threshold', 60)

    score = 0
    feedback_parts = []
    
    # 1. Check Result JSON from Export
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/material_upgrade_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result_data = json.load(f)
    except Exception:
        result_data = {"ork_exists": False, "report_exists": False, "report_size": 0}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    ork_exists = result_data.get('ork_exists', False)
    report_exists = result_data.get('report_exists', False)
    report_size = result_data.get('report_size', 0)

    if not ork_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Upgraded .ork file not found. Task requires saving to upgraded_rocket.ork."
        }
    else:
        score += 10
        feedback_parts.append("File saved successfully [10/10 pts]")

    # 2. Parse the saved .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env("/tmp/agent_upgraded_rocket.ork", tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse saved .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Check Material Densities
    bt_density = get_max_density_for_tag(ork_root, 'bodytube')
    if bt_density >= min_fiberglass:
        score += 20
        feedback_parts.append(f"Body tube density {bt_density} >= {min_fiberglass} [20/20 pts]")
    else:
        feedback_parts.append(f"Body tube density {bt_density} < {min_fiberglass} [0/20 pts]")

    nc_density = get_max_density_for_tag(ork_root, 'nosecone')
    if nc_density >= min_fiberglass:
        score += 20
        feedback_parts.append(f"Nose cone density {nc_density} >= {min_fiberglass} [20/20 pts]")
    else:
        feedback_parts.append(f"Nose cone density {nc_density} < {min_fiberglass} [0/20 pts]")

    # Fins could be trapezoidal, elliptical, etc.
    fin_density = max(
        get_max_density_for_tag(ork_root, 'trapezoidfinset'),
        get_max_density_for_tag(ork_root, 'ellipticalfinset'),
        get_max_density_for_tag(ork_root, 'freeformfinset')
    )
    if fin_density >= min_plywood:
        score += 20
        feedback_parts.append(f"Fin density {fin_density} >= {min_plywood} [20/20 pts]")
    else:
        feedback_parts.append(f"Fin density {fin_density} < {min_plywood} [0/20 pts]")

    # 4. Check for updated simulations
    sims = ork_root.find('simulations')
    has_uptodate = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                has_uptodate = True
                break

    if has_uptodate:
        score += 15
        feedback_parts.append("Uptodate simulation found [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15 pts]")

    # 5. Check Report Content
    if report_exists and report_size >= 200:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env("/tmp/agent_material_report.txt", tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
            
            has_material_keywords = any(k in content for k in ['fiberglass', 'plywood', 'birch'])
            has_metric_keywords = any(k in content for k in ['mass', 'weight', 'g', 'kg', 'altitude', 'apogee', 'performance'])
            
            if has_material_keywords and has_metric_keywords:
                score += 15
                feedback_parts.append("Report is valid and contains required details [15/15 pts]")
            else:
                score += 5
                feedback_parts.append("Report missing required material/metric discussion [5/15 pts]")
        except Exception as e:
            feedback_parts.append(f"Could not read report: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    elif report_exists:
        feedback_parts.append(f"Report is too short ({report_size} chars) [0/15 pts]")
    else:
        feedback_parts.append("Report not found [0/15 pts]")

    # Determine Pass/Fail
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }