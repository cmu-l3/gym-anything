#!/usr/bin/env python3
"""
Verifier for xray_binary_optical_counterparts task.

Criteria (100 pts total, pass >= 80):
1. Cygnus X-1 Data (≥3 new V-band FITS in CygnusX1/ with EXPTIME=15) - 20 pts
2. V404 Cygni Data (≥3 new V-band FITS in V404Cygni/ with EXPTIME=15) - 20 pts
3. SS 433 Data (≥3 new V-band FITS in SS433/ with EXPTIME=15) - 20 pts
4. Finding Charts (Up to 3 finding_chart.png files generated) - 20 pts
5. Summary Report (Exists and contains decimal coordinates) - 20 pts
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_xray_binary_optical_counterparts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    # ── Count valid FITS per target directory ─────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files 
                  if f.get('mtime', 0) > task_start 
                  and f.get('size', 0) > 1000000  # FITS from INDI are usually ~8MB
                  and 14.5 <= f.get('exptime', 0) <= 15.5]

    def count_target_fits(target_name):
        return sum(1 for f in valid_fits if f.get('dir', '').lower() == target_name.lower())

    cyg_count = count_target_fits('CygnusX1')
    v404_count = count_target_fits('V404Cygni')
    ss_count = count_target_fits('SS433')

    # Criterion 1: Cygnus X-1 Data (20 pts)
    if cyg_count >= 3:
        score += 20
        feedback.append(f"CygnusX1: {cyg_count} FITS captured (excl. stale files)")
    elif cyg_count > 0:
        score += 10
        feedback.append(f"CygnusX1: {cyg_count}/3 FITS captured")
    else:
        feedback.append("CygnusX1: No valid new FITS found")

    # Criterion 2: V404 Cygni Data (20 pts)
    if v404_count >= 3:
        score += 20
        feedback.append(f"V404Cygni: {v404_count} FITS captured")
    elif v404_count > 0:
        score += 10
        feedback.append(f"V404Cygni: {v404_count}/3 FITS captured")
    else:
        feedback.append("V404Cygni: No valid new FITS found")

    # Criterion 3: SS 433 Data (20 pts)
    if ss_count >= 3:
        score += 20
        feedback.append(f"SS433: {ss_count} FITS captured")
    elif ss_count > 0:
        score += 10
        feedback.append(f"SS433: {ss_count}/3 FITS captured")
    else:
        feedback.append("SS433: No valid new FITS found")

    # ── Criterion 4: Finding Charts (20 pts) ─────────────────────────
    charts = result.get('charts', [])
    valid_charts = [c for c in charts 
                    if c.get('mtime', 0) > task_start 
                    and c.get('size', 0) > 20000]  # Valid charts should be >20KB
    
    chart_dirs = set(c.get('dir', '').lower() for c in valid_charts)
    
    if len(chart_dirs) >= 3:
        score += 20
        feedback.append("Finding charts generated for all 3 targets")
    elif len(chart_dirs) == 2:
        score += 13
        feedback.append("Finding charts generated for 2 targets")
    elif len(chart_dirs) == 1:
        score += 6
        feedback.append("Finding chart generated for 1 target")
    else:
        feedback.append("No valid finding charts generated")

    # ── Criterion 5: Summary Report (20 pts) ─────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')

    if report_exists and report_mtime > task_start:
        report_text = ''
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
        except: pass

        has_names = ('cygnus' in report_text or 'x-1' in report_text) and \
                    ('v404' in report_text) and \
                    ('ss' in report_text and '433' in report_text)
        
        # Check for presence of decimal substrings for coordinates
        has_dec_1 = '19.9' in report_text or '35.2' in report_text
        has_dec_2 = '20.4' in report_text or '33.8' in report_text
        has_dec_3 = '19.1' in report_text or '4.9' in report_text or '04.9' in report_text
        has_decs = sum([has_dec_1, has_dec_2, has_dec_3]) >= 2

        if has_names and has_decs:
            score += 20
            feedback.append("Report contains target names and decimal coordinates")
        elif has_names:
            score += 10
            feedback.append("Report exists with target names (missing decimal coords)")
        else:
            score += 5
            feedback.append("Report created but content lacks target names")
    else:
        feedback.append("Summary report missing or not updated during task")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }