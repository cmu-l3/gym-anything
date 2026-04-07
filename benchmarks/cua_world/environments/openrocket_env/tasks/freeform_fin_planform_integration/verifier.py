#!/usr/bin/env python3
"""
Verifier for freeform_fin_planform_integration task.

Scoring breakdown (100 points total):
  10 pts - Old trapezoidal fins removed
  15 pts - Freeform fins added to the body tube
  35 pts - Shape coordinates match expected X,Y points (8.75 pts per point matched)
  15 pts - Fin properties correct (7.5 pts for thickness=3mm, 7.5 pts for fincount=3)
  15 pts - Simulation re-run (uptodate simulation exists)
  10 pts - Report generated with required keywords

Pass threshold: 70 points
"""

import os
import math
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


def _get_vertices_from_finpoints(finpoints_el):
    """Extract (x, y) tuples from a <finpoints> XML element."""
    vertices = []
    # OpenRocket usually stores them as <point x="0.0" y="0.0"/> or <vertex x="..." y="..."/>
    for child in finpoints_el:
        if 'x' in child.attrib and 'y' in child.attrib:
            try:
                x = float(child.attrib['x'])
                y = float(child.attrib['y'])
                vertices.append((x, y))
            except ValueError:
                pass
        else:
            # Fallback if they are nested elements
            x_el = child.find('x')
            y_el = child.find('y')
            if x_el is not None and y_el is not None:
                try:
                    x = float(x_el.text)
                    y = float(y_el.text)
                    vertices.append((x, y))
                except (ValueError, TypeError):
                    pass
    return vertices


def verify_freeform_fin_planform_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/freeform_rocket.ork')
    report_vm_path = metadata.get('report_path', '/home/ga/Documents/exports/fin_integration_report.txt')
    expected_coords = metadata.get('expected_coordinates_m', [[0.0, 0.0], [0.045, 0.05], [0.065, 0.05], [0.075, 0.0]])
    expected_fincount = metadata.get('expected_fin_count', 3)
    expected_thickness = metadata.get('expected_thickness_m', 0.003)
    tolerance = metadata.get('tolerance_m', 0.003)

    score = 0
    feedback_parts = []
    details = {}

    # ---- Check 1: Extract and Parse .ork file ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve expected freeform_rocket.ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) or "Failed to retrieve the saved freeform_rocket.ork file. Did you save to the requested path?"
        }

    # ---- Check 2: Old fins removed (10 pts) ----
    trap_fins = list(ork_root.iter('trapezoidfinset'))
    if len(trap_fins) == 0:
        score += 10
        feedback_parts.append("Trapezoidal fins removed [10/10 pts]")
    else:
        feedback_parts.append(f"Found {len(trap_fins)} trapezoidal fin set(s) still present [0/10 pts]")

    # ---- Check 3: Freeform fins added (15 pts) ----
    freeform_fins = list(ork_root.iter('freeformfinset'))
    if len(freeform_fins) > 0:
        score += 15
        feedback_parts.append("Freeform fins added [15/15 pts]")
        
        target_fin = freeform_fins[0] # Evaluate the first freeform fin set
        
        # ---- Check 4: Shape coordinates (35 pts) ----
        actual_vertices = []
        fp_elem = target_fin.find('finpoints')
        if fp_elem is not None:
            actual_vertices = _get_vertices_from_finpoints(fp_elem)
        
        matched_points = 0
        point_score = 0
        
        for ex_x, ex_y in expected_coords:
            # Find closest actual vertex
            min_dist = float('inf')
            for ac_x, ac_y in actual_vertices:
                dist = math.sqrt((ex_x - ac_x)**2 + (ex_y - ac_y)**2)
                min_dist = min(min_dist, dist)
            
            if min_dist <= tolerance:
                matched_points += 1
                point_score += 8.75
                
        score += point_score
        details['matched_vertices'] = matched_points
        if matched_points == 4:
            feedback_parts.append("All shape coordinates match exactly [35/35 pts]")
        else:
            feedback_parts.append(f"Shape coordinates: matched {matched_points}/4 points [{point_score:.1f}/35 pts]")

        # ---- Check 5: Fin Properties (15 pts) ----
        props_score = 0
        
        try:
            fc = int(target_fin.findtext('fincount', '0'))
            if fc == expected_fincount:
                props_score += 7.5
                feedback_parts.append("Fin count is 3 [7.5/7.5 pts]")
            else:
                feedback_parts.append(f"Fin count is {fc} (expected 3) [0/7.5 pts]")
        except (ValueError, TypeError):
            feedback_parts.append("Fin count missing or invalid [0/7.5 pts]")
            
        try:
            th = float(target_fin.findtext('thickness', '0'))
            if abs(th - expected_thickness) < 0.0005:
                props_score += 7.5
                feedback_parts.append("Fin thickness is 3.0mm [7.5/7.5 pts]")
            else:
                feedback_parts.append(f"Fin thickness is {th*1000:.1f}mm (expected 3.0mm) [0/7.5 pts]")
        except (ValueError, TypeError):
            feedback_parts.append("Fin thickness missing or invalid [0/7.5 pts]")
            
        score += props_score

    else:
        feedback_parts.append("No freeform fin set found [0/15 pts]")
        # Skip fin coordinate and property checks since no freeform fins exist

    # ---- Check 6: Simulation uptodate (15 pts) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1

    if uptodate_count > 0:
        score += 15
        feedback_parts.append(f"Found {uptodate_count} uptodate simulation(s) [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/15 pts]")

    # ---- Check 7: Report Generation (10 pts) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r') as f:
            content = f.read().lower()
            
        has_freeform = "freeform" in content
        has_thickness = "3" in content or "3.0" in content
        has_metrics = "altitude" in content or "apogee" in content or "stability" in content
        
        report_score = 0
        if has_freeform and has_thickness and has_metrics:
            report_score = 10
            feedback_parts.append("Report generated with expected metrics [10/10 pts]")
        elif len(content.strip()) > 10:
            report_score = 5
            feedback_parts.append("Report generated but missing some required keywords [5/10 pts]")
        else:
            feedback_parts.append("Report file is empty or insufficient [0/10 pts]")
            
        score += report_score
    except Exception as e:
        feedback_parts.append("Report file not found [0/10 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    passed = score >= metadata.get('pass_threshold', 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }