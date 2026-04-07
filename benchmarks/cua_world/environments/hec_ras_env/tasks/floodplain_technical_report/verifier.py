"""
Verifier stub: floodplain_technical_report
Occupation: Civil Engineer / Hydraulic Engineer (O*NET 17-2051.00)
Task: Produce floodplain profile, infrastructure impact assessment,
      and flow sensitivity check (1.5x boundary condition scaling).

This is a stub verifier. Full verification is handled by the
vlm_checklist_verifier. Basic structural checks are performed here.

Scoring rubric (100 pts total):
  10 pts - floodplain_profile.csv exists with correct 6-column header
  15 pts - Profile CSV has plausible cross-section data (row count, WSE range)
  10 pts - infrastructure_impact.csv exists with correct 6-column header
  10 pts - Infrastructure CSV has correct number of rows (8 facilities)
  15 pts - Sensitivity check performed (b04 modified AND simulation re-run)
  10 pts - Sensitivity deltas present and all positive (higher flow -> higher WSE)
  10 pts - report_summary.txt exists with all 6 labeled lines
  10 pts - Flood depths internally consistent (WSE - Bed_Elev)
  10 pts - Summary stats consistent with CSV data

Pass threshold: 60 pts
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

WSE_MIN = 930.0
WSE_MAX = 965.0
VEL_MIN = 0.0
VEL_MAX = 25.0
BED_MIN = 910.0
BED_MAX = 945.0


def verify_floodplain_technical_report(traj, env_info, task_info):
    if not callable(env_info.get("copy_from_env")):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}
    copy_fn = env_info["copy_from_env"]

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_fn("/tmp/floodplain_result.json", tmp.name)
        data = json.loads(open(tmp.name).read())
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0,
                "feedback": f"Export result not found: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    # Load ground truth
    gt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    gt_tmp.close()
    gt = {}
    try:
        copy_fn("/tmp/floodplain_gt.json", gt_tmp.name)
        gt = json.loads(open(gt_tmp.name).read())
    except Exception:
        pass
    finally:
        try:
            os.unlink(gt_tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # ── 1. Profile CSV existence and header (10 pts) ──
    if data.get("profile_csv_exists") and data.get("profile_has_header"):
        score += 10
        feedback.append("PASS(10): floodplain_profile.csv exists with correct headers")
    elif data.get("profile_csv_exists"):
        score += 3
        feedback.append("PARTIAL(3): profile CSV exists but header wrong/missing")
    else:
        feedback.append("FAIL(0): floodplain_profile.csv not found")

    # ── 2. Profile data plausibility (15 pts) ──
    profile_rows = data.get("profile_rows", [])
    expected_xs = gt.get("num_cross_sections", 0)
    if profile_rows:
        n_rows = len(profile_rows)
        # Check row count
        count_ok = (expected_xs > 0 and abs(n_rows - expected_xs) <= 2) or n_rows >= 10
        # Check WSE range
        wse_vals = [r.get("Peak_WSE_ft", 0) for r in profile_rows]
        wse_plausible = all(WSE_MIN <= w <= WSE_MAX for w in wse_vals) if wse_vals else False
        # Check velocity range
        vel_vals = [r.get("Max_Velocity_fps", 0) for r in profile_rows]
        vel_plausible = all(VEL_MIN <= v <= VEL_MAX for v in vel_vals) if vel_vals else False

        if count_ok and wse_plausible and vel_plausible:
            score += 15
            feedback.append(f"PASS(15): Profile has {n_rows} rows, WSE and velocity plausible")
        elif count_ok and wse_plausible:
            score += 10
            feedback.append(f"PARTIAL(10): Profile has {n_rows} rows, WSE plausible, velocity issues")
        elif wse_plausible:
            score += 5
            feedback.append(f"PARTIAL(5): WSE plausible but row count {n_rows} vs expected {expected_xs}")
        else:
            feedback.append(f"FAIL(0): Profile data implausible (rows={n_rows}, WSE range issues)")
    else:
        feedback.append("FAIL(0): No profile data rows found")

    # ── 3. Infrastructure CSV existence and header (10 pts) ──
    if data.get("infra_csv_exists") and data.get("infra_has_header"):
        score += 10
        feedback.append("PASS(10): infrastructure_impact.csv exists with correct headers")
    elif data.get("infra_csv_exists"):
        score += 3
        feedback.append("PARTIAL(3): infrastructure CSV exists but header wrong/missing")
    else:
        feedback.append("FAIL(0): infrastructure_impact.csv not found")

    # ── 4. Infrastructure row count (10 pts) ──
    infra_rows = data.get("infra_rows", [])
    if len(infra_rows) == 8:
        score += 10
        feedback.append("PASS(10): Infrastructure CSV has all 8 facility rows")
    elif len(infra_rows) >= 5:
        score += 5
        feedback.append(f"PARTIAL(5): Infrastructure CSV has {len(infra_rows)}/8 rows")
    elif len(infra_rows) > 0:
        score += 2
        feedback.append(f"PARTIAL(2): Infrastructure CSV has only {len(infra_rows)} rows")
    else:
        feedback.append("FAIL(0): No infrastructure data rows")

    # ── 5. Sensitivity check evidence (15 pts) ──
    if data.get("b04_modified") and data.get("hdf_modified_after_start"):
        score += 15
        feedback.append("PASS(15): b04 modified AND simulation re-run (sensitivity performed)")
    elif data.get("b04_modified") or data.get("hdf_modified_after_start"):
        score += 7
        feedback.append("PARTIAL(7): Partial sensitivity evidence (b04 or sim, not both)")
    else:
        feedback.append("FAIL(0): No evidence of sensitivity analysis (b04 unmodified, no re-run)")

    # ── 6. Sensitivity deltas positive (10 pts) ──
    if profile_rows:
        deltas = [r.get("Sensitivity_Delta_WSE_ft") for r in profile_rows
                  if r.get("Sensitivity_Delta_WSE_ft") is not None]
        if deltas:
            all_positive = all(d > -0.01 for d in deltas)  # small tolerance
            any_nonzero = any(abs(d) > 0.001 for d in deltas)
            if all_positive and any_nonzero:
                score += 10
                feedback.append(f"PASS(10): Sensitivity deltas all non-negative ({len(deltas)} values)")
            elif any_nonzero:
                score += 4
                feedback.append("PARTIAL(4): Sensitivity deltas present but some negative")
            else:
                feedback.append("FAIL(0): Sensitivity deltas all zero (simulation may not have rerun)")
        else:
            feedback.append("FAIL(0): No sensitivity delta values found in profile CSV")
    else:
        feedback.append("FAIL(0): Cannot check sensitivity deltas (no profile data)")

    # ── 7. Summary file with labeled lines (10 pts) ──
    expected_labels = ["NUM_CROSS_SECTIONS", "MAX_FLOOD_DEPTH_FT",
                       "MAX_FLOOD_DEPTH_STATION", "FACILITIES_FLOODED",
                       "FACILITIES_SAFE", "MAX_SENSITIVITY_DELTA_FT"]
    summary_vals = data.get("summary_values", {})
    if data.get("summary_exists"):
        found = sum(1 for lab in expected_labels if lab in summary_vals)
        if found == 6:
            score += 10
            feedback.append("PASS(10): Summary has all 6 labeled lines")
        elif found >= 4:
            score += 6
            feedback.append(f"PARTIAL(6): Summary has {found}/6 labeled lines")
        elif found >= 1:
            score += 3
            feedback.append(f"PARTIAL(3): Summary has only {found}/6 labeled lines")
        else:
            feedback.append("FAIL(0): Summary exists but no labeled lines found")
    else:
        feedback.append("FAIL(0): report_summary.txt not found")

    # ── 8. Flood depth internal consistency (10 pts) ──
    if profile_rows:
        consistent = 0
        total = 0
        for r in profile_rows:
            wse = r.get("Peak_WSE_ft")
            bed = r.get("Bed_Elev_ft")
            depth = r.get("Flood_Depth_ft")
            if wse is not None and bed is not None and depth is not None:
                total += 1
                expected_depth = wse - bed
                if abs(depth - expected_depth) < 0.15:
                    consistent += 1
        if total > 0 and consistent / total > 0.9:
            score += 10
            feedback.append(f"PASS(10): Flood depths consistent ({consistent}/{total})")
        elif total > 0 and consistent / total > 0.5:
            score += 5
            feedback.append(f"PARTIAL(5): Flood depths partially consistent ({consistent}/{total})")
        else:
            feedback.append(f"FAIL(0): Flood depths inconsistent ({consistent}/{total})")
    else:
        feedback.append("FAIL(0): Cannot check flood depth consistency (no profile data)")

    # ── 9. Summary stats match CSV data (10 pts) ──
    match_count = 0
    if summary_vals and profile_rows and infra_rows:
        # Check NUM_CROSS_SECTIONS
        if "NUM_CROSS_SECTIONS" in summary_vals:
            if int(summary_vals["NUM_CROSS_SECTIONS"]) == len(profile_rows):
                match_count += 1
        # Check FACILITIES_FLOODED
        if "FACILITIES_FLOODED" in summary_vals:
            actual_flooded = sum(1 for r in infra_rows if r.get("Status") == "FLOODED")
            if int(summary_vals["FACILITIES_FLOODED"]) == actual_flooded:
                match_count += 1
        # Check FACILITIES_SAFE
        if "FACILITIES_SAFE" in summary_vals:
            actual_safe = sum(1 for r in infra_rows if r.get("Status") == "SAFE")
            if int(summary_vals["FACILITIES_SAFE"]) == actual_safe:
                match_count += 1

        if match_count >= 3:
            score += 10
            feedback.append("PASS(10): Summary statistics match CSV data")
        elif match_count >= 1:
            score += 5
            feedback.append(f"PARTIAL(5): {match_count}/3 summary stats match CSV data")
        else:
            feedback.append("FAIL(0): Summary statistics do not match CSV data")
    else:
        feedback.append("FAIL(0): Cannot verify summary consistency (missing data)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
