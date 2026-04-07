#!/usr/bin/env python3
"""
Verifier for flight_data_export_and_analysis task.

Scoring breakdown (100 points total):
  30 pts - At least 4 of 5 simulations have 'uptodate' status (all re-run)
  30 pts - At least 3 CSV flight data files exist in the exports directory
  40 pts - Analysis report exists with:
           - Performance metrics table or data (15 pts)
           - Best configuration identified (10 pts)
           - Motor recommendation for 250m target (15 pts)

Pass threshold: 65 points
  (sims+CSVs alone = 60 pts, just below threshold -- report is required to pass)
  Do-nothing max: 0 (all sims outdated, no CSVs, no report)
"""

import os
import re
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


def verify_flight_data_export_and_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ork_vm_path = metadata.get('ork_vm_path', '/home/ga/Documents/rockets/flight_analysis.ork')
    exports_dir = metadata.get('exports_dir_vm', '/home/ga/Documents/exports/flight_data')
    report_vm_path = metadata.get('report_vm_path', '/home/ga/Documents/exports/flight_analysis_report.txt')
    min_uptodate = metadata.get('min_uptodate_sims', 4)
    min_csv = metadata.get('min_csv_files', 3)

    score = 0
    feedback_parts = []
    details = {}

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

    # Count uptodate simulations
    sims = ork_root.find('simulations')
    uptodate_count = 0
    total_count = 0
    if sims is not None:
        total_count = len(list(sims.findall('simulation')))
        uptodate_count = sum(
            1 for s in sims.findall('simulation') if s.get('status') == 'uptodate'
        )

    details['uptodate_sim_count'] = uptodate_count
    details['total_sim_count'] = total_count

    # ---- Check 1: Uptodate simulations (30 points) ----
    if uptodate_count >= min_uptodate:
        score += 30
        feedback_parts.append(f"{uptodate_count}/{total_count} sims uptodate [30/30 pts]")
    elif uptodate_count >= 2:
        pts = int(30 * uptodate_count / min_uptodate)
        score += pts
        feedback_parts.append(
            f"Only {uptodate_count}/{total_count} sims uptodate (need >={min_uptodate}) [{pts}/30 pts]"
        )
    elif uptodate_count == 1:
        score += 8
        feedback_parts.append(f"Only 1 sim uptodate [8/30 pts]")
    else:
        feedback_parts.append("No sims uptodate [0/30 pts]")

    # ---- Check 2: CSV files (30 points) ----
    csv_count = 0
    csv_names = []
    possible_names = [
        'sim_1.csv', 'sim_2.csv', 'sim_3.csv', 'sim_4.csv', 'sim_5.csv',
        'simulation_1.csv', 'simulation_2.csv', 'simulation_3.csv',
        'flight_1.csv', 'flight_2.csv', 'flight_3.csv',
        '1.csv', '2.csv', '3.csv', '4.csv', '5.csv',
    ]
    for csv_name in possible_names:
        tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        tmp_csv.close()
        try:
            copy_from_env(f"{exports_dir}/{csv_name}", tmp_csv.name)
            if os.path.getsize(tmp_csv.name) > 10:
                csv_count += 1
                csv_names.append(csv_name)
        except Exception:
            pass
        finally:
            if os.path.exists(tmp_csv.name):
                os.unlink(tmp_csv.name)

    # Also check generic filenames
    if csv_count < min_csv:
        for generic_name in ['motor_comparison.csv', 'export.csv', 'data.csv',
                              'output.csv', 'flight_data.csv', 'results.csv']:
            tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            tmp_csv.close()
            try:
                copy_from_env(f"/home/ga/Documents/exports/{generic_name}", tmp_csv.name)
                if os.path.getsize(tmp_csv.name) > 10:
                    csv_count += 1
                    csv_names.append(generic_name)
            except Exception:
                pass
            finally:
                if os.path.exists(tmp_csv.name):
                    os.unlink(tmp_csv.name)

    details['csv_files_found'] = csv_names
    if csv_count >= min_csv:
        score += 30
        feedback_parts.append(f"{csv_count} CSV files found [30/30 pts]")
    elif csv_count >= 1:
        pts = int(30 * csv_count / min_csv)
        score += pts
        feedback_parts.append(f"Only {csv_count}/{min_csv} CSV files [{pts}/30 pts]")
    else:
        feedback_parts.append("No CSV export files found [0/30 pts]")

    # ---- Check 3: Analysis report (40 points) ----
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_report.close()
    report_score = 0
    try:
        copy_from_env(report_vm_path, tmp_report.name)
        with open(tmp_report.name, 'r', errors='replace') as f:
            report_text = f.read()

        details['report_size'] = len(report_text)

        if len(report_text) >= 200:
            # Sub-check A: Performance metrics (15 pts)
            has_metrics = bool(re.search(
                r'altitude|apogee|velocity|time.*apogee|m/s|\dm\b', report_text, re.IGNORECASE
            ))
            has_numbers = bool(re.search(
                r'\d{2,4}\.\d|\d{2,4}\s*m\b', report_text, re.IGNORECASE
            ))
            has_multiple_sims = bool(re.search(
                r'sim(ulation)?\s*[1-5]|config\s*[1-5]|[ABC][468]|C6', report_text, re.IGNORECASE
            ))
            if has_metrics and has_numbers and has_multiple_sims:
                report_score += 15
            elif has_metrics and has_numbers:
                report_score += 10
            elif has_metrics or has_numbers:
                report_score += 5

            # Sub-check B: Best configuration (10 pts)
            has_best = bool(re.search(
                r'best|highest|optimal|maximum|greatest|top|winner', report_text, re.IGNORECASE
            ))
            has_config_ref = bool(re.search(
                r'config|motor|[ABCIJK]\d|simulation [1-5]', report_text, re.IGNORECASE
            ))
            if has_best and has_config_ref:
                report_score += 10
            elif has_best or has_config_ref:
                report_score += 5

            # Sub-check C: Recommendation for 250m target (15 pts)
            has_recommendation = bool(re.search(
                r'recommend|suggest|should use|for.*250|250.*target|choose', report_text, re.IGNORECASE
            ))
            has_target_alt = bool(re.search(r'250\s*m|target|goal', report_text, re.IGNORECASE))
            if has_recommendation and has_target_alt:
                report_score += 15
            elif has_recommendation or has_target_alt:
                report_score += 8

        elif len(report_text) >= 50:
            report_score = 5
        elif len(report_text) >= 10:
            report_score = 2

        score += report_score
        feedback_parts.append(
            f"Analysis report ({len(report_text)} chars) [{report_score}/40 pts]"
        )
    except Exception:
        feedback_parts.append("Analysis report not found [0/40 pts]")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
