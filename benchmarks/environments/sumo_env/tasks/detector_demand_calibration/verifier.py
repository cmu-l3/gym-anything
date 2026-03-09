#!/usr/bin/env python3
"""Verifier for detector_demand_calibration task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran and detector counts CSV produced (15 pts)
  C2: Observed reference counts CSV produced with plausible scaling (10 pts)
  C3: Calibrated route file created with modifications (20 pts)
  C4: Calibrated simulation ran and detector counts CSV produced (15 pts)
  C5: Calibration report CSV with GEH statistics (25 pts)
  C6: Calibration summary with methodology, GEH<5 stats, recommendations (15 pts)
"""

import json
import csv
import tempfile
import os
import io
import re
import math
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/detector_demand_calibration_result.json"


def verify_detector_demand_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # --- Do-nothing gate ---
    baseline_exists = result.get("baseline_counts_exists", False)
    observed_exists = result.get("observed_counts_exists", False)
    cal_route_exists = result.get("calibrated_route_exists", False)
    cal_counts_exists = result.get("calibrated_counts_exists", False)
    report_exists = result.get("calibration_report_exists", False)
    summary_exists = result.get("summary_exists", False)

    if not baseline_exists and not cal_route_exists and not report_exists and not summary_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No outputs found."}

    # --- C1: Baseline detector counts CSV (15 pts) ---
    baseline_content = result.get("baseline_counts_content", "")
    if baseline_exists and baseline_content:
        c1_score = 0
        try:
            reader = csv.DictReader(io.StringIO(baseline_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["detector_id", "interval_begin", "interval_end", "vehicle_count"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 4:
                c1_score += 5
                feedback.append("C1a: Baseline CSV has all required columns (+5)")
            elif cols_found >= 2:
                c1_score += 3
                feedback.append(f"C1a: Baseline CSV has {cols_found}/4 columns (+3)")
            else:
                feedback.append(f"C1a: Baseline CSV missing columns ({fieldnames}) (+0)")

            rows = list(reader)
            baseline_rows = result.get("baseline_counts_rows", 0)
            if len(rows) >= 50:
                c1_score += 5
                feedback.append(f"C1b: {len(rows)} detector count rows (multi-detector data) (+5)")
            elif len(rows) >= 10:
                c1_score += 3
                feedback.append(f"C1b: {len(rows)} detector count rows (+3)")
            elif len(rows) >= 1:
                c1_score += 1
                feedback.append(f"C1b: Only {len(rows)} rows (+1)")
            else:
                feedback.append("C1b: No data rows (+0)")

            # Check for numeric vehicle counts
            numeric_rows = 0
            for row in rows:
                try:
                    vc = row.get("vehicle_count", "")
                    if vc and float(vc) >= 0:
                        numeric_rows += 1
                except (ValueError, TypeError):
                    pass
            if numeric_rows >= 20:
                c1_score += 5
                feedback.append(f"C1c: {numeric_rows} rows with valid numeric counts (+5)")
            elif numeric_rows >= 5:
                c1_score += 3
                feedback.append(f"C1c: {numeric_rows} rows with valid counts (+3)")
            else:
                feedback.append(f"C1c: Only {numeric_rows} valid numeric rows (+0)")

        except Exception as e:
            feedback.append(f"C1: Error parsing baseline CSV: {e} (+0)")

        score += c1_score
    else:
        feedback.append("C1: Baseline detector counts CSV not found (+0)")

    # --- C2: Observed reference counts CSV (10 pts) ---
    if observed_exists:
        observed_content = result.get("observed_counts_content", "")
        c2_score = 0
        observed_rows = result.get("observed_counts_rows", 0)
        if observed_rows >= 10:
            c2_score += 5
            feedback.append(f"C2a: Observed counts CSV has {observed_rows} rows (+5)")
        elif observed_rows >= 2:
            c2_score += 3
            feedback.append(f"C2a: Observed counts CSV has {observed_rows} rows (+3)")
        else:
            feedback.append("C2a: Observed counts CSV empty or very small (+0)")

        # Check if observed > baseline (scaling applied)
        try:
            reader = csv.DictReader(io.StringIO(observed_content))
            rows = list(reader)
            obs_values = []
            for row in rows:
                try:
                    v = float(row.get("vehicle_count", "0"))
                    obs_values.append(v)
                except (ValueError, TypeError):
                    pass
            if obs_values and sum(obs_values) > 0:
                c2_score += 5
                feedback.append(f"C2b: Observed counts have valid values (total: {sum(obs_values):.0f}) (+5)")
            else:
                feedback.append("C2b: No valid observed count values (+0)")
        except Exception:
            feedback.append("C2b: Error parsing observed CSV (+0)")

        score += c2_score
    else:
        feedback.append("C2: Observed reference counts CSV not found (+0)")

    # --- C3: Calibrated route file (20 pts) ---
    if cal_route_exists:
        c3_score = 0
        cal_size = result.get("calibrated_route_size", 0)
        cal_veh_count = result.get("calibrated_vehicle_count", 0)
        orig_veh_count = result.get("initial_data", {}).get("vehicle_count", 0)

        if cal_size > 1000:
            c3_score += 5
            feedback.append(f"C3a: Calibrated route file exists ({cal_size} bytes) (+5)")
        elif cal_size > 0:
            c3_score += 2
            feedback.append(f"C3a: Calibrated route file small ({cal_size} bytes) (+2)")
        else:
            feedback.append("C3a: Calibrated route file is empty (+0)")

        if cal_veh_count > 0:
            c3_score += 5
            feedback.append(f"C3b: Calibrated route has {cal_veh_count} vehicles (+5)")
        else:
            feedback.append("C3b: No vehicles in calibrated route file (+0)")

        # Check if vehicle count actually changed (calibration applied)
        if orig_veh_count > 0 and cal_veh_count > 0 and cal_veh_count != orig_veh_count:
            c3_score += 10
            ratio = cal_veh_count / orig_veh_count
            feedback.append(f"C3c: Vehicle count changed from {orig_veh_count} to {cal_veh_count} (ratio: {ratio:.2f}) (+10)")
        elif orig_veh_count > 0 and cal_veh_count > 0:
            c3_score += 5
            feedback.append("C3c: Vehicle count unchanged - may have adjusted timing instead (+5)")
        else:
            feedback.append("C3c: Cannot compare vehicle counts (+0)")

        score += c3_score
    else:
        feedback.append("C3: Calibrated route file not found (+0)")

    # --- C4: Calibrated detector counts CSV (15 pts) ---
    if cal_counts_exists:
        cal_content = result.get("calibrated_counts_content", "")
        c4_score = 0
        cal_rows = result.get("calibrated_counts_rows", 0)

        if cal_rows >= 50:
            c4_score += 8
            feedback.append(f"C4a: Calibrated counts CSV has {cal_rows} rows (+8)")
        elif cal_rows >= 10:
            c4_score += 5
            feedback.append(f"C4a: Calibrated counts CSV has {cal_rows} rows (+5)")
        elif cal_rows >= 2:
            c4_score += 3
            feedback.append(f"C4a: Calibrated counts CSV has {cal_rows} rows (+3)")
        else:
            feedback.append("C4a: Calibrated counts CSV empty or small (+0)")

        # Check for valid data
        try:
            reader = csv.DictReader(io.StringIO(cal_content))
            rows = list(reader)
            valid = sum(1 for r in rows if float(r.get("vehicle_count", "0")) >= 0)
            if valid >= 20:
                c4_score += 7
                feedback.append(f"C4b: {valid} rows with valid counts (+7)")
            elif valid >= 5:
                c4_score += 4
                feedback.append(f"C4b: {valid} rows with valid counts (+4)")
            else:
                feedback.append(f"C4b: Only {valid} valid rows (+0)")
        except Exception:
            feedback.append("C4b: Error checking calibrated data (+0)")

        score += c4_score
    else:
        feedback.append("C4: Calibrated detector counts CSV not found (+0)")

    # --- C5: Calibration report CSV with GEH (25 pts) ---
    if report_exists:
        report_content = result.get("calibration_report_content", "")
        c5_score = 0
        try:
            reader = csv.DictReader(io.StringIO(report_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["detector_id", "observed_count", "baseline_count",
                           "calibrated_count", "baseline_geh", "calibrated_geh"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 6:
                c5_score += 7
                feedback.append("C5a: All 6 required columns present (+7)")
            elif cols_found >= 4:
                c5_score += 4
                feedback.append(f"C5a: {cols_found}/6 columns present (+4)")
            elif cols_found >= 2:
                c5_score += 2
                feedback.append(f"C5a: {cols_found}/6 columns present (+2)")
            else:
                feedback.append(f"C5a: Missing columns (found: {fieldnames}) (+0)")

            rows = list(reader)
            if len(rows) >= 10:
                c5_score += 6
                feedback.append(f"C5b: {len(rows)} detector rows in report (+6)")
            elif len(rows) >= 3:
                c5_score += 3
                feedback.append(f"C5b: {len(rows)} detector rows (+3)")
            else:
                feedback.append(f"C5b: Only {len(rows)} rows (+0)")

            # Check for valid GEH values
            geh_valid = 0
            geh_improved = 0
            for row in rows:
                try:
                    bg = float(row.get("baseline_geh", ""))
                    cg = float(row.get("calibrated_geh", ""))
                    if bg >= 0 and cg >= 0:
                        geh_valid += 1
                        if cg < bg:
                            geh_improved += 1
                except (ValueError, TypeError):
                    pass

            if geh_valid >= 10:
                c5_score += 7
                feedback.append(f"C5c: {geh_valid} detectors with valid GEH values (+7)")
            elif geh_valid >= 3:
                c5_score += 4
                feedback.append(f"C5c: {geh_valid} detectors with valid GEH values (+4)")
            else:
                feedback.append(f"C5c: Only {geh_valid} valid GEH entries (+0)")

            if geh_improved > 0:
                c5_score += 5
                feedback.append(f"C5d: {geh_improved}/{geh_valid} detectors show GEH improvement (+5)")
            else:
                feedback.append("C5d: No GEH improvement detected (+0)")

        except Exception as e:
            feedback.append(f"C5: Error parsing calibration report: {e} (+0)")

        score += c5_score
    else:
        feedback.append("C5: Calibration report CSV not found (+0)")

    # --- C6: Calibration summary (15 pts) ---
    summary_content = result.get("summary_content", "")
    summary_length = result.get("summary_length", 0)

    if summary_exists and summary_length > 100:
        c6_score = 0
        summary_lower = summary_content.lower()

        cal_keywords = ["calibrat", "geh", "detector", "demand", "vehicle",
                       "observed", "simulated", "count", "loop", "threshold",
                       "acceptance", "methodology", "adjustment", "scaling"]
        hits = sum(1 for k in cal_keywords if k in summary_lower)
        if hits >= 5:
            c6_score += 8
            feedback.append(f"C6a: Summary contains {hits} calibration terms (+8)")
        elif hits >= 3:
            c6_score += 5
            feedback.append(f"C6a: Summary contains {hits} terms (+5)")
        else:
            c6_score += 2
            feedback.append(f"C6a: Summary has {hits} terms (+2)")

        numbers = re.findall(r'\d+\.?\d*\s*%', summary_content)
        if len(numbers) >= 2:
            c6_score += 7
            feedback.append(f"C6b: Summary includes {len(numbers)} percentage values (+7)")
        elif len(numbers) >= 1:
            c6_score += 4
            feedback.append(f"C6b: Summary includes {len(numbers)} percentage value (+4)")
        else:
            any_numbers = re.findall(r'\d+\.?\d*', summary_content)
            if len(any_numbers) >= 5:
                c6_score += 3
                feedback.append("C6b: Summary has numerical data but no percentage format (+3)")
            else:
                feedback.append("C6b: No numerical results in summary (+0)")

        score += c6_score
    elif summary_exists:
        score += 2
        feedback.append(f"C6: Summary exists but short ({summary_length} chars) (+2)")
    else:
        feedback.append("C6: Summary not found (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
