#!/usr/bin/env python3
"""
Verifier for fin planform redesign task.
Checks: fin geometry changes, simulation status, flight data, and report.
"""

import json
import os
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ork_file(filepath):
    """Parse .ork file (ZIP containing XML) and extract rocket data."""
    try:
        with zipfile.ZipFile(filepath, 'r') as zf:
            xml_filename = None
            for name in zf.namelist():
                if name.endswith('.ork') or name.endswith('.xml'):
                    xml_filename = name
                    break
            if xml_filename:
                xml_bytes = zf.read(xml_filename)
                root = ET.fromstring(xml_bytes.decode('utf-8'))
                return root, None
    except zipfile.BadZipFile:
        try:
            tree = ET.parse(filepath)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Failed to parse XML: {e}"
    except Exception as e:
        return None, f"Failed to open ZIP: {e}"
    return None, "No XML found"

def verify_fin_planform_drag_redesign(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/simple_model_rocket.ork')
    report_vm_paths = metadata.get('report_vm_paths', [
        '/home/ga/Documents/exports/fin_redesign_report.txt',
        '/home/ga/Documents/exports/report.txt',
        '/home/ga/Documents/fin_redesign_report.txt',
        '/home/ga/fin_redesign_report.txt'
    ])

    score = 0
    feedback_parts = []
    
    # Copy task_result.json
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_result.close()
    result_data = {}
    try:
        copy_from_env('/tmp/task_result.json', tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result data: {e}")
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # Copy .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = parse_ork_file(tmp_ork.name)
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

    # Extract Fin Sets
    finsets = []
    for elem in ork_root.iter():
        if 'finset' in elem.tag.lower():
            fs = {}
            for tag in ['rootchord', 'tipchord', 'sweeplength']:
                val = elem.findtext(tag)
                if val is not None:
                    try:
                        fs[tag] = float(val)
                    except ValueError:
                        pass
            if 'rootchord' in fs and 'tipchord' in fs:
                finsets.append(fs)
                
    # Check 1: Tapered Fins (25 pts)
    tapered = False
    for fs in finsets:
        if fs.get('tipchord', 0) < fs.get('rootchord', 0) - 0.001:  # Allow small precision issues
            tapered = True
            break
            
    if tapered:
        score += 25
        feedback_parts.append("Tapered fins found (tip chord < root chord) [25/25 pts]")
    else:
        feedback_parts.append("Fins are not tapered [0/25 pts]")

    # Check 2: Sweep added (20 pts)
    swept = False
    for fs in finsets:
        if fs.get('sweeplength', 0) > 0.001:
            swept = True
            break

    if swept:
        score += 20
        feedback_parts.append("Sweep length is positive [20/20 pts]")
    else:
        feedback_parts.append("Fins have no sweep [0/20 pts]")

    # Check 3: Root chord changed (10 pts)
    rc_changed = False
    for fs in finsets:
        rc = fs.get('rootchord', 0)
        if abs(rc - 0.15) > 0.005:  # Changed from injected 150mm
            rc_changed = True
            break
            
    if rc_changed:
        score += 10
        feedback_parts.append("Root chord changed from original 150mm [10/10 pts]")
    else:
        feedback_parts.append("Root chord unchanged [0/10 pts]")

    # Extract Simulations
    sims = ork_root.find('simulations')
    uptodate_count = 0
    stable_flight = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        ghv = float(fd.get('groundhitvelocity', '999'))
                        maxalt = float(fd.get('maxaltitude', '0'))
                        if ghv < 20.0 and maxalt > 10.0:
                            stable_flight = True
                    except:
                        pass
    
    # Check 4: Simulation run (20 pts)
    if uptodate_count > 0:
        score += 20
        feedback_parts.append("Simulation is up to date [20/20 pts]")
    else:
        feedback_parts.append("No up to date simulation [0/20 pts]")

    # Check 5: Stable flight (10 pts)
    if stable_flight:
        score += 10
        feedback_parts.append("Simulation shows stable flight [10/10 pts]")
    else:
        feedback_parts.append("Simulation does not show stable flight [0/10 pts]")

    # Check 6: Analysis report (15 pts)
    report_found = False
    report_valid = False
    
    # Check multiple possible report paths
    for p in report_vm_paths:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        try:
            copy_from_env(p, tmp_report.name)
            if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
                report_found = True
                with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    if len(content) > 100:
                        # Check keywords
                        keywords = ['fin', 'sweep', 'taper', 'chord', 'drag', 'stability', 'redesign']
                        matches = sum(1 for kw in keywords if kw in content)
                        if matches >= 2:
                            report_valid = True
                if report_valid:
                    break
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)

    if report_valid:
        score += 15
        feedback_parts.append("Analysis report valid [15/15 pts]")
    elif report_found:
        score += 5
        feedback_parts.append("Analysis report exists but lacks expected keywords [5/15 pts]")
    else:
        feedback_parts.append("Analysis report not found [0/15 pts]")

    pass_threshold = metadata.get('pass_threshold', 60)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }