#!/usr/bin/env python3
"""
Verifier for classic_rocket_upscale task.

Scoring breakdown (100 points total):
  25 pts - Airframe Scaled (Body tube outer radius between 0.024m and 0.026m)
  15 pts - Nose Cone Scaled (Nose cone length between 0.24m and 0.27m)
  25 pts - Motor Mount Standardized (Motor mount inner diameter == 38mm ± 1mm)
  20 pts - Simulation Run (At least one uptodate sim with motor loaded/alt > 10m)
  15 pts - Upscale Report (Report exists with required metrics and keywords)

Pass threshold: 65 points
  Do-nothing max: 0
"""

import os
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


def verify_classic_rocket_upscale(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/upscaled_2x.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/upscale_report.txt')

    score = 0
    feedback_parts = []
    details = {}

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

    # ---- Check 1: Airframe Scaled (25 pts) ----
    bt_radius = 0.0
    for bt in ork_root.iter('bodytube'):
        try:
            r = float(bt.findtext('radius', '0'))
            bt_radius = max(bt_radius, r)
        except (ValueError, TypeError):
            pass

    details['bodytube_radius'] = bt_radius
    if 0.024 <= bt_radius <= 0.026:
        score += 25
        feedback_parts.append(f"Airframe scaled (Radius {bt_radius*1000:.1f}mm) [25/25 pts]")
    elif bt_radius > 0:
        feedback_parts.append(f"Airframe NOT scaled correctly (Radius {bt_radius*1000:.1f}mm) [0/25 pts]")
    else:
        feedback_parts.append("No body tube found [0/25 pts]")

    # ---- Check 2: Nose Cone Scaled (15 pts) ----
    nc_length = 0.0
    for nc in ork_root.iter('nosecone'):
        try:
            l = float(nc.findtext('length', '0'))
            nc_length = max(nc_length, l)
        except (ValueError, TypeError):
            pass

    details['nosecone_length'] = nc_length
    if 0.24 <= nc_length <= 0.27:
        score += 15
        feedback_parts.append(f"Nose cone scaled (Length {nc_length*1000:.1f}mm) [15/15 pts]")
    elif nc_length > 0:
        feedback_parts.append(f"Nose cone NOT scaled correctly (Length {nc_length*1000:.1f}mm) [0/15 pts]")
    else:
        feedback_parts.append("No nose cone found [0/15 pts]")

    # ---- Check 3: Motor Mount Standardized (25 pts) ----
    mm_inner_diameter = 0.0
    for comp in ork_root.iter():
        if comp.find('motormount') is not None:
            try:
                r = float(comp.findtext('radius', '0'))
                t = float(comp.findtext('thickness', '0'))
                id_val = (r - t) * 2
                if id_val > mm_inner_diameter:
                    mm_inner_diameter = id_val
            except (ValueError, TypeError):
                pass

    details['motor_mount_id'] = mm_inner_diameter
    if 0.037 <= mm_inner_diameter <= 0.039:
        score += 25
        feedback_parts.append(f"Motor mount standardized ({mm_inner_diameter*1000:.1f}mm ID) [25/25 pts]")
    elif mm_inner_diameter > 0:
        feedback_parts.append(f"Motor mount NOT standardized ({mm_inner_diameter*1000:.1f}mm ID) [0/25 pts]")
    else:
        feedback_parts.append("No motor mount found [0/25 pts]")

    # ---- Check 4: Simulation Run (20 pts) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        max_alt = float(fd.get('maxaltitude', '0'))
                        if max_alt > 10.0:
                            uptodate_count += 1
                    except (ValueError, TypeError):
                        pass

    details['valid_simulations'] = uptodate_count
    if uptodate_count > 0:
        score += 20
        feedback_parts.append(f"Simulation uptodate and motor loaded [20/20 pts]")
    else:
        feedback_parts.append("No valid simulation run [0/20 pts]")

    # ---- Check 5: Upscale Report (15 pts) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_pts = 0
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 10:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                # Check for metrics
                has_38mm = "38" in content
                has_len = "99" in content or "0.99" in content
                has_diam = "49" in content or "0.049" in content or "50" in content
                if has_38mm or has_len or has_diam:
                    report_pts = 15
                else:
                    report_pts = 5
            score += report_pts
            feedback_parts.append(f"Report found with metrics [{report_pts}/15 pts]")
        else:
            feedback_parts.append("Report missing or empty [0/15 pts]")
    except Exception:
        feedback_parts.append("Report missing [0/15 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }