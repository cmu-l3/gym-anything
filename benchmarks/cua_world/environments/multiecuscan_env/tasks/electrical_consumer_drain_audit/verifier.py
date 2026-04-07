#!/usr/bin/env python3
"""
Real verifier for electrical_consumer_drain_audit task.

Scoring breakdown (100 pts total):
  - Report created after task start (anti-gaming gate): required
  - Vehicle identified (500L / VIN / registration): 5 pts
  - Body Computer (BSI/BCM) section present: 20 pts
  - Engine ECU section present: 15 pts
  - BOTH systems covered: bonus +5 pts (max 40 for both sections)
  - DTC section present with codes or "no faults": 10 pts
  - Battery voltage parameter recorded: 10 pts
  - CAN bus / network fault mentioned: 5 pts
  - Ranked suspect module list: 15 pts
  - Next diagnostic steps / fuse pull test: 15 pts
  - At least one specific suspect module named: 5 pts

Pass threshold: 65 / 100
"""

import json
import os
import tempfile


def verify_electrical_consumer_drain_audit(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    result_path_in_vm = r"C:\Users\Docker\electrical_consumer_drain_audit_result.json"

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
        feedback_lines.append("+ Vehicle identified (Fiat 500L / VIN / registration) (+5)")
    else:
        feedback_lines.append("- Vehicle not clearly identified in report (0/5)")

    # 2. Body Computer section (20 pts)
    if result.get("has_body_computer_section"):
        score += 20
        feedback_lines.append("+ Body Computer (BSI/BCM) section present (+20)")
    else:
        feedback_lines.append("- Body Computer / BSI section missing — this is the PRIMARY system to check (0/20)")

    # 3. Engine ECU section (15 pts)
    if result.get("has_engine_ecu_section"):
        score += 15
        feedback_lines.append("+ Engine ECU section present (+15)")
    else:
        feedback_lines.append("- Engine ECU section missing (0/15)")

    # 4. Both systems covered bonus (5 pts)
    if result.get("both_systems_covered"):
        score += 5
        feedback_lines.append("+ Both systems (Body Computer + Engine ECU) covered (+5 bonus)")

    # 5. DTC section (10 pts)
    if result.get("has_dtc_section"):
        score += 10
        dtcs = result.get("all_dtcs_found", [])
        if dtcs:
            feedback_lines.append(f"+ DTC section with {len(dtcs)} code(s): {', '.join(dtcs[:6])} (+10)")
        else:
            feedback_lines.append("+ DTC section present (no faults found) (+10)")
    else:
        feedback_lines.append("- No DTC section found (0/10)")

    # 6. Battery voltage parameter (10 pts)
    if result.get("has_battery_voltage_param"):
        score += 10
        feedback_lines.append("+ Battery voltage parameter recorded (+10)")
    else:
        feedback_lines.append("- Battery voltage not recorded — important for drain diagnosis (0/10)")

    # 7. CAN bus / network fault (5 pts)
    if result.get("has_can_fault_mention"):
        score += 5
        feedback_lines.append("+ CAN bus / network communication addressed (+5)")
    else:
        feedback_lines.append("- CAN bus network faults not addressed (0/5)")

    # 8. Ranked suspect list (15 pts)
    if result.get("has_suspect_list"):
        score += 15
        suspects = result.get("suspect_modules", [])
        if suspects:
            feedback_lines.append(f"+ Ranked suspect list with modules: {', '.join(suspects)} (+15)")
        else:
            feedback_lines.append("+ Suspect list present (+15)")
    else:
        feedback_lines.append("- No ranked suspect list found (0/15)")

    # 9. Next diagnostic steps / fuse pull test (15 pts)
    next_pts = 0
    if result.get("has_next_steps"):
        next_pts += 8
    if result.get("has_fuse_test_mention"):
        next_pts += 7
    score += next_pts
    if next_pts >= 10:
        feedback_lines.append(f"+ Diagnostic procedure / fuse test sequence described (+{next_pts})")
    elif next_pts > 0:
        feedback_lines.append(f"+ Some next steps mentioned (+{next_pts}/15)")
    else:
        feedback_lines.append("- No next diagnostic steps or fuse test sequence (0/15)")

    # 10. Specific suspect module named (5 pts)
    suspects = result.get("suspect_modules", [])
    if len(suspects) >= 1:
        score += 5
        feedback_lines.append(f"+ Specific suspect module(s) named: {', '.join(suspects[:3])} (+5)")

    score = min(score, 100)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
