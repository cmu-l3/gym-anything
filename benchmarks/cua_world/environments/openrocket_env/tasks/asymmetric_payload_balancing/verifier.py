#!/usr/bin/env python3
"""
Verifier for asymmetric_payload_balancing task.

Scoring breakdown (100 points total):
  15 pts - Mass component named 'Counterweight' added to rocket
  20 pts - Radial direction/angle is set exactly opposite the camera (~180 deg)
  15 pts - Radial position placed inside the body tube (<= 19mm)
  25 pts - Exact mathematical balance achieved (mass * position == 0.0015 kg*m ± 5%)
  15 pts - Flight simulation run/updated after edits
  10 pts - Brief balancing report created containing values

Pass threshold: 65 points AND key structural changes (180deg angle + valid mathematical balance)
"""

import os
import math
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import json

def _parse_ork(local_path):
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

def verify_asymmetric_payload_balancing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_path = metadata.get('balanced_ork_path', '/home/ga/Documents/rockets/balanced_rocket.ork')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/balance_report.txt')
    expected_moment = metadata.get('expected_moment', 0.0015)

    score = 0
    feedback_parts = []
    
    # 1. Parse ORK file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    
    ork_root = None
    try:
        copy_from_env(ork_path, tmp_ork.name)
        if os.path.exists(tmp_ork.name) and os.path.getsize(tmp_ork.name) > 0:
            ork_root, parse_err = _parse_ork(tmp_ork.name)
            if parse_err:
                feedback_parts.append(f"Could not parse .ork: {parse_err}")
        else:
            feedback_parts.append("balanced_rocket.ork not found or empty")
    except Exception as e:
        feedback_parts.append(f"Error copying .ork: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if not ork_root:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts) or "balanced_rocket.ork not found"}

    # 2. Find the Counterweight MassComponent
    cw = None
    for mc in ork_root.iter('masscomponent'):
        name = mc.findtext('name', '').lower()
        if 'counterweight' in name:
            cw = mc
            break
            
    if cw is None:
        # Fallback: look for a mass component with ~180 degree angle if naming got messed up
        for mc in ork_root.iter('masscomponent'):
            name = mc.findtext('name', '').lower()
            if 'camera' in name:
                continue
            rad_dir = float(mc.findtext('radialdirection', '0'))
            if abs(abs(rad_dir) - math.pi) < 0.2:
                cw = mc
                break

    rdir = 0.0
    moment = 0.0
    if cw is not None:
        score += 15
        feedback_parts.append("Counterweight found [15/15 pts]")
        
        try:
            mass = float(cw.findtext('mass', '0'))
        except:
            mass = 0.0
            
        try:
            rpos = float(cw.findtext('radialposition', '0'))
        except:
            rpos = 0.0
            
        try:
            rdir = float(cw.findtext('radialdirection', '0'))
        except:
            rdir = 0.0

        # Check angle (~180 deg). OpenRocket stores this in radians.
        if abs(abs(rdir) - math.pi) <= 0.1:
            score += 20
            feedback_parts.append("Counterweight angle correct (~180 deg) [20/20 pts]")
        else:
            feedback_parts.append(f"Counterweight angle incorrect ({rdir:.3f} rad, expected ~3.141) [0/20 pts]")

        # Check internal fit
        if 0 < rpos <= 0.0195:
            score += 15
            feedback_parts.append(f"Counterweight internal fit correct (r={rpos*1000:.1f}mm <= 19mm) [15/15 pts]")
        elif rpos > 0.0195:
            feedback_parts.append(f"Counterweight placed outside body tube (r={rpos*1000:.1f}mm > 19mm) [0/15 pts]")
        else:
            feedback_parts.append("Counterweight radial position is 0 [0/15 pts]")

        # Check exact mathematical moment balance (5% tolerance)
        moment = mass * rpos
        if abs(moment - expected_moment) <= 0.000075:
            score += 25
            feedback_parts.append(f"Mathematical balance correct (moment={moment:.5f}) [25/25 pts]")
        elif abs(moment - expected_moment) <= 0.00030:
            score += 10
            feedback_parts.append(f"Mathematical balance approximate (moment={moment:.5f}, expected {expected_moment:.4f}) [10/25 pts]")
        else:
            feedback_parts.append(f"Mathematical balance incorrect (moment={moment:.5f}, expected {expected_moment:.4f}) [0/25 pts]")

    else:
        feedback_parts.append("Counterweight component not found [0/75 pts]")

    # 3. Check simulations
    sims = ork_root.find('simulations')
    uptodate_count = 0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
    
    if uptodate_count > 0:
        score += 15
        feedback_parts.append("Simulation re-run successfully [15/15 pts]")
    else:
        feedback_parts.append("No uptodate simulations [0/15 pts]")

    # 4. Check report existence and content
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r') as f:
                content = f.read().lower()
            if 'mass' in content and ('180' in content or '3.14' in content or 'angle' in content or 'position' in content):
                score += 10
                feedback_parts.append("Report found with meaningful content [10/10 pts]")
            else:
                score += 5
                feedback_parts.append("Report found but missing details [5/10 pts]")
        else:
            feedback_parts.append("Report not found [0/10 pts]")
    except Exception:
        feedback_parts.append("Report not found [0/10 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    # 5. Determine passing
    passed = score >= 65 and cw is not None and abs(abs(rdir) - math.pi) <= 0.1 and abs(moment - expected_moment) <= 0.000075
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }