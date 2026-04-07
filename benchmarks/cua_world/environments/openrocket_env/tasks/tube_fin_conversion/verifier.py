#!/usr/bin/env python3
"""
Verifier for tube_fin_conversion task.

Verification Strategy:
1. Anti-gaming: Check if .ork was created after task start and is not just a copy of the baseline. (5 pts)
2. XML Parsing: Check for presence of <tubefinset> (25 pts)
3. XML Parsing: Check for absence of standard fins (<trapezoidfinset>, <ellipticalfinset>, <freeformfinset>) (20 pts)
4. XML Parsing: Validate tube fin parameters (count=6 -> 5 pts, reasonable dimensions -> 10 pts)
5. XML Parsing: Simulation run / uptodate status (20 pts)
6. Report Parsing: Report exists and is >= 200 words mentioning both fin types (10 pts)
7. Report Parsing: Includes performance metrics data (apogee, velocity, etc.) (5 pts)

Pass threshold: 60 points
"""

import os
import re
import tempfile
import zipfile
import json
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


def verify_tube_fin_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_fin_count = metadata.get('expected_fin_count', 6)
    expected_outer_radius_m = metadata.get('expected_outer_radius_m', 0.010)
    expected_length_m = metadata.get('expected_length_m', 0.070)
    expected_thickness_m = metadata.get('expected_thickness_m', 0.001)

    score = 0
    feedback_parts = []

    # ---- 1. Get exported JSON state ----
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    
    result = {}
    try:
        copy_from_env("/tmp/tube_fin_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    task_start = result.get('task_start_ts', 0)
    ork_exists = result.get('ork_exists', False)
    ork_mtime = result.get('ork_mtime', 0)
    ork_md5 = result.get('ork_md5', '')
    source_md5 = result.get('source_ork_md5', '')
    report_exists = result.get('report_exists', False)
    report_path = result.get('report_path', '')

    if not ork_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target ORK file (tube_fin_conversion.ork) was not found."
        }

    # Anti-gaming: Ensure file was modified after task start and isn't just the source
    if ork_md5 == source_md5:
        feedback_parts.append("Saved ORK file is identical to the source file [0/5 pts]")
    elif ork_mtime >= task_start:
        score += 5
        feedback_parts.append("Valid modified ORK file saved [5/5 pts]")
    else:
        feedback_parts.append("ORK file timestamp precedes task start (anti-gaming flag) [0/5 pts]")

    # ---- 2. Retrieve and parse ORK file ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env("/home/ga/Documents/rockets/tube_fin_conversion.ork", tmp_ork.name)
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
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Failed to parse rocket XML"
        }

    # ---- 3. XML Analysis: Fin replacements ----
    tube_fins = list(ork_root.iter('tubefinset'))
    trapezoid_fins = list(ork_root.iter('trapezoidfinset'))
    elliptical_fins = list(ork_root.iter('ellipticalfinset'))
    freeform_fins = list(ork_root.iter('freeformfinset'))

    if len(tube_fins) > 0:
        score += 25
        feedback_parts.append("Tube fins added [25/25 pts]")
    else:
        feedback_parts.append("No <tubefinset> found [0/25 pts]")

    if len(trapezoid_fins) == 0 and len(elliptical_fins) == 0 and len(freeform_fins) == 0:
        score += 20
        feedback_parts.append("Standard fins fully removed [20/20 pts]")
    else:
        feedback_parts.append("Standard planar fins still exist in the design [0/20 pts]")

    # ---- 4. XML Analysis: Tube fin parameters ----
    if len(tube_fins) > 0:
        t_fin = tube_fins[0]
        
        # Count check
        count_text = t_fin.findtext('fincount', '0')
        try:
            fin_count = int(count_text)
            if fin_count == expected_fin_count:
                score += 5
                feedback_parts.append("Correct tube fin count (6) [5/5 pts]")
            else:
                feedback_parts.append(f"Incorrect fin count ({fin_count} != 6) [0/5 pts]")
        except ValueError:
            feedback_parts.append("Invalid fin count [0/5 pts]")

        # Dimensions check
        try:
            r_out = float(t_fin.findtext('outerradius', '0'))
            length = float(t_fin.findtext('length', '0'))
            thickness = float(t_fin.findtext('thickness', '0'))
            
            # Tolerances to allow slight variation / agent interpretation
            dim_score = 0
            if 0.008 <= r_out <= 0.015: dim_score += 4
            if 0.050 <= length <= 0.100: dim_score += 4
            if 0.0005 <= thickness <= 0.002: dim_score += 2
            
            score += dim_score
            feedback_parts.append(f"Tube dimensions verified ({dim_score}/10 pts)")
        except ValueError:
            feedback_parts.append("Invalid tube fin dimensions [0/10 pts]")
    else:
        feedback_parts.append("Skipping tube dimension checks [0/15 pts]")

    # ---- 5. XML Analysis: Simulation run ----
    sims = ork_root.find('simulations')
    uptodate = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status', '').upper() in ('UPTODATE', 'LOADED'):
                uptodate = True
                break
    
    if uptodate:
        score += 20
        feedback_parts.append("Simulation successfully run [20/20 pts]")
    else:
        feedback_parts.append("No uptodate simulation found [0/20 pts]")

    # ---- 6. Report Content Analysis ----
    if report_exists and report_path:
        tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_report.close()
        
        try:
            copy_from_env(report_path, tmp_report.name)
            with open(tmp_report.name, 'r') as f:
                report_content = f.read().lower()
                
            words = report_content.split()
            
            # Length & Keyword check
            if len(words) >= 150:  # Relaxed slightly to 150 for partial credit
                has_tube = 'tube' in report_content
                has_standard = any(w in report_content for w in ['trapezoid', 'standard', 'original', 'planar'])
                
                if has_tube and has_standard and len(words) >= 200:
                    score += 10
                    feedback_parts.append("Detailed comparative report created [10/10 pts]")
                elif has_tube and has_standard:
                    score += 7
                    feedback_parts.append("Adequate comparative report created [7/10 pts]")
                else:
                    score += 5
                    feedback_parts.append("Report exists but missing comparative keywords [5/10 pts]")
            else:
                score += 3
                feedback_parts.append(f"Report is too short ({len(words)} words) [3/10 pts]")
                
            # Performance data check
            perf_keywords = ['apogee', 'altitude', 'velocity', 'stability', 'margin', 'mach', 'm/s', 'ft']
            found_perf = [k for k in perf_keywords if k in report_content]
            if len(found_perf) >= 2:
                score += 5
                feedback_parts.append("Report contains performance metrics [5/5 pts]")
            elif len(found_perf) == 1:
                score += 2
                feedback_parts.append("Report contains minimal performance metrics [2/5 pts]")
            else:
                feedback_parts.append("Report lacks performance metrics [0/5 pts]")
                
        except Exception as e:
            feedback_parts.append(f"Failed to read report: {e}")
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
    else:
        feedback_parts.append("No performance report found [0/15 pts]")

    pass_threshold = metadata.get('pass_threshold', 60)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }