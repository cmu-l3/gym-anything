#!/usr/bin/env python3
"""
Verifier for motor_adapter_downsize_retrofit task.

Scoring breakdown (100 points total):
  15 pts - Original structure intact (OD >= 38mm found in body tubes)
  30 pts - 29mm adapter tube correctly sized (Inner tube ID 28-31mm)
  15 pts - Adapter has 'motormount' property enabled
  10 pts - Centering rings added for structure
  20 pts - Uptodate simulation demonstrating stable flight
  10 pts - Trade study report written with required context

Pass threshold: 70 points
"""

import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except Exception as e:
        return None, f"Failed to parse .ork: {e}"

def verify_motor_adapter_downsize_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('output_ork_path', '/home/ga/Documents/rockets/janus_29mm_adapter.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/adapter_report.txt')
    
    score = 0
    feedback_parts = []
    
    # Check JSON result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    result = {}
    try:
        copy_from_env('/tmp/task_result.json', tmp_json.name)
        import json
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)
            
    if not result.get('ork_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Modified rocket design was not saved to expected path"
        }

    # Retrieve ORK
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

    # 1. Original structure intact (15 pts)
    original_intact = False
    for bt in ork_root.iter('bodytube'):
        try:
            rad = float(bt.findtext('radius', '0'))
            if rad >= 0.0185:  # ~38mm OD (19mm radius)
                original_intact = True
                break
        except Exception:
            pass

    if original_intact:
        score += 15
        feedback_parts.append("Main airframe intact [15/15 pts]")
    else:
        feedback_parts.append("Main airframe missing or shrunk! [0/15 pts]")

    # 2. 29mm Adapter Tube (30 pts) and 3. Adapter is Motor Mount (15 pts)
    found_adapter = False
    adapter_is_mm = False
    for inner in ork_root.iter('innertube'):
        try:
            r = float(inner.findtext('radius', '0'))
            t = float(inner.findtext('thickness', '0'))
            inner_diam = 2 * (r - t)
            
            # Check if inner diameter is around 29mm
            if 0.028 <= inner_diam <= 0.031:
                found_adapter = True
                # Check if it has motormount child
                mm = inner.find('motormount')
                if mm is not None:
                    adapter_is_mm = True
                break
        except Exception:
            pass

    if found_adapter:
        score += 30
        feedback_parts.append("29mm adapter tube found [30/30 pts]")
        if adapter_is_mm:
            score += 15
            feedback_parts.append("Adapter has motor mount enabled [15/15 pts]")
        else:
            feedback_parts.append("Adapter is NOT set as a motor mount [0/15 pts]")
    else:
        feedback_parts.append("No 29mm inner tube adapter found [0/30 pts]")

    # 4. Centering rings added (10 pts)
    ring_count = len(list(ork_root.iter('centeringring')))
    if ring_count >= 1:
        score += 10
        feedback_parts.append(f"Centering rings found ({ring_count}) [10/10 pts]")
    else:
        feedback_parts.append("No centering rings found [0/10 pts]")

    # 5. Simulation Up-to-date (20 pts)
    uptodate = False
    sims = ork_root.find('simulations')
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        if alt > 10:  # Validate it actually flew
                            uptodate = True
                            break
                    except Exception:
                        pass

    if uptodate:
        score += 20
        feedback_parts.append("Successful up-to-date simulation found [20/20 pts]")
    else:
        feedback_parts.append("No successful up-to-date simulations [0/20 pts]")

    # 6. Report Created (10 pts)
    report_pts = 0
    if result.get('report_exists', False) and result.get('report_size', 0) > 10:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(report_vm_path, tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8') as f:
                content = f.read().lower()
                if ('29mm' in content or 'adapter' in content) and ('apogee' in content or 'altitude' in content):
                    report_pts = 10
                    feedback_parts.append("Report created with required keywords [10/10 pts]")
                else:
                    report_pts = 5
                    feedback_parts.append("Report created but missing keywords [5/10 pts]")
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("Report missing or empty [0/10 pts]")
        
    score += report_pts
    
    passed = score >= metadata.get('pass_threshold', 70) and original_intact and found_adapter
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }