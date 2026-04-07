#!/usr/bin/env python3
"""
Real verifier for emissions_readiness_assessment task.

Scoring breakdown (100 pts total):
  - Report created after task start (anti-gaming gate): required
  - ECU / vehicle identification section present: 10 pts
  - Readiness monitor table present (>=3 monitors mentioned): 20 pts
  - Catalyst monitor explicitly addressed: 10 pts
  - DTC section present (even "no faults" is valid): 15 pts
  - MOT/emissions verdict present (READY/NOT READY/CONDITIONAL): 15 pts
  - Drive cycle guidance for incomplete monitors: 15 pts
  - EVAP monitor mentioned: 5 pts
  - O2/lambda sensor monitor mentioned: 5 pts
  - MOT-specific reference (mentions UK test or MOT rules): 5 pts

Pass threshold: 65 / 100
"""

import json
import os
import tempfile


def verify_emissions_readiness_assessment(traj, env_info, task_info):
    score = 0
    feedback_lines = []
    passed = False

    result_path_in_vm = r"C:\Users\Docker\emissions_readiness_assessment_result.json"

    # ── Pull result file from VM ─────────────────────────────────────────────
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        env_info["copy_from_env"](result_path_in_vm, local_path)
        with open(local_path, encoding="utf-8-sig") as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found or unreadable — agent likely did not complete the task. ({e})",
        }

    # ── Anti-gaming gate: report must be created AFTER task started ──────────
    report_mtime = int(result.get("report_file_mtime", 0))
    start_ts     = int(result.get("start_timestamp", 0))
    report_exists = result.get("report_exists", False)

    if not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file was not created. Task not completed.",
        }

    if start_ts > 0 and report_mtime <= start_ts:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file predates task start — likely a pre-existing file, not agent-created.",
        }

    report_is_new = (start_ts == 0) or (report_mtime > start_ts)

    # ── Scoring ──────────────────────────────────────────────────────────────
    raw_content = result.get("report_content", "")
    # Unescape \\n → real newlines (PowerShell JSON serialisation artefact)
    content = raw_content.replace("\\n", "\n").replace("\\t", "\t")

    # 1. ECU / vehicle identification (10 pts)
    if result.get("has_ecu_section") and result.get("vehicle_id_present"):
        score += 10
        feedback_lines.append("+ Vehicle/ECU identification section present (+10)")
    elif result.get("has_ecu_section"):
        score += 5
        feedback_lines.append("+ ECU section present but vehicle ID unclear (+5)")
    else:
        feedback_lines.append("- Missing vehicle/ECU identification section (0/10)")

    # 2. Readiness monitor table with >=3 monitors (20 pts)
    monitors = result.get("readiness_monitors", [])
    if result.get("has_readiness_table") and len(monitors) >= 3:
        score += 20
        feedback_lines.append(f"+ Readiness monitor table with {len(monitors)} monitors (+20)")
    elif result.get("has_readiness_table") and len(monitors) >= 1:
        score += 10
        feedback_lines.append(f"+ Readiness table present but only {len(monitors)} monitor(s) (+10)")
    else:
        feedback_lines.append("- No readiness monitor table found (0/20)")

    # 3. Catalyst monitor explicitly addressed (10 pts)
    if result.get("catalyst_monitor_mentioned"):
        score += 10
        feedback_lines.append("+ Catalyst monitor explicitly mentioned (+10)")
    else:
        feedback_lines.append("- Catalyst monitor not mentioned — critical for MOT (0/10)")

    # 4. DTC section (15 pts)
    if result.get("has_dtc_section"):
        score += 15
        dtcs = result.get("dtc_codes_found", [])
        if dtcs:
            feedback_lines.append(f"+ DTC section present with {len(dtcs)} code(s): {', '.join(dtcs[:5])} (+15)")
        else:
            feedback_lines.append("+ DTC section present (no faults reported) (+15)")
    else:
        feedback_lines.append("- No DTC section found (0/15)")

    # 5. MOT/emissions verdict (15 pts)
    if result.get("has_verdict"):
        verdict = result.get("verdict_value", "")
        score += 15
        feedback_lines.append(f"+ MOT readiness verdict present: {verdict} (+15)")
    else:
        feedback_lines.append("- No clear READY/NOT READY/CONDITIONAL verdict (0/15)")

    # 6. Drive cycle guidance (15 pts)
    if result.get("has_drive_cycle"):
        score += 15
        feedback_lines.append("+ Drive cycle guidance for incomplete monitors (+15)")
    else:
        feedback_lines.append("- No drive cycle guidance for completing readiness monitors (0/15)")

    # 7. EVAP monitor mentioned (5 pts)
    if result.get("evap_monitor_mentioned"):
        score += 5
        feedback_lines.append("+ EVAP monitor mentioned (+5)")

    # 8. O2/lambda sensor monitor mentioned (5 pts)
    if result.get("o2_sensor_mentioned"):
        score += 5
        feedback_lines.append("+ O2/lambda sensor monitor mentioned (+5)")

    # 9. MOT-specific regulatory reference (5 pts)
    if result.get("mot_reference"):
        score += 5
        feedback_lines.append("+ MOT / UK regulations explicitly referenced (+5)")

    # ── Final result ─────────────────────────────────────────────────────────
    score = min(score, 100)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
