#!/usr/bin/env python3
"""Verifier for multimodal_person_trip_analysis task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran and modal performance CSV produced (15 pts)
  C2: Bus stop analysis CSV with per-stop metrics (20 pts)
  C3: Underserved stops identified with valid gap reasons (15 pts)
  C4: New bus route + improved sumocfg created (20 pts)
  C5: Transit assessment report with modal analysis and improvement proposals (15 pts)
  C6: Stop-output XML generated (simulation configured correctly) (15 pts)
"""

import json
import csv
import tempfile
import os
import io
import re
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/multimodal_person_trip_analysis_result.json"


def verify_multimodal_person_trip_analysis(traj, env_info, task_info):
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
    modal_exists = result.get("modal_perf_exists", False)
    bus_analysis_exists = result.get("bus_stop_analysis_exists", False)
    underserved_exists = result.get("underserved_exists", False)
    new_route_exists = result.get("new_bus_route_exists", False)
    report_exists = result.get("report_exists", False)

    if not modal_exists and not bus_analysis_exists and not new_route_exists and not report_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No outputs found."}

    # --- C1: Modal performance CSV (15 pts) ---
    if modal_exists:
        modal_content = result.get("modal_perf_content", "")
        c1_score = 0
        try:
            reader = csv.DictReader(io.StringIO(modal_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["mode", "metric", "value"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 3:
                c1_score += 5
                feedback.append("C1a: Modal CSV has all required columns (+5)")
            elif cols_found >= 2:
                c1_score += 3
                feedback.append(f"C1a: {cols_found}/3 columns present (+3)")
            else:
                feedback.append(f"C1a: Missing columns ({fieldnames}) (+0)")

            rows = list(reader)
            modes_found = set()
            for row in rows:
                mode = row.get("mode", "").strip().lower()
                if "bus" in mode:
                    modes_found.add("bus")
                if "private" in mode or "car" in mode or "passenger" in mode:
                    modes_found.add("car")

            if len(modes_found) >= 2:
                c1_score += 5
                feedback.append("C1b: Both bus and car modes present (+5)")
            elif len(modes_found) >= 1:
                c1_score += 3
                feedback.append(f"C1b: Only {modes_found} mode(s) found (+3)")
            else:
                feedback.append("C1b: No recognized modes found (+0)")

            # Check for valid numeric values
            valid_vals = 0
            for row in rows:
                try:
                    v = float(row.get("value", ""))
                    if v >= 0:
                        valid_vals += 1
                except (ValueError, TypeError):
                    pass
            if valid_vals >= 4:
                c1_score += 5
                feedback.append(f"C1c: {valid_vals} valid metric values (+5)")
            elif valid_vals >= 2:
                c1_score += 3
                feedback.append(f"C1c: {valid_vals} valid values (+3)")
            else:
                feedback.append(f"C1c: Only {valid_vals} valid values (+0)")

        except Exception as e:
            feedback.append(f"C1: Error parsing CSV: {e} (+0)")

        score += c1_score
    else:
        feedback.append("C1: Modal performance CSV not found (+0)")

    # --- C2: Bus stop analysis CSV (20 pts) ---
    if bus_analysis_exists:
        bus_content = result.get("bus_stop_analysis_content", "")
        c2_score = 0
        try:
            reader = csv.DictReader(io.StringIO(bus_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["stop_id", "num_buses_served", "total_dwell_time_s", "avg_headway_s"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 4:
                c2_score += 7
                feedback.append("C2a: All 4 required columns present (+7)")
            elif cols_found >= 3:
                c2_score += 5
                feedback.append(f"C2a: {cols_found}/4 columns present (+5)")
            elif cols_found >= 2:
                c2_score += 3
                feedback.append(f"C2a: {cols_found}/4 columns present (+3)")
            else:
                feedback.append(f"C2a: Missing columns ({fieldnames}) (+0)")

            rows = list(reader)
            bus_rows = result.get("bus_stop_analysis_rows", 0)
            if len(rows) >= 20:
                c2_score += 7
                feedback.append(f"C2b: {len(rows)} bus stops analyzed (+7)")
            elif len(rows) >= 10:
                c2_score += 5
                feedback.append(f"C2b: {len(rows)} bus stops analyzed (+5)")
            elif len(rows) >= 3:
                c2_score += 3
                feedback.append(f"C2b: {len(rows)} bus stops analyzed (+3)")
            else:
                feedback.append(f"C2b: Only {len(rows)} rows (+0)")

            # Check for valid numeric data
            valid_stops = 0
            for row in rows:
                try:
                    buses = int(row.get("num_buses_served", "0"))
                    if buses >= 0:
                        valid_stops += 1
                except (ValueError, TypeError):
                    pass
            if valid_stops >= 10:
                c2_score += 6
                feedback.append(f"C2c: {valid_stops} stops with valid bus count data (+6)")
            elif valid_stops >= 3:
                c2_score += 3
                feedback.append(f"C2c: {valid_stops} stops with valid data (+3)")
            else:
                feedback.append(f"C2c: Only {valid_stops} valid entries (+0)")

        except Exception as e:
            feedback.append(f"C2: Error parsing bus stop CSV: {e} (+0)")

        score += c2_score
    else:
        feedback.append("C2: Bus stop analysis CSV not found (+0)")

    # --- C3: Underserved stops CSV (15 pts) ---
    if underserved_exists:
        underserved_content = result.get("underserved_content", "")
        c3_score = 0
        try:
            reader = csv.DictReader(io.StringIO(underserved_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["stop_id", "num_visits", "avg_headway_s", "gap_reason"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 4:
                c3_score += 5
                feedback.append("C3a: All 4 required columns present (+5)")
            elif cols_found >= 2:
                c3_score += 3
                feedback.append(f"C3a: {cols_found}/4 columns present (+3)")
            else:
                feedback.append(f"C3a: Missing columns ({fieldnames}) (+0)")

            rows = list(reader)
            if len(rows) >= 1:
                c3_score += 5
                feedback.append(f"C3b: {len(rows)} underserved stops identified (+5)")
            else:
                feedback.append("C3b: No underserved stops identified (+0)")

            # Check gap_reason is meaningful
            reasons_valid = 0
            for row in rows:
                reason = row.get("gap_reason", "").lower()
                if "headway" in reason or "visit" in reason or "frequency" in reason or "few" in reason or "low" in reason:
                    reasons_valid += 1
            if reasons_valid >= 1:
                c3_score += 5
                feedback.append(f"C3c: {reasons_valid} stops with meaningful gap reasons (+5)")
            else:
                feedback.append("C3c: No meaningful gap reasons found (+0)")

        except Exception as e:
            feedback.append(f"C3: Error parsing underserved CSV: {e} (+0)")

        score += c3_score
    else:
        feedback.append("C3: Underserved stops CSV not found (+0)")

    # --- C4: New bus route + improved sumocfg (20 pts) ---
    if new_route_exists:
        c4_score = 0
        new_veh_count = result.get("new_bus_vehicle_count", 0)
        new_stops = result.get("new_bus_stops_served", [])
        improved_cfg = result.get("improved_cfg_exists", False)

        if new_veh_count >= 2:
            c4_score += 7
            feedback.append(f"C4a: New route file has {new_veh_count} bus vehicles (target >= 2) (+7)")
        elif new_veh_count >= 1:
            c4_score += 4
            feedback.append(f"C4a: New route file has {new_veh_count} bus vehicle(s) (+4)")
        else:
            feedback.append("C4a: No bus vehicles in new route file (+0)")

        if len(new_stops) >= 3:
            c4_score += 7
            feedback.append(f"C4b: New buses serve {len(new_stops)} stops (target >= 3) (+7)")
        elif len(new_stops) >= 1:
            c4_score += 4
            feedback.append(f"C4b: New buses serve {len(new_stops)} stop(s) (+4)")
        else:
            feedback.append("C4b: No bus stops in new route (+0)")

        if improved_cfg:
            cfg_content = result.get("improved_cfg_content", "")
            if "new_bus_route" in cfg_content or "acosta_new_bus" in cfg_content:
                c4_score += 6
                feedback.append("C4c: Improved sumocfg references new bus route (+6)")
            elif cfg_content:
                c4_score += 3
                feedback.append("C4c: Improved sumocfg exists but may not reference new route (+3)")
            else:
                feedback.append("C4c: Improved sumocfg is empty (+0)")
        else:
            feedback.append("C4c: Improved sumocfg not found (+0)")

        score += c4_score
    else:
        feedback.append("C4: New bus route file not found (+0)")

    # --- C5: Transit assessment report (15 pts) ---
    report_content = result.get("report_content", "")
    report_length = result.get("report_length", 0)

    if report_exists and report_length > 100:
        c5_score = 0
        report_lower = report_content.lower()

        transit_keywords = ["transit", "bus", "modal", "accessibility", "headway",
                          "frequency", "service", "route", "stop", "passenger",
                          "underserved", "gap", "improvement", "dwell", "coverage",
                          "multimodal", "public transport"]
        hits = sum(1 for k in transit_keywords if k in report_lower)
        if hits >= 6:
            c5_score += 8
            feedback.append(f"C5a: Report contains {hits} transit planning terms (+8)")
        elif hits >= 3:
            c5_score += 5
            feedback.append(f"C5a: Report contains {hits} terms (+5)")
        else:
            c5_score += 2
            feedback.append(f"C5a: Report has {hits} terms (+2)")

        numbers = re.findall(r'\d+\.?\d*', report_content)
        if len(numbers) >= 10:
            c5_score += 7
            feedback.append(f"C5b: Report includes {len(numbers)} numerical data points (+7)")
        elif len(numbers) >= 5:
            c5_score += 4
            feedback.append(f"C5b: Report includes {len(numbers)} numerical values (+4)")
        else:
            feedback.append(f"C5b: Only {len(numbers)} numerical values (+0)")

        score += c5_score
    elif report_exists:
        score += 2
        feedback.append(f"C5: Report exists but short ({report_length} chars) (+2)")
    else:
        feedback.append("C5: Report not found (+0)")

    # --- C6: Stop-output XML generated (15 pts) ---
    stop_output_exists = result.get("stop_output_exists", False)
    stop_output_size = result.get("stop_output_size", 0)

    if stop_output_exists and stop_output_size > 1000:
        score += 15
        feedback.append(f"C6: Stop-output XML generated ({stop_output_size} bytes) (+15)")
    elif stop_output_exists and stop_output_size > 100:
        score += 8
        feedback.append(f"C6: Stop-output exists but small ({stop_output_size} bytes) (+8)")
    elif stop_output_exists:
        score += 4
        feedback.append(f"C6: Stop-output exists but nearly empty ({stop_output_size} bytes) (+4)")
    elif result.get("tripinfo_exists", False):
        score += 3
        feedback.append("C6: Tripinfo exists but no stop-output (--stop-output not configured) (+3)")
    else:
        feedback.append("C6: No stop-output or tripinfo found (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
