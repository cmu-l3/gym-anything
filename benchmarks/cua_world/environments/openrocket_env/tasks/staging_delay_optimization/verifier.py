#!/usr/bin/env python3
"""
Verifier for staging_delay_optimization task.

Scoring breakdown (100 points total):
  25 pts - Stage 2 ignition delay fixed (0.3s <= delay <= 8.0s)
  25 pts - Stage 3 ignition delay fixed (0.3s <= delay <= 8.0s)
  20 pts - At least one simulation has 'uptodate' status (re-run after fixing)
  15 pts - Max altitude > 40m (demonstrating staging works instead of failing on pad)
  15 pts - Staging report file exists with meaningful content and keywords

Pass threshold: 60 points
  Do-nothing max: 0 (delays still 0.0/20.0, no uptodate sims, no report)
"""

import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import json


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


def verify_staging_delay_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/three_stage_low_power_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/staging_report.txt')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve JSON metadata from export
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env('/tmp/staging_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception:
        result = {}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # 2. Retrieve ORK File
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

    # Extract stages and their ignition delays
    stages = list(ork_root.iter('stage'))
    stage3_fixed = False
    stage2_fixed = False
    
    if len(stages) >= 3:
        # Top stage (Stage 3)
        s3_delays = []
        for mm in stages[0].iter('motormount'):
            try: s3_delays.append(float(mm.findtext('ignitiondelay', '0.0')))
            except: pass
        if s3_delays and 0.3 <= s3_delays[0] <= 8.0:
            stage3_fixed = True
            
        # Middle stage (Stage 2)
        s2_delays = []
        for mm in stages[1].iter('motormount'):
            try: s2_delays.append(float(mm.findtext('ignitiondelay', '0.0')))
            except: pass
        if s2_delays and 0.3 <= s2_delays[0] <= 8.0:
            stage2_fixed = True
    else:
        # Fallback if agent modified the tree structure, scan all motor mounts looking for valid upper stage delays
        valid_delays = 0
        for mm in ork_root.iter('motormount'):
            try:
                d = float(mm.findtext('ignitiondelay', '0.0'))
                if 0.3 <= d <= 8.0:
                    valid_delays += 1
            except: pass
        if valid_delays >= 1: stage3_fixed = True
        if valid_delays >= 2: stage2_fixed = True

    # ---- Check 1: Stage 2 ignition delay fixed (25 points) ----
    if stage2_fixed:
        score += 25
        feedback_parts.append("Stage 2 ignition delay fixed [25/25 pts]")
    else:
        feedback_parts.append("Stage 2 ignition delay not fixed [0/25 pts]")

    # ---- Check 2: Stage 3 ignition delay fixed (25 points) ----
    if stage3_fixed:
        score += 25
        feedback_parts.append("Stage 3 ignition delay fixed [25/25 pts]")
    else:
        feedback_parts.append("Stage 3 ignition delay not fixed [0/25 pts]")

    # ---- Check 3 & 4: Simulations & Altitude (35 points total) ----
    sims = ork_root.find('simulations')
    uptodate_count = 0
    max_alt = 0.0
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_count += 1
                fd = sim.find('flightdata')
                if fd is not None:
                    try:
                        alt = float(fd.get('maxaltitude', '0'))
                        max_alt = max(max_alt, alt)
                    except ValueError:
                        pass
                        
    if uptodate_count >= 1:
        score += 20
        feedback_parts.append("Simulation(s) successfully run [20/20 pts]")
    else:
        feedback_parts.append("No uptodate simulations found [0/20 pts]")
        
    if max_alt > 40.0:
        score += 15
        feedback_parts.append(f"Altitude is reasonable ({max_alt:.1f}m) [15/15 pts]")
    else:
        feedback_parts.append(f"Altitude too low or no data ({max_alt:.1f}m) [0/15 pts]")

    # ---- Check 5: Staging Report (15 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_valid = False
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 100:
            with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                keywords = ['delay', 'stage', 'ignition', 'second', 'altitude', 'separation', 'coast', 'optimization', 'timing', 'sim']
                found_kw = [kw for kw in keywords if kw in content]
                # Requires at least 3 relevant keywords and the presence of numbers (for values)
                if len(found_kw) >= 3 and any(char.isdigit() for char in content):
                    report_valid = True
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    if report_valid:
        score += 15
        feedback_parts.append("Valid staging optimization report found [15/15 pts]")
    else:
        feedback_parts.append("Staging report invalid or missing [0/15 pts]")

    # Calculate overall pass (must score 60+ and have actually fixed delays and run sims)
    key_criteria_met = (stage2_fixed or stage3_fixed) and uptodate_count >= 1
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }