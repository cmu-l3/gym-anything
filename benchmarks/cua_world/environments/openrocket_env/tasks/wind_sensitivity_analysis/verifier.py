#!/usr/bin/env python3
"""
Verifier for wind_sensitivity_analysis task.

Scoring breakdown (100 points total):
  25 pts - Wind sweep created: >=6 simulations with >=5 distinct wind speed values
  10 pts - Wind range adequate: At least one calm (<=0.1m/s) and one strong (>=9.9m/s)
  20 pts - Simulations uptodate: All required distinct wind configurations have been run
  20 pts - Valid CSV export exists (must be created after task start, >=6 rows)
  10 pts - Launch readiness report exists and is meaningful (>= 150 chars, created after task start)
  15 pts - Report contains a specific numeric threshold recommendation (go/no-go)

Pass threshold: 60 points
  Do-nothing max: 0
"""

import os
import re
import json
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


def verify_wind_sensitivity_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/wind_sensitivity.ork')
    csv_vm_path = metadata.get('csv_vm_path', '/home/ga/Documents/exports/wind_sensitivity.csv')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/wind_report.txt')

    score = 0
    feedback_parts = []
    details = {}

    # ---- Read Export Metadata ----
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env("/tmp/wind_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task export result: {e}"}
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    task_start_ts = export_data.get('task_start_ts', 0)

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

    # ---- Analyze Simulations ----
    sims = ork_root.find('simulations')
    sims_data = []
    if sims is not None:
        for sim in sims.findall('simulation'):
            status = sim.get('status', 'outdated')
            windaverage = 0.0
            cond = sim.find('conditions')
            if cond is not None:
                try:
                    windaverage = float(cond.findtext('windaverage', '0.0'))
                except ValueError:
                    pass
            sims_data.append({'status': status, 'wind': windaverage})

    distinct_winds = {round(s['wind'], 2) for s in sims_data}
    uptodate_winds = {round(s['wind'], 2) for s in sims_data if s['status'] == 'uptodate'}

    details['total_simulations'] = len(sims_data)
    details['distinct_winds'] = list(distinct_winds)
    details['uptodate_winds'] = list(uptodate_winds)

    # Criterion 1: Wind sweep created (25 pts)
    if len(sims_data) >= 6 and len(distinct_winds) >= 5:
        score += 25
        feedback_parts.append(f"Wind sweep created ({len(distinct_winds)} distinct winds) [25/25 pts]")
    elif len(distinct_winds) >= 3:
        score += 10
        feedback_parts.append(f"Partial wind sweep ({len(distinct_winds)} distinct winds) [10/25 pts]")
    else:
        feedback_parts.append("Inadequate wind sweep created [0/25 pts]")

    # Criterion 2: Wind range adequate (10 pts)
    if distinct_winds and min(distinct_winds) <= 0.1 and max(distinct_winds) >= 9.9:
        score += 10
        feedback_parts.append(f"Adequate wind range ({min(distinct_winds):.1f} to {max(distinct_winds):.1f} m/s) [10/10 pts]")
    elif distinct_winds:
        feedback_parts.append(f"Inadequate wind range ({min(distinct_winds):.1f} to {max(distinct_winds):.1f} m/s) [0/10 pts]")
    else:
        feedback_parts.append("No wind data [0/10 pts]")

    # Criterion 3: Simulations uptodate (20 pts)
    if len(uptodate_winds) >= 5:
        score += 20
        feedback_parts.append(f"All required simulations uptodate [20/20 pts]")
    elif len(uptodate_winds) > 0:
        score += int(20 * (len(uptodate_winds) / 5))
        feedback_parts.append(f"{len(uptodate_winds)} distinct wind simulations uptodate [Partial pts]")
    else:
        feedback_parts.append("No simulations uptodate [0/20 pts]")

    # ---- Check CSV Export (20 pts) ----
    csv_exists = export_data.get('csv_exists', False)
    csv_mtime = export_data.get('csv_mtime', 0)
    csv_size = export_data.get('csv_size', 0)

    if csv_exists and csv_mtime >= task_start_ts and csv_size > 50:
        tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        tmp_csv.close()
        try:
            copy_from_env(csv_vm_path, tmp_csv.name)
            with open(tmp_csv.name, 'r', errors='ignore') as f:
                lines = f.readlines()
            if len(lines) >= 6:
                score += 20
                feedback_parts.append("Valid CSV export found [20/20 pts]")
            else:
                score += 10
                feedback_parts.append("CSV export found but has too few rows [10/20 pts]")
        except Exception as e:
            feedback_parts.append(f"Failed to validate CSV contents: {e}")
        finally:
            if os.path.exists(tmp_csv.name):
                os.unlink(tmp_csv.name)
    elif csv_exists and csv_mtime < task_start_ts:
        feedback_parts.append("CSV file is stale (created before task start) [0/20 pts]")
    else:
        feedback_parts.append("CSV export missing or empty [0/20 pts]")

    # ---- Check Launch Readiness Report (25 pts) ----
    report_exists = export_data.get('report_exists', False)
    report_mtime = export_data.get('report_mtime', 0)
    report_size = export_data.get('report_size', 0)

    if report_exists and report_mtime >= task_start_ts and report_size > 50:
        tmp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_rep.close()
        try:
            copy_from_env(report_vm_path, tmp_rep.name)
            with open(tmp_rep.name, 'r', errors='ignore') as f:
                content = f.read()

            if len(content.strip()) >= 150:
                score += 10
                feedback_parts.append("Meaningful report found [10/10 pts]")

                # Check for numeric go/no-go threshold
                if re.search(r'\d+', content):
                    score += 15
                    feedback_parts.append("Report includes threshold recommendation [15/15 pts]")
                else:
                    feedback_parts.append("Report lacks numeric threshold recommendation [0/15 pts]")
            else:
                score += 5
                feedback_parts.append("Report is too brief [5/25 pts]")
        except Exception as e:
            feedback_parts.append(f"Failed to validate report contents: {e}")
        finally:
            if os.path.exists(tmp_rep.name):
                os.unlink(tmp_rep.name)
    elif report_exists and report_mtime < task_start_ts:
        feedback_parts.append("Report file is stale (created before task start) [0/25 pts]")
    else:
        feedback_parts.append("Launch readiness report missing or empty [0/25 pts]")

    # ---- Final Evaluation ----
    passed = score >= metadata.get('pass_threshold', 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }