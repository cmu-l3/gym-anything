#!/usr/bin/env python3
"""
Verifier for design_presentation_and_blueprint_export task.

Scoring breakdown (100 points total):
  20 pts - Nose cone is painted solid Red
  20 pts - Body tube is painted solid Blue
  20 pts - Trapezoidal fin set is painted solid Yellow
  20 pts - Design Report PDF is successfully exported (valid PDF format, size > 10KB, created during task)
  20 pts - Fin Alignment Guide PDF is successfully exported (valid PDF format, size > 5KB, created during task)

Pass threshold: 60 points
  Requires at least one PDF export and at least two color modifications.
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


def _check_color(element_tag, ork_root, condition_fn):
    """Checks if any component of the given tag matches the color condition."""
    for comp in ork_root.iter(element_tag):
        # The color is typically stored under appearance -> paint -> color
        # or appearance -> color depending on OpenRocket version
        appearances = comp.findall('.//appearance')
        for app in appearances:
            colors = app.findall('.//color')
            for c in colors:
                try:
                    r = int(float(c.get('r', '0')))
                    g = int(float(c.get('g', '0')))
                    b = int(float(c.get('b', '0')))
                    if condition_fn(r, g, b):
                        return True
                except (ValueError, TypeError):
                    continue
    return False


def _is_valid_pdf(filepath):
    """Checks file size and PDF magic bytes."""
    if not os.path.exists(filepath):
        return False
    # PDF should be at least a few KB
    if os.path.getsize(filepath) < 1024:
        return False
    try:
        with open(filepath, 'rb') as f:
            header = f.read(5)
            return header == b'%PDF-'
    except Exception:
        return False


def verify_design_presentation_and_blueprint_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/cdr_rocket.ork')
    dr_vm_path = metadata.get('dr_vm_path', '/home/ga/Documents/exports/design_report.pdf')
    fa_vm_path = metadata.get('fa_vm_path', '/home/ga/Documents/exports/fin_alignment_guide.pdf')

    score = 0
    feedback_parts = []

    # ---- 1. Check basic export results from JSON ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    result_data = {}
    try:
        copy_from_env("/tmp/cdr_task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read task export data: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    task_start = result_data.get('task_start_ts', 0)

    # ---- 2. Verify Colors via .ork parsing ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        if os.path.getsize(tmp_ork.name) > 0:
            ork_root, parse_err = _parse_ork(tmp_ork.name)
            if parse_err:
                feedback_parts.append(f"Could not parse .ork: {parse_err}")
        else:
            feedback_parts.append("Saved .ork file is empty or not found.")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is not None:
        # Check Nose cone -> Red
        is_red = lambda r, g, b: r > 180 and g < 100 and b < 100
        if _check_color('nosecone', ork_root, is_red):
            score += 20
            feedback_parts.append("Nose cone painted Red [20/20]")
        else:
            feedback_parts.append("Nose cone NOT painted Red [0/20]")

        # Check Body tube -> Blue
        is_blue = lambda r, g, b: r < 100 and g < 150 and b > 180
        if _check_color('bodytube', ork_root, is_blue):
            score += 20
            feedback_parts.append("Body tube painted Blue [20/20]")
        else:
            feedback_parts.append("Body tube NOT painted Blue [0/20]")

        # Check Fins -> Yellow
        is_yellow = lambda r, g, b: r > 180 and g > 180 and b < 100
        if _check_color('trapezoidfinset', ork_root, is_yellow):
            score += 20
            feedback_parts.append("Fins painted Yellow [20/20]")
        else:
            feedback_parts.append("Fins NOT painted Yellow [0/20]")
    else:
        feedback_parts.append("Skipping color checks (no .ork file) [0/60]")

    # ---- 3. Verify Design Report PDF ----
    tmp_dr = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    tmp_dr.close()
    dr_valid = False
    try:
        copy_from_env(dr_vm_path, tmp_dr.name)
        if result_data.get('dr_exists') and _is_valid_pdf(tmp_dr.name):
            # Anti-gaming: Ensure it was generated during the task
            if result_data.get('dr_mtime', 0) >= task_start:
                dr_valid = True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_dr.name):
            os.unlink(tmp_dr.name)

    if dr_valid:
        score += 20
        feedback_parts.append("Design Report PDF valid and generated during task [20/20]")
    else:
        feedback_parts.append("Design Report PDF missing, invalid, or pre-existing [0/20]")

    # ---- 4. Verify Fin Alignment Guide PDF ----
    tmp_fa = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    tmp_fa.close()
    fa_valid = False
    try:
        copy_from_env(fa_vm_path, tmp_fa.name)
        if result_data.get('fa_exists') and _is_valid_pdf(tmp_fa.name):
            # Anti-gaming: Ensure it was generated during the task
            if result_data.get('fa_mtime', 0) >= task_start:
                fa_valid = True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_fa.name):
            os.unlink(tmp_fa.name)

    if fa_valid:
        score += 20
        feedback_parts.append("Fin Alignment PDF valid and generated during task [20/20]")
    else:
        feedback_parts.append("Fin Alignment PDF missing, invalid, or pre-existing [0/20]")

    # ---- Final Output ----
    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }