"""
Verifier: dam_breach_scenario
Occupation: Civil Engineer / Dam Safety Engineer (O*NET 17-2051.00)
Task: Construct dam-break hydrograph, run simulation, produce inundation report.

Scoring rubric (100 pts total):
  15 pts — b04 boundary condition file modified with new hydrograph
  15 pts — Peak flow in b04 matches dam breach parameters (45000 cfs ± 10%)
  20 pts — Simulation run (HDF5 updated after task start)
  20 pts — Report exists with all 4 labeled metric lines
  20 pts — Peak WSE in report is physically plausible (> baseline of ~953 ft)
  10 pts — Report includes narrative summary paragraph (≥ 30 words)

Pass threshold: 60 pts
Wrong-target gate: If b04 was NOT modified, score=0 (agent used wrong baseline).
"""
import json, logging, os, tempfile

logger = logging.getLogger(__name__)

PEAK_BREACH_FLOW = 45000.0   # cfs from dam breach parameters
FLOW_TOL_PCT     = 0.10      # ±10%
BASELINE_PEAK_WSE = 953.84   # ft — from standard Muncie 21000 cfs simulation
WSE_MAX_PLAUSIBLE = 980.0    # ft — upper bound for sanity check


def verify_dam_breach_scenario(traj, env_info, task_info):
    if not callable(env_info.get("copy_from_env")):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}
    copy_fn = env_info["copy_from_env"]

    # Load GT
    gt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    gt_tmp.close()
    try:
        copy_fn("/tmp/dambreach_gt.json", gt_tmp.name)
        gt = json.loads(open(gt_tmp.name).read())
    except Exception as e:
        os.unlink(gt_tmp.name)
        return {"passed": False, "score": 0, "feedback": f"GT not found: {e}"}
    finally:
        try: os.unlink(gt_tmp.name)
        except Exception: pass

    # Load result
    res_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    res_tmp.close()
    try:
        copy_fn("/tmp/dambreach_result.json", res_tmp.name)
        data = json.loads(open(res_tmp.name).read())
    except Exception as e:
        os.unlink(res_tmp.name)
        return {"passed": False, "score": 0, "feedback": f"Export result not found: {e}"}
    finally:
        try: os.unlink(res_tmp.name)
        except Exception: pass

    score = 0
    feedback = []

    # ── Wrong-target gate: b04 MUST have been modified ──
    if not data.get("b04_modified"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: Muncie.b04 was not modified — agent did not replace the hydrograph. "
                            "Dam breach hydrograph must be constructed and written to b04."}

    # ── Criterion 1: b04 modified ──
    score += 15
    feedback.append(f"PASS(15): Muncie.b04 modified (line count changed from {data.get('b04_original_line_count')} to {data.get('b04_line_count')})")

    # ── Criterion 2: Peak flow in b04 matches 45000 cfs ±10% ──
    b04_peak = data.get("b04_peak_flow")
    if b04_peak is not None:
        diff_pct = abs(b04_peak - PEAK_BREACH_FLOW) / PEAK_BREACH_FLOW
        if diff_pct <= FLOW_TOL_PCT:
            score += 15
            feedback.append(f"PASS(15): Peak flow in b04={b04_peak:.0f} cfs (target 45000 cfs, within ±10%)")
        elif diff_pct <= 0.25:
            score += 7
            feedback.append(f"PARTIAL(7): Peak flow in b04={b04_peak:.0f} cfs (target 45000 cfs, within ±25%)")
        else:
            feedback.append(f"FAIL(0): Peak flow in b04={b04_peak:.0f} cfs differs from 45000 cfs by {diff_pct*100:.0f}%")
    else:
        feedback.append("FAIL(0): Could not extract peak flow from modified b04")

    # ── Criterion 3: Simulation run ──
    if data.get("hdf_modified_after_start"):
        score += 20
        feedback.append("PASS(20): Simulation output HDF5 updated after task start")
    else:
        feedback.append("FAIL(0): No evidence that RasUnsteady was run after task start")

    # ── Criterion 4: Report with all 4 labeled metric lines ──
    if data.get("report_exists"):
        metrics_found = sum([
            data.get("report_peak_breach_flow") is not None,
            data.get("report_peak_wse") is not None,
            data.get("report_mean_peak_wse") is not None,
            data.get("report_peak_timestep_min") is not None,
        ])
        if metrics_found == 4:
            score += 20
            feedback.append("PASS(20): Report has all 4 labeled metric lines")
        elif metrics_found >= 2:
            score += 10
            feedback.append(f"PARTIAL(10): Report has {metrics_found}/4 labeled metric lines")
        elif metrics_found == 1:
            score += 5
            feedback.append(f"PARTIAL(5): Report has {metrics_found}/4 labeled metric lines")
        else:
            feedback.append("FAIL(0): Report exists but no labeled metric lines found")
    else:
        feedback.append("FAIL(0): dam_breach_report.txt not found in hec_ras_results/")

    # ── Criterion 5: Peak WSE is physically plausible (above baseline) ──
    rep_wse = data.get("report_peak_wse")
    if rep_wse is not None:
        if BASELINE_PEAK_WSE < rep_wse <= WSE_MAX_PLAUSIBLE:
            score += 20
            feedback.append(f"PASS(20): Reported peak WSE={rep_wse:.2f} ft is above baseline {BASELINE_PEAK_WSE} ft (dam-breach scenario correct)")
        elif WSE_MAX_PLAUSIBLE < rep_wse:
            score += 5
            feedback.append(f"PARTIAL(5): Reported peak WSE={rep_wse:.2f} ft exceeds plausible maximum {WSE_MAX_PLAUSIBLE} ft")
        else:
            feedback.append(f"FAIL(0): Reported peak WSE={rep_wse:.2f} ft is not above baseline {BASELINE_PEAK_WSE} ft — dam breach must produce higher flooding than standard event")
    else:
        feedback.append(f"FAIL(0): No peak WSE found in report (expected > {BASELINE_PEAK_WSE} ft for dam-breach scenario)")

    # ── Criterion 6: Narrative summary paragraph ──
    word_count = data.get("report_summary_word_count", 0)
    if word_count >= 30:
        score += 10
        feedback.append(f"PASS(10): Report includes narrative summary ({word_count} words)")
    elif word_count >= 10:
        score += 5
        feedback.append(f"PARTIAL(5): Report has brief summary ({word_count} words, ≥30 recommended)")
    else:
        feedback.append(f"FAIL(0): Report lacks narrative summary (only {word_count} words)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
