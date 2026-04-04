"""
Verifier: flood_frequency_analysis
Occupation: Civil Engineer / Hydraulic Engineer
Task: Run 3 return-period simulations, produce frequency_results.csv + BFE doc.

Scoring rubric (100 pts total):
  15 pts — HDF5 and b04 modified after task start (simulation was run)
  15 pts — frequency_results.csv exists with correct header
  20 pts — CSV has exactly 3 data rows with correct return periods (10, 50, 100)
  15 pts — Design flows in CSV match USGS values (16200, 23100, 26200 ± 5%)
  15 pts — WSE values are physically plausible AND monotonically increasing
  10 pts — BFE file exists and contains BFE=<value> line
  10 pts — BFE value matches the 100-yr WSE in the CSV (± 0.1 ft)

Pass threshold: 60 pts
"""
import json, logging, os, tempfile

logger = logging.getLogger(__name__)

DESIGN_FLOWS = {10: 16200, 50: 23100, 100: 26200}
WSE_MIN = 935.0
WSE_MAX = 965.0
FLOW_TOL_PCT = 5.0   # ± 5% tolerance on design flow values


def verify_flood_frequency_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env") or env_info.get("exec_capture")
    if callable(env_info.get("copy_from_env")):
        copy_fn = env_info["copy_from_env"]
    else:
        return {"passed": False, "score": 0, "feedback": "ERROR: copy_from_env not available"}

    # Retrieve result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_fn("/tmp/flood_freq_result.json", tmp.name)
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0,
                "feedback": f"Export result not found — export_result.sh may not have run: {e}"}

    try:
        data = json.loads(open(tmp.name).read())
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # ── Criterion 1: simulation was run (HDF5 / b04 modified after task start) ──
    hdf_modified = data.get("hdf_modified_after_start", False)
    b04_modified = data.get("b04_modified_after_start", False)
    if hdf_modified and b04_modified:
        score += 15
        feedback.append("PASS(15): Simulation run detected — HDF5 and b04 both updated")
    elif hdf_modified or b04_modified:
        score += 7
        feedback.append("PARTIAL(7): Simulation or b04 updated, but not both")
    else:
        feedback.append("FAIL(0): No evidence that simulation was run — HDF5 and b04 unchanged")

    # ── Criterion 2: frequency_results.csv exists with correct header ──
    if data.get("frequency_csv_exists") and data.get("csv_has_header"):
        score += 15
        feedback.append("PASS(15): frequency_results.csv exists with correct column headers")
    elif data.get("frequency_csv_exists"):
        score += 5
        feedback.append("PARTIAL(5): frequency_results.csv exists but header missing/wrong")
    else:
        feedback.append("FAIL(0): frequency_results.csv not found in hec_ras_results/")

    # ── Criterion 3: CSV has 3 rows with correct return periods ──
    rps = sorted(data.get("return_periods_present", []))
    if set(rps) == {10, 50, 100} and data.get("csv_row_count", 0) == 3:
        score += 20
        feedback.append("PASS(20): CSV has 3 rows with return periods 10, 50, 100")
    elif len(set(rps) & {10, 50, 100}) >= 2:
        score += 10
        feedback.append(f"PARTIAL(10): CSV has return periods {rps} — expected {{10, 50, 100}}")
    else:
        feedback.append(f"FAIL(0): CSV return periods {rps} — expected 10, 50, 100")

    # ── Criterion 4: design flows match USGS values within ±5% ──
    rows = data.get("frequency_rows", [])
    flow_match_count = 0
    for row in rows:
        rp   = row.get("return_period")
        flow = row.get("design_flow_cfs", 0)
        if rp in DESIGN_FLOWS:
            expected = DESIGN_FLOWS[rp]
            if abs(flow - expected) / expected <= FLOW_TOL_PCT / 100.0:
                flow_match_count += 1
    if flow_match_count == 3:
        score += 15
        feedback.append("PASS(15): All 3 design flows match USGS values within ±5%")
    elif flow_match_count >= 2:
        score += 8
        feedback.append(f"PARTIAL(8): {flow_match_count}/3 design flows within ±5% of USGS values")
    elif flow_match_count == 1:
        score += 3
        feedback.append(f"PARTIAL(3): Only {flow_match_count}/3 design flows within tolerance")
    else:
        feedback.append("FAIL(0): No design flows match USGS values within ±5%")

    # ── Criterion 5: WSE values are plausible and monotonically increasing ──
    wse_vals = data.get("wse_values", [])
    if len(wse_vals) == 3:
        wse_in_range = all(WSE_MIN <= w <= WSE_MAX for w in wse_vals)
        # WSE must be non-decreasing with return period (sort rows by return period first)
        rows_sorted = sorted(data.get("frequency_rows", []), key=lambda r: r.get("return_period", 0))
        wse_sorted = [r["peak_wse_ft"] for r in rows_sorted if "peak_wse_ft" in r]
        wse_monotonic = all(wse_sorted[i] <= wse_sorted[i+1] for i in range(len(wse_sorted)-1))
        if wse_in_range and wse_monotonic:
            score += 15
            feedback.append(f"PASS(15): WSE values {wse_vals} are plausible and monotonically increasing")
        elif wse_in_range:
            score += 8
            feedback.append(f"PARTIAL(8): WSE values {wse_vals} are in range but not monotonically increasing")
        elif wse_monotonic:
            score += 5
            feedback.append(f"PARTIAL(5): WSE values are monotonic but outside plausible range ({WSE_MIN}–{WSE_MAX} ft)")
        else:
            feedback.append(f"FAIL(0): WSE values {wse_vals} are implausible or non-monotonic")
    else:
        feedback.append(f"FAIL(0): Expected 3 WSE values, found {len(wse_vals)}")

    # ── Criterion 6: BFE file exists with correct format ──
    if data.get("bfe_file_exists") and data.get("bfe_value") is not None:
        score += 10
        feedback.append(f"PASS(10): BFE file exists with BFE={data['bfe_value']} ft")
    elif data.get("bfe_file_exists"):
        score += 4
        feedback.append("PARTIAL(4): BFE file exists but BFE= line not found or unreadable")
    else:
        feedback.append("FAIL(0): bfe_documentation.txt not found in hec_ras_results/")

    # ── Criterion 7: BFE value consistent with 100-yr WSE in CSV ──
    bfe_value = data.get("bfe_value")
    csv_100yr_wse = None
    for row in rows:
        if row.get("return_period") == 100:
            csv_100yr_wse = row.get("peak_wse_ft")
    if bfe_value is not None and csv_100yr_wse is not None:
        if abs(bfe_value - csv_100yr_wse) <= 0.1:
            score += 10
            feedback.append(f"PASS(10): BFE={bfe_value} ft matches 100-yr WSE={csv_100yr_wse} ft in CSV")
        else:
            feedback.append(f"FAIL(0): BFE={bfe_value} ft does not match 100-yr WSE={csv_100yr_wse} ft (diff={abs(bfe_value - csv_100yr_wse):.2f} ft)")
    else:
        feedback.append("FAIL(0): Cannot compare BFE to 100-yr WSE (missing data)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "simulation_run": score,
        }
    }
