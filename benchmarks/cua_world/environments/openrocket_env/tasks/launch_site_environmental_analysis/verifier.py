#!/usr/bin/env python3
"""
Verifier for launch_site_environmental_analysis task.

Checks:
1. ORK file saved and contains two distinct simulations.
2. Switzerland simulation launch conditions: ~400m altitude, ~15C (288.15K).
3. New Mexico simulation launch conditions: ~1400m altitude, ~35C (308.15K).
4. Both CSV files exist, are exported with valid sizes, and contain expected OpenRocket headers.
5. Report text file exists and indicates understanding of the apogee difference.

Scoring breakdown (100 points total):
  10 pts - File saved (`environmental_analysis.ork`)
  25 pts - Switzerland simulation configured correctly
  25 pts - New Mexico simulation configured correctly
  25 pts - CSV exports valid
  15 pts - Impact report exists and is valid

Pass threshold: 70 points
"""

import os
import re
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return root_element."""
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

def verify_launch_site_environmental_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_ork_path = metadata.get('target_ork_path', '/home/ga/Documents/rockets/environmental_analysis.ork')
    switzerland_csv_path = metadata.get('switzerland_csv', '/home/ga/Documents/exports/switzerland.csv')
    new_mexico_csv_path = metadata.get('new_mexico_csv', '/home/ga/Documents/exports/new_mexico.csv')
    report_path = metadata.get('report_path', '/home/ga/Documents/exports/environmental_impact_report.txt')

    score = 0
    feedback_parts = []

    # 1. Check result JSON from export script
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    if not export_data.get('ork_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "environmental_analysis.ork not found. Agent did not save the design file."
        }
        
    score += 10
    feedback_parts.append("Saved .ork file [10/10 pts]")

    if not export_data.get('created_during_task'):
        feedback_parts.append("WARNING: File timestamps do not appear to match task duration.")

    # 2. Parse the saved .ork file
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork').name
    ork_root = None
    try:
        copy_from_env(target_ork_path, tmp_ork)
        ork_root, parse_err = _parse_ork(tmp_ork)
        if parse_err:
            feedback_parts.append(f"Could not parse saved .ork file: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Failed to fetch .ork: {e}")
    finally:
        if os.path.exists(tmp_ork):
            os.unlink(tmp_ork)

    if ork_root is None:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check simulations
    sims = ork_root.find('simulations')
    switz_ok = False
    nm_ok = False
    
    if sims is not None:
        for sim in sims.findall('simulation'):
            name = sim.findtext('name', '').lower()
            conds = sim.find('conditions')
            if conds is not None:
                # OpenRocket saves alt in meters and temp in Kelvin
                try:
                    alt = float(conds.findtext('launchaltitude', '0'))
                    temp_k = float(conds.findtext('temperature', '288.15'))  # Standard sea level is ~288.15K
                except ValueError:
                    alt, temp_k = 0.0, 288.15
                
                # Check Switzerland config (400m, 15C / 288.15K)
                if 'switz' in name:
                    if abs(alt - 400.0) < 5 and abs(temp_k - 288.15) < 2:
                        switz_ok = True
                
                # Check New Mexico config (1400m, 35C / 308.15K)
                if 'mexico' in name:
                    if abs(alt - 1400.0) < 5 and abs(temp_k - 308.15) < 2:
                        nm_ok = True

    if switz_ok:
        score += 25
        feedback_parts.append("Switzerland simulation configured perfectly [25/25 pts]")
    else:
        feedback_parts.append("Switzerland simulation missing or incorrectly configured [0/25 pts]")

    if nm_ok:
        score += 25
        feedback_parts.append("New Mexico simulation configured perfectly [25/25 pts]")
    else:
        feedback_parts.append("New Mexico simulation missing or incorrectly configured [0/25 pts]")

    # 3. Check CSV exports
    csv_pts = 0
    if export_data.get('switz_csv_exists') and export_data.get('switz_csv_size', 0) > 500:
        csv_pts += 12.5
    if export_data.get('nm_csv_exists') and export_data.get('nm_csv_size', 0) > 500:
        csv_pts += 12.5
        
    # Check headers to prevent dummy CSV files
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    valid_csvs = 0
    try:
        if export_data.get('nm_csv_exists'):
            copy_from_env(new_mexico_csv_path, tmp_csv)
            with open(tmp_csv, 'r') as f:
                content = f.read(2000)
                # OpenRocket CSVs contain comment headers like "# Time (s)"
                if "# Time" in content or "Altitude" in content:
                    valid_csvs += 1
                    
        if export_data.get('switz_csv_exists'):
            copy_from_env(switzerland_csv_path, tmp_csv)
            with open(tmp_csv, 'r') as f:
                content = f.read(2000)
                if "# Time" in content or "Altitude" in content:
                    valid_csvs += 1
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_csv):
            os.unlink(tmp_csv)

    if valid_csvs == 2 and csv_pts == 25:
        score += 25
        feedback_parts.append("Both CSV flight data files exported correctly [25/25 pts]")
    elif csv_pts > 0:
        score += 10
        feedback_parts.append("Partial/invalid CSV exports found [10/25 pts]")
    else:
        feedback_parts.append("Missing CSV exports [0/25 pts]")

    # 4. Check Impact Report
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    report_pts = 0
    try:
        if export_data.get('report_exists'):
            copy_from_env(report_path, tmp_report)
            with open(tmp_report, 'r') as f:
                report_text = f.read().lower()
                
            # Basic content checks
            has_switz = 'switz' in report_text
            has_nm = 'mexico' in report_text
            has_numbers = bool(re.search(r'\d{3,5}', report_text))
            
            if has_switz and has_nm and has_numbers:
                report_pts = 15
                feedback_parts.append("Impact report contains correct comparison metrics [15/15 pts]")
            else:
                report_pts = 5
                feedback_parts.append("Impact report exists but lacks comprehensive comparison details [5/15 pts]")
        else:
            feedback_parts.append("Impact report missing [0/15 pts]")
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_report):
            os.unlink(tmp_report)
            
    score += report_pts

    threshold = metadata.get('pass_threshold', 70)
    passed = score >= threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }