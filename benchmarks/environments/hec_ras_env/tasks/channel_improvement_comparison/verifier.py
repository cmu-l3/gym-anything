"""
Verifier: channel_improvement_comparison
Occupation: Environmental Engineer (O*NET 17-2081.00)
Task: Two-scenario hydraulic comparison — baseline vs. improved channel conditions.

Scoring rubric (100 pts total):
  10 pts — Two simulations run (HDF5 modified after task start, both JSONs exist)
  15 pts — baseline_results.json and improved_results.json exist with plausible values
  20 pts — Baseline peak WSE within ±0.5 ft of GT baseline
  20 pts — Improved conditions show WSE reduction (improved < baseline, per GT direction)
  20 pts — scenario_comparison.csv correct: 2 rows, 6 columns, correct flood_reduction_pct
  15 pts — project_benefit_summary.txt exists with ≥5 sentences and design criterion assessment

Pass threshold: 60 pts
Wrong-target gate: If neither baseline nor improved JSON exists AND CSV missing, score=0.
Score cap: If only baseline JSON exists (no improved sim), cap score at 50.
"""
import json, logging, os, tempfile

logger = logging.getLogger(__name__)

WSE_TOLERANCE  = 0.5   # ft
PCT_TOLERANCE  = 5.0   # percentage points for flood_reduction_pct


def verify_channel_improvement_comparison(traj, env_info, task_info):
    if not callable(env_info.get("copy_from_env")):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}
    copy_fn = env_info["copy_from_env"]

    # --- GT ---
    gt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    gt_tmp.close()
    try:
        copy_fn("/tmp/channelimp_gt.json", gt_tmp.name)
        gt = json.loads(open(gt_tmp.name).read())
    except Exception as e:
        os.unlink(gt_tmp.name)
        return {"passed": False, "score": 0, "feedback": f"GT not found: {e}"}
    finally:
        try: os.unlink(gt_tmp.name)
        except Exception: pass

    gt_baseline_peak = gt["baseline_peak_wse"]
    gt_improved_peak = gt["improved_peak_wse"]
    gt_flood_red_pct = gt["flood_reduction_pct"]

    # --- Agent result ---
    res_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    res_tmp.close()
    try:
        copy_fn("/tmp/channelimp_result.json", res_tmp.name)
        data = json.loads(open(res_tmp.name).read())
    except Exception as e:
        os.unlink(res_tmp.name)
        return {"passed": False, "score": 0, "feedback": f"Export result not found: {e}"}
    finally:
        try: os.unlink(res_tmp.name)
        except Exception: pass

    score = 0
    feedback = []

    # ── Wrong-target gate ──
    has_any_output = (data.get("baseline_json_exists") or
                      data.get("improved_json_exists") or
                      data.get("comparison_csv_exists"))
    if not has_any_output:
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: No output files produced — agent took no action"}

    # ── Score cap: if improved sim not run, cap at 50 ──
    improved_sim_run = data.get("improved_json_exists") and data.get("hdf_modified_after_start")

    # ── Criterion 1: Two sims run ──
    hdf_mod   = data.get("hdf_modified_after_start", False)
    both_jsons = data.get("baseline_json_exists") and data.get("improved_json_exists")
    if hdf_mod and both_jsons:
        score += 10
        feedback.append("PASS(10): HDF5 updated and both result JSONs exist — two simulations run")
    elif data.get("baseline_json_exists") or hdf_mod:
        score += 4
        feedback.append("PARTIAL(4): Evidence of at least one simulation; second may be missing")
    else:
        feedback.append("FAIL(0): No evidence of any simulation run")

    # ── Criterion 2: Both JSONs with plausible values ──
    b_peak = data.get("baseline_peak_wse")
    i_peak = data.get("improved_peak_wse")
    b_plausible = b_peak is not None and 935.0 < b_peak < 965.0
    i_plausible = i_peak is not None and 935.0 < i_peak < 965.0
    if b_plausible and i_plausible:
        score += 15
        feedback.append(f"PASS(15): Both JSONs have plausible WSE values (baseline={b_peak:.2f} ft, improved={i_peak:.2f} ft)")
    elif b_plausible or i_plausible:
        score += 7
        feedback.append(f"PARTIAL(7): One plausible WSE found (baseline={b_peak}, improved={i_peak})")
    else:
        feedback.append(f"FAIL(0): JSON WSE values implausible (baseline={b_peak}, improved={i_peak})")

    # ── Criterion 3: Baseline WSE within ±0.5 ft of GT ──
    if b_peak is not None:
        diff = abs(b_peak - gt_baseline_peak)
        if diff <= WSE_TOLERANCE:
            score += 20
            feedback.append(f"PASS(20): Baseline peak WSE={b_peak:.3f} ft matches GT={gt_baseline_peak:.3f} ft (diff={diff:.3f} ft)")
        elif diff <= 1.0:
            score += 10
            feedback.append(f"PARTIAL(10): Baseline WSE={b_peak:.3f} ft vs GT={gt_baseline_peak:.3f} ft (diff={diff:.3f} ft, within 1 ft)")
        else:
            feedback.append(f"FAIL(0): Baseline WSE={b_peak:.3f} ft vs GT={gt_baseline_peak:.3f} ft (diff={diff:.3f} ft)")
    else:
        feedback.append(f"FAIL(0): No baseline WSE found in results")

    # ── Criterion 4: Improved conditions show WSE reduction in correct direction ──
    if b_peak is not None and i_peak is not None:
        wse_reduction = b_peak - i_peak
        gt_wse_reduction = gt_baseline_peak - gt_improved_peak
        correct_direction = wse_reduction > 0  # improved should be lower
        reduction_plausible = 0 < wse_reduction < gt_wse_reduction * 2.0  # within 2× GT
        if correct_direction and reduction_plausible:
            score += 20
            feedback.append(f"PASS(20): Improved WSE={i_peak:.3f} ft < baseline={b_peak:.3f} ft; reduction={wse_reduction:.3f} ft (GT reduction={gt_wse_reduction:.3f} ft)")
        elif correct_direction:
            score += 10
            feedback.append(f"PARTIAL(10): WSE reduction in correct direction ({wse_reduction:.3f} ft) but may not match GT closely")
        else:
            feedback.append(f"FAIL(0): Improved WSE={i_peak} ft is NOT lower than baseline={b_peak} ft — direction wrong")
    else:
        feedback.append(f"FAIL(0): Cannot compare scenarios (missing baseline or improved WSE)")

    # ── Criterion 5: scenario_comparison.csv ──
    if data.get("comparison_csv_exists") and data.get("csv_has_header"):
        csv_rows = data.get("csv_rows", [])
        has_baseline = any("baseline" in str(r.get("scenario","")).lower() for r in csv_rows)
        has_improved = any(any(k in str(r.get("scenario","")).lower() for k in ["improved","improv"]) for r in csv_rows)
        # Check flood_reduction_pct is present and plausible
        red_pct_values = [r.get("flood_reduction_pct") for r in csv_rows if r.get("flood_reduction_pct") is not None]
        red_pct_plausible = any(0 <= v <= 100 for v in red_pct_values)
        if data.get("csv_row_count") == 2 and has_baseline and has_improved and red_pct_plausible:
            score += 20
            feedback.append(f"PASS(20): scenario_comparison.csv has 2 rows (baseline+improved) with plausible flood_reduction_pct")
        elif data.get("csv_row_count") >= 1 and data.get("csv_has_header"):
            score += 10
            feedback.append(f"PARTIAL(10): CSV exists with {data.get('csv_row_count')} row(s), headers correct")
        else:
            score += 5
            feedback.append("PARTIAL(5): scenario_comparison.csv exists but structure incomplete")
    elif data.get("comparison_csv_exists"):
        score += 5
        feedback.append("PARTIAL(5): CSV exists but missing required column headers")
    else:
        feedback.append("FAIL(0): scenario_comparison.csv not found in hec_ras_results/")

    # ── Criterion 6: project_benefit_summary.txt ──
    wc = data.get("summary_word_count", 0)
    has_criterion = data.get("summary_mentions_criterion", False)
    if data.get("summary_exists") and wc >= 80 and has_criterion:
        score += 15
        feedback.append(f"PASS(15): Summary ({wc} words) with design criterion assessment")
    elif data.get("summary_exists") and wc >= 40:
        score += 8
        feedback.append(f"PARTIAL(8): Summary exists ({wc} words) but may lack design criterion")
    elif data.get("summary_exists"):
        score += 4
        feedback.append(f"PARTIAL(4): Summary exists but too brief ({wc} words)")
    else:
        feedback.append("FAIL(0): project_benefit_summary.txt not found")

    # ── Score cap if only baseline sim run ──
    if not improved_sim_run and score > 50:
        score = 50
        feedback.append("CAP(50): Score capped — improved conditions simulation not confirmed")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "baseline_wse": b_peak,
            "improved_wse": i_peak,
            "gt_baseline_wse": gt_baseline_peak,
            "gt_improved_wse": gt_improved_peak,
        }
    }
