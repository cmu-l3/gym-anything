#!/usr/bin/env python3
"""
Real verifier for turbo_vgt_actuator_root_cause task.

Scoring breakdown (100 pts total):
  - Report created after task start (anti-gaming gate): required
  - ECU / vehicle identification section present: 10 pts
  - DTC section present (any codes or "no faults"): 10 pts
  - Boost pressure parameter monitored: 15 pts
  - MAF (mass air flow) parameter monitored: 10 pts
  - EGR-related parameter or DTC mentioned: 10 pts
  - >=4 live parameters total: 10 pts
  - Root cause section present: 15 pts
  - Specific root cause identified (one of 5 categories): 10 pts
  - Repair recommendations present: 10 pts

Pass threshold: 65 / 100
"""

import json
import os
import tempfile


def verify_turbo_vgt_actuator_root_cause(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    result_path_in_vm = r"C:\Users\Docker\turbo_vgt_actuator_root_cause_result.json"

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

    # 1. ECU / vehicle identification (10 pts)
    if result.get("has_ecu_section") and result.get("vehicle_id_present"):
        score += 10
        feedback_lines.append("+ Vehicle/ECU identification present (+10)")
    elif result.get("has_ecu_section"):
        score += 5
        feedback_lines.append("+ ECU section present but vehicle ID unclear (+5)")
    else:
        feedback_lines.append("- Missing ECU/vehicle identification (0/10)")

    # 2. DTC section (10 pts)
    if result.get("has_dtc_section"):
        score += 10
        dtcs = result.get("all_dtc_codes_found", [])
        turbo_dtcs = result.get("turbo_dtcs_found", [])
        msg = f"+ DTC section present"
        if dtcs:
            msg += f" — {len(dtcs)} code(s): {', '.join(dtcs[:5])}"
        if turbo_dtcs:
            msg += f" — turbo DTCs: {', '.join(turbo_dtcs)}"
        feedback_lines.append(msg + " (+10)")
    else:
        feedback_lines.append("- No DTC section found (0/10)")

    # 3. Boost pressure parameter (15 pts)
    if result.get("has_boost_parameters"):
        score += 15
        feedback_lines.append("+ Boost pressure parameter monitored (+15)")
    else:
        feedback_lines.append("- Boost pressure not mentioned — critical for turbo diagnosis (0/15)")

    # 4. MAF parameter (10 pts)
    if result.get("has_maf_parameter"):
        score += 10
        feedback_lines.append("+ Mass Air Flow (MAF) parameter monitored (+10)")
    else:
        feedback_lines.append("- MAF sensor not mentioned (0/10)")

    # 5. EGR parameter or DTC (10 pts)
    if result.get("has_egr_parameter"):
        score += 10
        feedback_lines.append("+ EGR system mentioned (+10)")
    else:
        feedback_lines.append("- EGR system not mentioned (0/10)")

    # 6. Total live parameter count >=4 (10 pts)
    param_count = int(result.get("live_parameters_count", 0))
    if param_count >= 4:
        score += 10
        feedback_lines.append(f"+ {param_count} live parameters documented (+10)")
    elif param_count >= 2:
        score += 5
        feedback_lines.append(f"+ {param_count} live parameters documented (+5)")
    else:
        feedback_lines.append(f"- Only {param_count} live parameter(s) found (0/10)")

    # 7. Root cause section present (15 pts)
    if result.get("has_root_cause_section"):
        score += 15
        feedback_lines.append("+ Root cause analysis section present (+15)")
    else:
        feedback_lines.append("- No root cause analysis section found (0/15)")

    # 8. Specific root cause identified (10 pts)
    rca = result.get("root_cause_identified", "")
    if rca:
        score += 10
        feedback_lines.append(f"+ Specific root cause identified: {rca} (+10)")
    else:
        feedback_lines.append("- No specific root cause category identified (0/10)")

    # 9. Repair recommendations (10 pts)
    if result.get("has_repair_recommendations"):
        score += 10
        feedback_lines.append("+ Repair recommendations present (+10)")
    else:
        feedback_lines.append("- No repair recommendations (0/10)")

    score = min(score, 100)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
