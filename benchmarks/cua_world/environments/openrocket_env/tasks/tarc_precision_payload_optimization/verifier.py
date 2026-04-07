#!/usr/bin/env python3
"""
Verifier for tarc_precision_payload_optimization task.
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Safely parse .ork file which is a ZIP containing rocket.ork XML."""
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
            return None, f"Could not parse as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_tarc_precision_payload_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/tarc_competition_design.ork')

    score = 0
    feedback_parts = []

    # 1. Copy result JSON
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    result = {}
    try:
        copy_from_env("/tmp/tarc_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read result JSON: {e}")
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    if not result.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Saved rocket design not found."
        }

    if not result.get('file_created_during_task', False):
        feedback_parts.append("Warning: Design file does not appear to have been modified/saved during task window.")

    # 2. Copy .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Parse error: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Failed to copy .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "Cannot parse .ork file"}

    # Evaluate criteria
    # 1. Airframe Upscaled (15 pts)
    max_bt_radius = 0.0
    for bt in ork_root.iter('bodytube'):
        try:
            r = float(bt.findtext('radius', '0'))
            if r > max_bt_radius:
                max_bt_radius = r
        except Exception:
            pass

    if max_bt_radius >= 0.0225:
        score += 15
        feedback_parts.append(f"Airframe upscaled (radius {max_bt_radius*1000:.1f}mm) [15/15 pts]")
    elif max_bt_radius > 0.015:
        score += 5
        feedback_parts.append(f"Airframe partially upscaled (radius {max_bt_radius*1000:.1f}mm) [5/15 pts]")
    else:
        feedback_parts.append(f"Airframe not upscaled enough (radius {max_bt_radius*1000:.1f}mm) [0/15 pts]")

    # 2. Payload Integrated (20 pts) & 3. Tuning Ballast (10 pts)
    egg_found = False
    alt_found = False
    ballast_found = False
    for mc in ork_root.iter('masscomponent'):
        name = mc.findtext('name', '').lower()
        try:
            mass = float(mc.findtext('mass', '0'))
        except Exception:
            mass = 0.0
        
        if 'egg' in name and 0.06 < mass < 0.07:
            egg_found = True
        if 'altimeter' in name and 0.01 < mass < 0.02:
            alt_found = True
        if 'ballast' in name:
            ballast_found = True

    payload_pts = 0
    if egg_found: payload_pts += 10
    if alt_found: payload_pts += 10
    score += payload_pts
    if payload_pts == 20:
        feedback_parts.append("Egg & Altimeter integrated [20/20 pts]")
    else:
        feedback_parts.append(f"Payload incomplete (Egg:{egg_found}, Alt:{alt_found}) [{payload_pts}/20 pts]")

    if ballast_found:
        score += 10
        feedback_parts.append("Tuning ballast found [10/10 pts]")
    else:
        feedback_parts.append("Tuning ballast not found [0/10 pts]")

    # 4 & 5. Flight Data: Precision Apogee (15 pts) and Safe Descent (20 pts)
    sims = ork_root.find('simulations')
    best_apogee = -1
    best_ghv = 999.0
    uptodate = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate = True
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        apogee = float(fd.get('maxaltitude', '0'))
                        ghv = float(fd.get('groundhitvelocity', '999'))
                        # Log closest apogee to target
                        if best_apogee < 0 or abs(apogee - 259.0) < abs(best_apogee - 259.0):
                            best_apogee = apogee
                            best_ghv = ghv
                    except Exception:
                        pass
    
    if not uptodate:
        feedback_parts.append("No uptodate simulations [0/35 pts]")
    else:
        # Precision Altitude (15 pts)
        alt_err = abs(best_apogee - 259.0)
        if best_apogee > 0:
            if alt_err <= 3.0:
                score += 15
                feedback_parts.append(f"Apogee {best_apogee:.1f}m is within ±3m [15/15 pts]")
            elif alt_err <= 10.0:
                score += 10
                feedback_parts.append(f"Apogee {best_apogee:.1f}m is within ±10m [10/15 pts]")
            elif alt_err <= 50.0:
                score += 5
                feedback_parts.append(f"Apogee {best_apogee:.1f}m is within ±50m [5/15 pts]")
            else:
                feedback_parts.append(f"Apogee {best_apogee:.1f}m is far from target [0/15 pts]")
        else:
            feedback_parts.append("No valid apogee found [0/15 pts]")
        
        # Safe Descent (20 pts)
        if best_ghv <= 4.5:
            score += 20
            feedback_parts.append(f"Safe descent {best_ghv:.1f} m/s <= 4.5 m/s [20/20 pts]")
        elif best_ghv <= 6.5:
            score += 10
            feedback_parts.append(f"Marginal descent {best_ghv:.1f} m/s [10/20 pts]")
        else:
            feedback_parts.append(f"Unsafe descent {best_ghv:.1f} m/s [0/20 pts]")

    # 6. Engineering Notebook (10 pts)
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size', 0)
    if report_exists and report_size > 20:
        score += 10
        feedback_parts.append("Engineering notebook is complete [10/10 pts]")
    elif report_exists:
        score += 5
        feedback_parts.append("Engineering notebook is empty/too short [5/10 pts]")
    else:
        feedback_parts.append("Engineering notebook not found [0/10 pts]")

    # 7. VLM Verification (10 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = '''You are analyzing screenshots from an OpenRocket session.
Did the agent actively use the OpenRocket UI to modify a rocket design (e.g., changing dimensions, adding mass components, running simulations)?
Respond in JSON format with a single boolean field:
{
    "workflow_completed": true/false
}'''
                vlm_result = query_vlm(images=images, prompt=prompt)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("workflow_completed", False):
                        vlm_score = 10
                        feedback_parts.append("VLM confirmed UI interaction [10/10 pts]")
                    else:
                        feedback_parts.append("VLM did not detect UI interaction [0/10 pts]")
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")
            
    score += vlm_score

    passed = (score >= 65)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }