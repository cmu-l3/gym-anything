#!/usr/bin/env python3
"""
Verifier for high_wind_recovery_overhaul task.

Scoring breakdown (100 points total):
  20 pts - Wind speed configured to 12.0 m/s in simulation
  30 pts - Parachute deployment event is ALTITUDE at ~50m
  20 pts - Streamer component added
  15 pts - At least one simulation is uptodate
  15 pts - Analysis report exists with numbers

Pass threshold: 70 points
"""

import os
import re
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Safely unzips and parses the OpenRocket .ork file"""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except Exception as e:
        return None, str(e)

def verify_high_wind_recovery_overhaul(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/simple_model_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/wind_mitigation_report.txt')

    score = 0
    feedback_parts = []
    
    # Extract ORK file for parsing
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
    except Exception as e:
        pass
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to parse .ork file"
        }

    # Criterion 1: Wind speed set to 12.0 m/s (20 points)
    wind_found = False
    sims = ork_root.find('simulations')
    if sims is not None:
        for sim in sims.findall('simulation'):
            conds = sim.find('conditions')
            if conds is not None:
                ws = conds.findtext('windspeed', '')
                try:
                    if abs(float(ws) - 12.0) < 0.5:
                        wind_found = True
                        break
                except:
                    pass
    if wind_found:
        score += 20
        feedback_parts.append("Wind speed set to 12.0 m/s [20/20 pts]")
    else:
        feedback_parts.append("Wind speed not 12.0 m/s [0/20 pts]")

    # Criterion 2: Parachute set to 50m altitude (30 points)
    para_ok = False
    for para in ork_root.iter('parachute'):
        de = para.findtext('deployevent', '').upper()
        da = para.findtext('deployaltitude', '0')
        try:
            if de == 'ALTITUDE' and abs(float(da) - 50.0) < 5.0:
                para_ok = True
                break
        except:
            pass
    
    if para_ok:
        score += 30
        feedback_parts.append("Parachute set to deploy at 50m altitude [30/30 pts]")
    else:
        feedback_parts.append("Parachute not set to deploy at 50m altitude [0/30 pts]")

    # Criterion 3: Streamer added (20 points)
    streamer_found = False
    for streamer in ork_root.iter('streamer'):
        streamer_found = True
        break
    
    if streamer_found:
        score += 20
        feedback_parts.append("Streamer component found [20/20 pts]")
    else:
        feedback_parts.append("Streamer component not found [0/20 pts]")

    # Criterion 4: Simulation uptodate (15 points)
    uptodate = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate = True
                break
    
    if uptodate:
        score += 15
        feedback_parts.append("Simulation is up-to-date [15/15 pts]")
    else:
        feedback_parts.append("Simulation is not up-to-date [0/15 pts]")

    # Criterion 5: Report exists with numeric metrics (15 points)
    report_ok = False
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 10:
            with open(tmp_report.name, 'r') as f:
                content = f.read()
                # Confirm there are numbers present in the report
                if re.search(r'\d+', content):
                    report_ok = True
    except:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    if report_ok:
        score += 15
        feedback_parts.append("Analysis report is valid [15/15 pts]")
    else:
        feedback_parts.append("Analysis report missing or lacks metrics [0/15 pts]")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }