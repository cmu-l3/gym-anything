#!/usr/bin/env python3
"""
Verifier for launch_guide_drag_penalty_analysis task.

Scoring breakdown (100 points total):
  10 pts - Final file (guided_rocket.ork) exists
  20 pts - Exactly two launch lugs added to the rocket
  25 pts - Launch lugs match Small Lug dimensions (10mm OD, 30mm L)
  15 pts - Simulation is up-to-date in the saved .ork file
  20 pts - Report exists and contains 3 logically ordered apogee values reflecting drag penalties
  10 pts - Baseline apogee reported is close to the expected ground truth

Pass threshold: 65 points
"""

import os
import re
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

def verify_launch_guide_drag_penalty_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/guided_rocket.ork')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/launch_guide_report.txt')
    
    expected_baseline_apogee = metadata.get('baseline_apogee_m', 2043)
    apogee_tolerance = metadata.get('apogee_tolerance_m', 150)
    
    small_lug_length_m = metadata.get('small_lug_length_m', 0.030)
    small_lug_od_m = metadata.get('small_lug_od_m', 0.010)

    score = 0
    feedback_parts = []
    
    # 1. Final file saved (10 pts)
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(ork_vm_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        pass
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is not None:
        score += 10
        feedback_parts.append("guided_rocket.ork exists [10/10 pts]")
        
        # Look for launch lugs across the entire rocket
        lugs = list(ork_root.iter('launchlug'))
        
        # 2. Components Added (20 pts)
        if len(lugs) == 2:
            score += 20
            feedback_parts.append("Exactly two launch lugs found [20/20 pts]")
        elif len(lugs) > 0:
            score += 10
            feedback_parts.append(f"Found {len(lugs)} launch lugs instead of 2 [10/20 pts]")
        else:
            feedback_parts.append("No launch lugs found [0/20 pts]")
            
        # 3. Lugs Correctly Sized (25 pts)
        if len(lugs) > 0:
            correct_size = True
            for lug in lugs:
                length = float(lug.findtext('length', '0'))
                # Handle OpenRocket's saving format for outer radius
                radius_text = lug.findtext('radius', lug.findtext('outerradius', '0'))
                od = float(radius_text) * 2
                
                if not (math.isclose(length, small_lug_length_m, abs_tol=0.005) and math.isclose(od, small_lug_od_m, abs_tol=0.002)):
                    correct_size = False
            
            if correct_size and len(lugs) == 2:
                score += 25
                feedback_parts.append("Launch lugs match Small Lug dimensions [25/25 pts]")
            elif correct_size:
                score += 15
                feedback_parts.append("Launch lugs match Small Lug dimensions but incorrect count [15/25 pts]")
            else:
                feedback_parts.append("Launch lugs do not match Small Lug dimensions [0/25 pts]")
                
        # 4. Simulation Updated (15 pts)
        sims = ork_root.find('simulations')
        uptodate_count = 0
        if sims is not None:
            for sim in sims.findall('simulation'):
                if sim.get('status') == 'uptodate':
                    uptodate_count += 1
        
        if uptodate_count > 0:
            score += 15
            feedback_parts.append(f"Simulation status is uptodate [15/15 pts]")
        else:
            feedback_parts.append("No uptodate simulations found [0/15 pts]")
    else:
        feedback_parts.append("guided_rocket.ork NOT found [0/70 pts]")

    # Report Analysis
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_content = ""
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        if os.path.exists(tmp_report.name) and os.path.getsize(tmp_report.name) > 0:
            with open(tmp_report.name, 'r') as f:
                report_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    if report_content:
        # Find numbers that might be apogees (typically between 1000 and 4000 for this model)
        numbers = re.findall(r'\b(1\d{3}|2\d{3})(?:\.\d+)?\b', report_content)
        numbers = [float(n) for n in numbers]
        
        # 5. Report Data Logic (20 pts)
        if len(numbers) >= 3:
            distinct_apogees = sorted(list(set(numbers)), reverse=True)
            if len(distinct_apogees) >= 3:
                # Expecting Baseline > Small Lugs > Large Lugs apogees to be distinct
                baseline = distinct_apogees[0]
                small = distinct_apogees[1]
                large = distinct_apogees[2]
                if baseline > small > large:
                    score += 20
                    feedback_parts.append("Report contains 3 logical apogee values reflecting proper drag penalties [20/20 pts]")
                else:
                    score += 10
                    feedback_parts.append("Report contains 3 apogee values, but logic (Baseline > Small > Large) is unclear [10/20 pts]")
            else:
                score += 10
                feedback_parts.append("Report contains apogee values but not 3 distinct ones for Baseline/Small/Large [10/20 pts]")
        elif len(numbers) > 0:
            score += 5
            feedback_parts.append("Report contains some numbers, but missing all 3 required apogee values [5/20 pts]")
        else:
            feedback_parts.append("Report does not contain valid apogee numbers [0/20 pts]")
            
        # 6. Baseline Accuracy (10 pts)
        if len(numbers) > 0:
            max_reported = max(numbers)
            if abs(max_reported - expected_baseline_apogee) <= apogee_tolerance:
                score += 10
                feedback_parts.append(f"Reported baseline apogee ({max_reported}) matches ground truth [10/10 pts]")
            else:
                feedback_parts.append(f"Reported baseline apogee ({max_reported}) differs from expected ({expected_baseline_apogee}) [0/10 pts]")
        else:
            feedback_parts.append("No baseline apogee to verify [0/10 pts]")
    else:
        feedback_parts.append("launch_guide_report.txt NOT found or empty [0/30 pts]")

    passed = score >= metadata.get('pass_threshold', 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }