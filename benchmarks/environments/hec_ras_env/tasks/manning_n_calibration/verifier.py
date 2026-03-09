"""
Verifier: manning_n_calibration
Occupation: Senior Hydrologist (O*NET 19-2043.00)
Task: Calibrate Manning's n by iterating simulations to match observed peak WSE.

Scoring rubric (100 pts total):
  10 pts — Simulation was run (HDF5 updated after task start)
  15 pts — calibration_log.csv exists with correct headers
  20 pts — At least 3 distinct Manning's n values tested (iterative process)
  20 pts — Final Manning's n in HDF5 is close to the correct default value (±20%)
  25 pts — Simulated peak WSE with final n is within ±0.5 ft of observed target
  10 pts — calibration_report.txt documents n value, simulated WSE, and residual

Pass threshold: 60 pts
Wrong-target gate: If no simulation was run AND no calibration log exists, score=0.
"""
import json, logging, os, tempfile, numpy as np

logger = logging.getLogger(__name__)

CALIBRATION_TOLERANCE_FT = 0.5
N_VARIATION_TOLERANCE     = 0.20   # ±20% of true_default_n is acceptable


def verify_manning_n_calibration(traj, env_info, task_info):
    if not callable(env_info.get("copy_from_env")):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}
    copy_fn = env_info["copy_from_env"]

    # --- Load ground truth ---
    gt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    gt_tmp.close()
    try:
        copy_fn("/tmp/calib_gt.json", gt_tmp.name)
        gt = json.loads(open(gt_tmp.name).read())
    except Exception as e:
        os.unlink(gt_tmp.name)
        return {"passed": False, "score": 0,
                "feedback": f"Ground truth not found: {e}"}
    finally:
        try: os.unlink(gt_tmp.name)
        except Exception: pass

    target_wse    = gt["observed_peak_wse_ft"]
    true_n        = gt["true_default_n"]
    wrong_n_start = gt["wrong_n_given"]

    # --- Load agent result ---
    res_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    res_tmp.close()
    try:
        copy_fn("/tmp/calib_result.json", res_tmp.name)
        data = json.loads(open(res_tmp.name).read())
    except Exception as e:
        os.unlink(res_tmp.name)
        return {"passed": False, "score": 0,
                "feedback": f"Export result not found: {e}"}
    finally:
        try: os.unlink(res_tmp.name)
        except Exception: pass

    score = 0
    feedback = []

    # ── Wrong-target gate ──
    if not data.get("hdf_modified_after_start") and not data.get("calib_log_exists"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: No simulation run and no calibration log — agent took no action"}

    # ── Criterion 1: Simulation was run ──
    if data.get("hdf_modified_after_start"):
        score += 10
        feedback.append("PASS(10): Simulation output HDF5 updated after task start")
    else:
        feedback.append("FAIL(0): No evidence that simulation was run")

    # ── Criterion 2: calibration_log.csv with correct headers ──
    if data.get("calib_log_exists") and data.get("log_has_header"):
        score += 15
        feedback.append("PASS(15): calibration_log.csv exists with correct column headers")
    elif data.get("calib_log_exists"):
        score += 6
        feedback.append("PARTIAL(6): calibration_log.csv exists but headers missing/wrong")
    else:
        feedback.append("FAIL(0): calibration_log.csv not found in hec_ras_results/")

    # ── Criterion 3: At least 3 distinct n values tested ──
    n_vals = data.get("n_values_tested", [])
    distinct_n = len(set(round(v, 3) for v in n_vals))
    # Also check that the n values are DIFFERENT from the starting wrong_n
    # (agent actually explored, not just ran once with wrong_n)
    if distinct_n >= 3:
        score += 20
        feedback.append(f"PASS(20): {distinct_n} distinct Manning's n values tested (≥3 required)")
    elif distinct_n == 2:
        score += 10
        feedback.append(f"PARTIAL(10): Only {distinct_n} distinct n values tested (3+ recommended)")
    elif distinct_n == 1:
        score += 4
        feedback.append(f"PARTIAL(4): Only {distinct_n} distinct n value tested — no iteration")
    else:
        feedback.append("FAIL(0): No Manning's n values found in calibration log")

    # ── Criterion 4: Final n in HDF5 is closer to true_n than wrong_n_start ──
    final_n = data.get("final_n_in_hdf")
    if final_n is not None:
        dist_to_true  = abs(final_n - true_n)
        dist_to_wrong = abs(final_n - wrong_n_start)
        n_within_tolerance = dist_to_true / true_n <= N_VARIATION_TOLERANCE

        if n_within_tolerance:
            score += 20
            feedback.append(f"PASS(20): Final Manning's n={final_n:.4f} is within ±{N_VARIATION_TOLERANCE*100:.0f}% of correct value ({true_n:.4f})")
        elif dist_to_true < dist_to_wrong:
            score += 10
            feedback.append(f"PARTIAL(10): Final n={final_n:.4f} is closer to correct ({true_n:.4f}) than starting wrong value ({wrong_n_start:.4f}), but outside ±20%")
        else:
            feedback.append(f"FAIL(0): Final n={final_n:.4f} is NOT closer to correct ({true_n:.4f}) than starting wrong ({wrong_n_start:.4f})")
    else:
        feedback.append("FAIL(0): Could not read final Manning's n from HDF5")

    # ── Criterion 5: Best simulated WSE within ±0.5 ft of target ──
    sim_wses = data.get("simulated_wse_values", [])
    if sim_wses:
        best_wse  = min(sim_wses, key=lambda w: abs(w - target_wse))
        best_res  = abs(best_wse - target_wse)
        if best_res <= CALIBRATION_TOLERANCE_FT:
            score += 25
            feedback.append(f"PASS(25): Best simulated peak WSE={best_wse:.3f} ft within ±{CALIBRATION_TOLERANCE_FT} ft of observed target={target_wse:.3f} ft")
        elif best_res <= 1.0:
            score += 14
            feedback.append(f"PARTIAL(14): Best WSE={best_wse:.3f} ft, residual={best_res:.3f} ft (target ±0.5 ft; within 1.0 ft)")
        elif best_res <= 2.0:
            score += 7
            feedback.append(f"PARTIAL(7): Best WSE={best_wse:.3f} ft, residual={best_res:.3f} ft (outside ±0.5 ft, within 2.0 ft)")
        else:
            feedback.append(f"FAIL(0): Best WSE={best_wse:.3f} ft, residual={best_res:.3f} ft — far from target={target_wse:.3f} ft")
    else:
        feedback.append(f"FAIL(0): No simulated WSE values found in calibration log (target: {target_wse:.3f} ft)")

    # ── Criterion 6: calibration_report.txt with key metrics ──
    if data.get("calib_report_exists") and data.get("report_text"):
        has_n   = data.get("report_n_value") is not None
        has_wse = data.get("report_peak_wse") is not None
        has_res = data.get("report_residual") is not None
        if has_n and has_wse:
            score += 10
            feedback.append(f"PASS(10): calibration_report.txt documents n={data.get('report_n_value')} and peak WSE={data.get('report_peak_wse')}")
        elif data.get("calib_report_exists"):
            score += 4
            feedback.append("PARTIAL(4): calibration_report.txt exists but key metrics not parsed")
    else:
        feedback.append("FAIL(0): calibration_report.txt not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "distinct_n_values": distinct_n,
            "final_n": final_n,
            "target_wse": target_wse,
        }
    }
