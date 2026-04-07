#!/usr/bin/env python3
"""
Verifier for neutrino_alert_optical_followup task.

Context: Multi-messenger ToO follow-up observing 3 blazar candidates for IceCube-170922A.

Criteria (100 pts total, pass >= 80):
1. TXS 0506+056 Data: ≥3 V-band and ≥3 R-band FITS (20 pts)
2. PKS 0502+049 Data: ≥3 V-band and ≥3 R-band FITS (20 pts)
3. GB6 J0512+0529 Data: ≥3 V-band and ≥3 R-band FITS (20 pts)
4. DSS Reference Images: 'dss_reference.png' in all 3 candidate directories (20 pts)
5. GCN Circular Draft: exists and mentions all 3 candidates (20 pts)

Anti-gaming protections:
- FITS images must be >2KB and mtime > task_start
- Reference PNGs must be >10KB and mtime > task_start
- This ignores the stale files seeded in the TXS 0506+056 directory.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CANDIDATES = ["TXS_0506+056", "PKS_0502+049", "GB6_J0512+0529"]
CANDIDATE_NAMES_FLAT = ["TXS 0506+056", "PKS 0502+049", "GB6 J0512+0529", "TXS0506", "PKS0502", "GB6J0512"]


def verify_neutrino_alert_optical_followup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    req_v_slot = metadata.get('required_v_slot', 2)
    req_r_slot = metadata.get('required_r_slot', 4)
    req_exp = metadata.get('required_exposures_per_filter', 3)

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

    # ── Evaluate FITS Files ───────────────────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_filters(candidate_folder):
        v_count = 0
        r_count = 0
        for f in valid_fits:
            # Match folder name flexibly
            if candidate_folder.replace("_", "") in f.get('candidate', '').replace("_", ""):
                filt = str(f.get('filter', '')).upper()
                if 'V' in filt or str(req_v_slot) in filt:
                    v_count += 1
                elif 'R' in filt or str(req_r_slot) in filt:
                    r_count += 1
        return v_count, r_count

    # Criterion 1: TXS 0506+056 (20 pts)
    v1, r1 = count_filters("TXS_0506+056")
    if v1 >= req_exp and r1 >= req_exp:
        score += 20
        feedback.append(f"TXS 0506+056 data complete (V:{v1}, R:{r1})")
    elif v1 >= 1 or r1 >= 1:
        score += 10
        feedback.append(f"TXS 0506+056 data partial (V:{v1}, R:{r1})")
    else:
        feedback.append("TXS 0506+056 data missing")

    # Criterion 2: PKS 0502+049 (20 pts)
    v2, r2 = count_filters("PKS_0502+049")
    if v2 >= req_exp and r2 >= req_exp:
        score += 20
        feedback.append(f"PKS 0502+049 data complete (V:{v2}, R:{r2})")
    elif v2 >= 1 or r2 >= 1:
        score += 10
        feedback.append(f"PKS 0502+049 data partial (V:{v2}, R:{r2})")
    else:
        feedback.append("PKS 0502+049 data missing")

    # Criterion 3: GB6 J0512+0529 (20 pts)
    v3, r3 = count_filters("GB6_J0512+0529")
    if v3 >= req_exp and r3 >= req_exp:
        score += 20
        feedback.append(f"GB6 J0512+0529 data complete (V:{v3}, R:{r3})")
    elif v3 >= 1 or r3 >= 1:
        score += 10
        feedback.append(f"GB6 J0512+0529 data partial (V:{v3}, R:{r3})")
    else:
        feedback.append("GB6 J0512+0529 data missing")

    # ── Evaluate DSS Reference PNGs ───────────────────────────────────
    png_files = result.get('png_files', [])
    valid_pngs = [p for p in png_files
                  if p.get('mtime', 0) > task_start and p.get('size', 0) > 10240]

    png_candidates_found = set()
    for p in valid_pngs:
        c_folder = p.get('candidate', '').replace("_", "")
        for c in CANDIDATES:
            if c.replace("_", "") in c_folder:
                png_candidates_found.add(c)

    png_count = len(png_candidates_found)
    if png_count == 3:
        score += 20
        feedback.append("DSS reference PNGs generated for all 3 candidates")
    elif png_count > 0:
        score += (png_count * 6)
        feedback.append(f"DSS reference PNGs generated for {png_count}/3 candidates")
    else:
        feedback.append("DSS reference PNGs missing")

    # ── Evaluate GCN Circular Draft ───────────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')

    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            mentions = 0
            if "TXS" in report_text or "0506" in report_text:
                mentions += 1
            if "PKS" in report_text or "0502" in report_text:
                mentions += 1
            if "GB6" in report_text or "0512" in report_text:
                mentions += 1

            if mentions == 3:
                score += 20
                feedback.append("GCN circular drafted and mentions all 3 targets")
            elif mentions > 0:
                score += 10
                feedback.append(f"GCN circular drafted but only mentions {mentions}/3 targets")
            else:
                score += 5
                feedback.append("GCN circular drafted but target names missing")
        except Exception as e:
            feedback.append("GCN circular unreadable")
    else:
        feedback.append("GCN circular draft missing or not created during task")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }