#!/usr/bin/env python3
"""
Verifier for the airfoiled_fin_fabrication_export task.

Verification Strategy:
1. ORK File modifications: Parse XML to check if <thickness> is 0.00635 m and <crosssection> is 'airfoil'.
2. Simulation execution: Ensure ORK XML has a <simulation> element with status 'uptodate'.
3. 3D Model: Copy the OBJ file, check if it's not empty and contains standard Wavefront definitions ('v ', 'f ').
4. PDF Export: Check magic bytes ('%PDF') for both Design Report and Fin Templates.
5. Anti-gaming: All files must be created/modified *after* the task start timestamp.
"""

import json
import os
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
        # Fallback if it was saved uncompressed for some reason
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_airfoiled_fin_fabrication_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_thickness = metadata.get('expected_thickness_m', 0.00635)
    thickness_tolerance = metadata.get('expected_thickness_tolerance', 0.0005)
    expected_crosssection = metadata.get('expected_crosssection', 'airfoil')

    score = 0
    feedback_parts = []

    # 1. Get the base JSON status
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files_status = result.get('files', {})
    ork_status = files_status.get('ork_file', {})
    obj_status = files_status.get('obj_file', {})
    design_status = files_status.get('design_report', {})
    templates_status = files_status.get('fin_templates', {})

    # ---------------------------------------------------------
    # Criterion 1 & 2: Evaluate ORK file (Fin thickness, Airfoil, Simulation)
    # ---------------------------------------------------------
    if ork_status.get('exists') and ork_status.get('created_during_task'):
        tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
        try:
            copy_from_env(metadata.get('output_ork', '/home/ga/Documents/rockets/upgraded_fins.ork'), tmp_ork.name)
            ork_root, parse_err = _parse_ork(tmp_ork.name)
            
            if ork_root is not None:
                # Find the maximum thickness and presence of airfoil among all finsets
                max_thickness = 0.0
                has_airfoil = False
                
                for finset_tag in ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']:
                    for fin in ork_root.iter(finset_tag):
                        t_str = fin.findtext('thickness', '0')
                        try:
                            t = float(t_str)
                            max_thickness = max(max_thickness, t)
                        except ValueError:
                            pass
                        
                        cs = fin.findtext('crosssection', '').strip().lower()
                        if cs == expected_crosssection:
                            has_airfoil = True

                # Check Thickness (20 pts)
                if abs(max_thickness - expected_thickness) <= thickness_tolerance:
                    score += 20
                    feedback_parts.append("Fin thickness updated correctly")
                else:
                    feedback_parts.append(f"Fin thickness incorrect: {max_thickness*1000:.2f}mm")

                # Check Airfoil (20 pts)
                if has_airfoil:
                    score += 20
                    feedback_parts.append("Airfoil cross-section applied")
                else:
                    feedback_parts.append("Airfoil cross-section not found")

                # Check Simulation (10 pts)
                simulations = ork_root.find('simulations')
                has_uptodate = False
                if simulations is not None:
                    for sim in simulations.findall('simulation'):
                        if sim.get('status') == 'uptodate':
                            has_uptodate = True
                            break
                if has_uptodate:
                    score += 10
                    feedback_parts.append("Uptodate simulation found")
                else:
                    feedback_parts.append("No uptodate simulation in saved design")
            else:
                feedback_parts.append(f"Failed to parse ORK: {parse_err}")
        except Exception as e:
            feedback_parts.append(f"Error fetching ORK: {e}")
        finally:
            if os.path.exists(tmp_ork.name):
                os.unlink(tmp_ork.name)
    else:
        feedback_parts.append("Upgraded ORK file not found or pre-dates task")

    # ---------------------------------------------------------
    # Criterion 3: 3D Model Export (15 pts)
    # ---------------------------------------------------------
    if obj_status.get('exists') and obj_status.get('created_during_task') and obj_status.get('size', 0) > 100:
        tmp_obj = tempfile.NamedTemporaryFile(delete=False, suffix='.obj')
        try:
            copy_from_env(metadata.get('output_obj', '/home/ga/Documents/exports/rocket_3d.obj'), tmp_obj.name)
            
            with open(tmp_obj.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read(4096) # Check first chunk for efficiency
                if 'v ' in content and 'f ' in content:
                    score += 15
                    feedback_parts.append("3D OBJ exported successfully")
                else:
                    feedback_parts.append("Exported OBJ lacks geometry (no 'v' or 'f' lines)")
        except Exception as e:
            feedback_parts.append(f"Failed to verify OBJ: {e}")
        finally:
            if os.path.exists(tmp_obj.name):
                os.unlink(tmp_obj.name)
    else:
        feedback_parts.append("3D OBJ missing or invalid")

    # ---------------------------------------------------------
    # Criterion 4: Design Report PDF (15 pts)
    # ---------------------------------------------------------
    if design_status.get('exists') and design_status.get('created_during_task') and design_status.get('size', 0) > 1024:
        tmp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            copy_from_env(metadata.get('output_design_pdf', '/home/ga/Documents/exports/design_report.pdf'), tmp_pdf.name)
            with open(tmp_pdf.name, 'rb') as f:
                header = f.read(4)
                if header == b'%PDF':
                    score += 15
                    feedback_parts.append("Design Report PDF exported successfully")
                else:
                    feedback_parts.append("Design Report is not a valid PDF")
        except Exception as e:
            feedback_parts.append(f"Failed to verify Design Report PDF: {e}")
        finally:
            if os.path.exists(tmp_pdf.name):
                os.unlink(tmp_pdf.name)
    else:
        feedback_parts.append("Design Report PDF missing or invalid")

    # ---------------------------------------------------------
    # Criterion 5: Fin Templates PDF (20 pts)
    # ---------------------------------------------------------
    if templates_status.get('exists') and templates_status.get('created_during_task') and templates_status.get('size', 0) > 1024:
        tmp_pdf2 = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            copy_from_env(metadata.get('output_templates_pdf', '/home/ga/Documents/exports/fin_templates.pdf'), tmp_pdf2.name)
            with open(tmp_pdf2.name, 'rb') as f:
                header = f.read(4)
                if header == b'%PDF':
                    score += 20
                    feedback_parts.append("Fin Templates PDF exported successfully")
                else:
                    feedback_parts.append("Fin Templates is not a valid PDF")
        except Exception as e:
            feedback_parts.append(f"Failed to verify Fin Templates PDF: {e}")
        finally:
            if os.path.exists(tmp_pdf2.name):
                os.unlink(tmp_pdf2.name)
    else:
        feedback_parts.append("Fin Templates PDF missing or invalid")

    # Final logic
    threshold = metadata.get('pass_threshold', 75)
    passed = score >= threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }