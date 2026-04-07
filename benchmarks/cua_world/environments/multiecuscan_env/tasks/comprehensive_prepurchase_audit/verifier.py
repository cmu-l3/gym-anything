#!/usr/bin/env python3
"""
Real verifier for comprehensive_prepurchase_audit task.

Scoring breakdown (100 pts total):
  - Report created after task start (anti-gaming gate): required
  - Vehicle identified (Ducato / VIN / registration): 5 pts
  - Engine ECU section present: 15 pts
  - Transmission section present: 10 pts
  - ABS/Braking section present: 10 pts
  - Body Computer section present: 10 pts
  - Airbag/SRS section present: 10 pts
    → Bonus: all 5 systems covered: +5 pts
  - DTC severity classification (CRITICAL/MAJOR/MINOR): 15 pts
  - Risk score (0-100) present: 10 pts
  - Final verdict (RECOMMENDED/CONDITIONAL/NOT RECOMMENDED): 10 pts

Pass threshold: 65 / 100
"""

import json
import os
import tempfile


def verify_comprehensive_prepurchase_audit(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    result_path_in_vm = r"C:\Users\Docker\comprehensive_prepurchase_audit_result.json"

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
            "feedback": f"Export file not found — agent likely did not complete the task. ({e})",
        }

    # ── Anti-gaming gate ─────────────────────────────────────────────────────
    report_mtime  = int(result.get("report_file_mtime", 0))
    start_ts      = int(result.get("start_timestamp", 0))
    report_exists = result.get("report_exists", False)

    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not created."}

    if start_ts > 0 and report_mtime <= start_ts:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report predates task start — likely pre-existing file.",
        }

    # ── Scoring ──────────────────────────────────────────────────────────────

    # 1. Vehicle identification (5 pts)
    if result.get("vehicle_id_present"):
        score += 5
        feedback_lines.append("+ Vehicle identified (Ducato / VIN / registration) (+5)")
    else:
        feedback_lines.append("- Vehicle not clearly identified (0/5)")

    # 2. Engine ECU section (15 pts)
    if result.get("has_engine_section"):
        score += 15
        feedback_lines.append("+ Engine ECU section present (+15)")
    else:
        feedback_lines.append("- Engine ECU section missing (0/15)")

    # 3. Transmission section (10 pts)
    if result.get("has_transmission_section"):
        score += 10
        feedback_lines.append("+ Transmission/Gearbox section present (+10)")
    else:
        feedback_lines.append("- Transmission section missing (0/10)")

    # 4. ABS/Braking section (10 pts)
    if result.get("has_abs_section"):
        score += 10
        feedback_lines.append("+ ABS/Braking section present (+10)")
    else:
        feedback_lines.append("- ABS/Braking section missing (0/10)")

    # 5. Body Computer section (10 pts)
    if result.get("has_body_computer_section"):
        score += 10
        feedback_lines.append("+ Body Computer section present (+10)")
    else:
        feedback_lines.append("- Body Computer section missing (0/10)")

    # 6. Airbag/SRS section (10 pts)
    if result.get("has_airbag_section"):
        score += 10
        feedback_lines.append("+ Airbag/SRS section present (+10)")
    else:
        feedback_lines.append("- Airbag/SRS section missing (0/10)")

    # 7. All 5 systems covered bonus (5 pts)
    sys_count = int(result.get("systems_covered_count", 0))
    if sys_count >= 5:
        score += 5
        feedback_lines.append(f"+ All 5 systems covered (+5 bonus)")
    elif sys_count >= 3:
        feedback_lines.append(f"~ {sys_count}/5 systems covered (no bonus, need all 5)")
    else:
        feedback_lines.append(f"- Only {sys_count}/5 systems covered")

    # 8. DTC severity classification (15 pts)
    if result.get("has_dtc_classification"):
        pts = 15
        if result.get("has_critical_mention") and result.get("has_major_mention"):
            feedback_lines.append("+ DTC severity classification with CRITICAL + MAJOR categories (+15)")
        elif result.get("has_critical_mention") or result.get("has_major_mention"):
            pts = 10
            feedback_lines.append("+ Partial DTC classification (CRITICAL or MAJOR, not both) (+10)")
        else:
            pts = 8
            feedback_lines.append("+ Some DTC classification present (+8)")
        score += pts
    else:
        feedback_lines.append("- No DTC severity classification (CRITICAL/MAJOR/MINOR) found (0/15)")

    # 9. Risk score (10 pts)
    if result.get("has_risk_score"):
        score += 10
        rv = result.get("risk_score_value", -1)
        if rv >= 0:
            feedback_lines.append(f"+ Risk score present: {rv}/100 (+10)")
        else:
            feedback_lines.append("+ Risk score mentioned (+10)")
    else:
        feedback_lines.append("- No overall risk score (0-100) found (0/10)")

    # 10. Final verdict (10 pts)
    if result.get("has_verdict"):
        score += 10
        verdict = result.get("verdict_value", "")
        feedback_lines.append(f"+ Final verdict present: {verdict} (+10)")
    else:
        feedback_lines.append("- No RECOMMENDED/NOT RECOMMENDED verdict (0/10)")

    score = min(score, 100)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
