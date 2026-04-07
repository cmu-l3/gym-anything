#!/usr/bin/env python3
"""
Real verifier for fleet_health_priority_matrix task.

Scoring breakdown (100 pts total):
  - Report created after task start (anti-gaming gate): required
  - Vehicle A section present (Punto CNG): 15 pts
  - Vehicle B section present (Giulietta MultiAir): 15 pts
  - Vehicle C section present (Ducato diesel): 15 pts
    → All 3 vehicles covered bonus: +5 pts
  - ECU identification present for at least one vehicle: 10 pts
  - Live parameters documented: 5 pts
  - Comparison table present: 10 pts
  - Priority ranking (Rank 1/2/3) present: 15 pts
  - Pre-service actions per vehicle: 10 pts

Pass threshold: 65 / 100
"""

import json
import os
import tempfile


def verify_fleet_health_priority_matrix(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    result_path_in_vm = r"C:\Users\Docker\fleet_health_priority_matrix_result.json"

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

    # 1. Vehicle A (Punto CNG) section (15 pts)
    if result.get("has_vehicle_a_section"):
        score += 15
        feedback_lines.append("+ Vehicle A (Fiat Punto CNG) section present (+15)")
    else:
        feedback_lines.append("- Vehicle A (Punto CNG / FP14) section missing (0/15)")

    # 2. Vehicle B (Giulietta MultiAir) section (15 pts)
    if result.get("has_vehicle_b_section"):
        score += 15
        feedback_lines.append("+ Vehicle B (Alfa Romeo Giulietta MultiAir) section present (+15)")
    else:
        feedback_lines.append("- Vehicle B (Giulietta / AR13) section missing (0/15)")

    # 3. Vehicle C (Ducato diesel) section (15 pts)
    if result.get("has_vehicle_c_section"):
        score += 15
        feedback_lines.append("+ Vehicle C (Fiat Ducato 2.3 Multijet) section present (+15)")
    else:
        feedback_lines.append("- Vehicle C (Ducato / FD16) section missing (0/15)")

    # 4. All 3 vehicles covered bonus (5 pts)
    veh_count = int(result.get("vehicles_covered_count", 0))
    if veh_count >= 3:
        score += 5
        feedback_lines.append("+ All 3 vehicles covered (+5 bonus)")
    else:
        feedback_lines.append(f"- Only {veh_count}/3 vehicles covered (no bonus)")

    # 5. ECU identification (10 pts)
    if result.get("has_ecu_info_any"):
        score += 10
        feedback_lines.append("+ ECU identification (part number / HW / SW) present (+10)")
    else:
        feedback_lines.append("- No ECU identification found (0/10)")

    # 6. Live parameters (5 pts)
    if result.get("has_parameters_any"):
        score += 5
        feedback_lines.append("+ Engine parameters documented (+5)")
    else:
        feedback_lines.append("- No engine parameter readings found (0/5)")

    # 7. Comparison table (10 pts)
    if result.get("has_comparison_table"):
        score += 10
        feedback_lines.append("+ Side-by-side comparison table present (+10)")
    else:
        feedback_lines.append("- No comparison table (0/10)")

    # 8. Priority ranking (15 pts)
    if result.get("has_priority_ranking"):
        score += 15
        rank1 = result.get("priority_rank1_vehicle", "")
        if rank1:
            feedback_lines.append(f"+ Priority ranking present — Rank 1: {rank1} (+15)")
        else:
            feedback_lines.append("+ Priority ranking present (+15)")
    else:
        feedback_lines.append("- No priority ranking (Rank 1/2/3) found (0/15)")

    # 9. Pre-service actions (10 pts)
    if result.get("has_preservice_actions"):
        score += 10
        feedback_lines.append("+ Pre-service actions documented (+10)")
    else:
        feedback_lines.append("- No pre-service actions found (0/10)")

    score = min(score, 100)
    passed = score >= 65

    # DTC summary in feedback
    all_dtcs = result.get("all_dtcs_found", [])
    if all_dtcs:
        feedback_lines.append(f"\nDTCs found across all vehicles: {', '.join(all_dtcs[:10])}")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }
