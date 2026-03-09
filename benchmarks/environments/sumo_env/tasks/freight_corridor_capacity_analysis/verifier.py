#!/usr/bin/env python3
"""Verifier for freight_corridor_capacity_analysis task.

Scoring breakdown (100 points, pass >= 60):
  C1: Truck vehicle type definitions exist with realistic parameters (15 pts)
  C2: At least 60 truck vehicles added to simulation routes (20 pts)
  C3: Modified simulation ran and produced tripinfo output (15 pts)
  C4: CSV report exists with correct structure and required metrics (25 pts)
  C5: Professional recommendation file exists with substantive analysis (15 pts)
  C6: Wrong-target gate - report values must be numerically plausible (10 pts)
"""

import json
import csv
import tempfile
import os
import io
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/freight_corridor_capacity_analysis_result.json"

REQUIRED_METRICS = [
    "avg_travel_time",
    "avg_speed",
    "total_vehicles_completed",
    "avg_waiting_time",
    "truck_avg_travel_time",
]

REQUIRED_COLUMNS = ["metric", "baseline_value", "with_trucks_value", "delta_pct"]


def verify_freight_corridor_capacity_analysis(traj, env_info, task_info):
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
    report_exists = result.get("report_exists", False)
    truck_routes = result.get("truck_routes_exist", False)
    modified_sim = result.get("modified_tripinfo_exists", False)

    if not report_exists and not truck_routes and not modified_sim:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No report, truck routes, or simulation output found."}

    # --- C1: Truck vehicle type definitions (15 pts) ---
    truck_count = result.get("truck_vehicle_count", 0)
    truck_routes_exist = result.get("truck_routes_exist", False)

    if truck_routes_exist and truck_count >= 60:
        score += 15
        feedback.append(f"C1: Truck vehicle definitions found with {truck_count} vehicles (+15)")
    elif truck_routes_exist and truck_count >= 30:
        score += 10
        feedback.append(f"C1: Truck definitions found but only {truck_count} vehicles (+10)")
    elif truck_routes_exist:
        score += 5
        feedback.append(f"C1: Truck route files exist but only {truck_count} truck vehicles (+5)")
    else:
        feedback.append("C1: No truck vehicle type definitions found (+0)")

    # --- C2: At least 60 truck vehicles in routes (20 pts) ---
    if truck_count >= 80:
        score += 20
        feedback.append(f"C2: {truck_count} truck vehicles added (target: 80) (+20)")
    elif truck_count >= 60:
        score += 15
        feedback.append(f"C2: {truck_count} truck vehicles added (target: 80) (+15)")
    elif truck_count >= 40:
        score += 10
        feedback.append(f"C2: {truck_count} truck vehicles added (target: 80) (+10)")
    elif truck_count >= 20:
        score += 5
        feedback.append(f"C2: {truck_count} truck vehicles added (target: 80) (+5)")
    else:
        feedback.append(f"C2: Only {truck_count} truck vehicles found (target: 80) (+0)")

    # --- C3: Simulation ran with truck traffic (15 pts) ---
    if modified_sim:
        tripinfo_size = result.get("modified_tripinfo_size", 0)
        if tripinfo_size > 1000:
            score += 15
            feedback.append(f"C3: Modified simulation produced tripinfo ({tripinfo_size} bytes) (+15)")
        else:
            score += 5
            feedback.append(f"C3: Tripinfo exists but small ({tripinfo_size} bytes) (+5)")
    else:
        feedback.append("C3: No modified simulation tripinfo output found (+0)")

    # --- C4: CSV report with correct structure and metrics (25 pts) ---
    report_content = result.get("report_content", "")
    if report_exists and report_content:
        c4_score = 0
        try:
            reader = csv.DictReader(io.StringIO(report_content))
            fieldnames = reader.fieldnames or []

            # Check columns
            cols_present = sum(1 for c in REQUIRED_COLUMNS if c in fieldnames)
            if cols_present == len(REQUIRED_COLUMNS):
                c4_score += 5
                feedback.append("C4a: All required columns present (+5)")
            else:
                feedback.append(f"C4a: {cols_present}/{len(REQUIRED_COLUMNS)} required columns present (+0)")

            # Check metrics rows
            rows = list(reader)
            metrics_found = set()
            numeric_valid = 0
            for row in rows:
                metric_name = row.get("metric", "").strip().lower()
                for req in REQUIRED_METRICS:
                    if req in metric_name or metric_name in req:
                        metrics_found.add(req)
                        # Check if values are numeric
                        try:
                            bv = float(row.get("baseline_value", ""))
                            wv = float(row.get("with_trucks_value", ""))
                            if bv > 0 and wv > 0:
                                numeric_valid += 1
                        except (ValueError, TypeError):
                            pass

            metrics_count = len(metrics_found)
            if metrics_count >= 5:
                c4_score += 10
                feedback.append(f"C4b: All {metrics_count} required metrics present (+10)")
            elif metrics_count >= 3:
                c4_score += 6
                feedback.append(f"C4b: {metrics_count}/5 required metrics present (+6)")
            elif metrics_count >= 1:
                c4_score += 3
                feedback.append(f"C4b: {metrics_count}/5 required metrics present (+3)")
            else:
                feedback.append("C4b: No required metrics found in report (+0)")

            if numeric_valid >= 4:
                c4_score += 10
                feedback.append(f"C4c: {numeric_valid} metrics have valid numeric values (+10)")
            elif numeric_valid >= 2:
                c4_score += 5
                feedback.append(f"C4c: {numeric_valid} metrics have valid numeric values (+5)")
            else:
                feedback.append(f"C4c: Only {numeric_valid} metrics have valid numeric values (+0)")

        except Exception as e:
            feedback.append(f"C4: Error parsing CSV: {e} (+0)")

        score += c4_score
    else:
        feedback.append("C4: CSV report not found or empty (+0)")

    # --- C5: Professional recommendation (15 pts) ---
    rec_exists = result.get("recommendation_exists", False)
    rec_content = result.get("recommendation_content", "")
    rec_length = result.get("recommendation_length", 0)

    if rec_exists and rec_length > 100:
        c5_score = 0
        rec_lower = rec_content.lower()

        # Check for substantive content keywords
        transport_keywords = ["corridor", "truck", "freight", "traffic", "capacity",
                              "travel time", "congestion", "vehicle", "recommend",
                              "simulation", "analysis"]
        keyword_hits = sum(1 for k in transport_keywords if k in rec_lower)

        if keyword_hits >= 5:
            c5_score += 10
            feedback.append(f"C5a: Recommendation contains {keyword_hits} relevant terms (+10)")
        elif keyword_hits >= 3:
            c5_score += 6
            feedback.append(f"C5a: Recommendation contains {keyword_hits} relevant terms (+6)")
        else:
            c5_score += 2
            feedback.append(f"C5a: Recommendation contains only {keyword_hits} relevant terms (+2)")

        # Check for a clear yes/no determination
        has_determination = any(phrase in rec_lower for phrase in
                                ["can handle", "cannot handle", "can not handle",
                                 "recommend", "not recommend", "feasible",
                                 "infeasible", "acceptable", "unacceptable",
                                 "within", "exceed", "below"])
        if has_determination:
            c5_score += 5
            feedback.append("C5b: Contains clear recommendation/determination (+5)")
        else:
            feedback.append("C5b: No clear recommendation/determination found (+0)")

        score += c5_score
    elif rec_exists:
        score += 3
        feedback.append(f"C5: Recommendation exists but too short ({rec_length} chars) (+3)")
    else:
        feedback.append("C5: Recommendation file not found (+0)")

    # --- C6: Wrong-target gate - plausibility check (10 pts) ---
    if report_exists and report_content:
        try:
            reader = csv.DictReader(io.StringIO(report_content))
            rows = list(reader)
            plausible = True
            for row in rows:
                try:
                    bv = float(row.get("baseline_value", "0"))
                    wv = float(row.get("with_trucks_value", "0"))
                    # Travel times should be positive and reasonable (1-10000 seconds)
                    metric = row.get("metric", "").lower()
                    if "time" in metric:
                        if not (0.1 < bv < 10000 and 0.1 < wv < 10000):
                            plausible = False
                    # Speeds should be positive and < 200 m/s
                    if "speed" in metric:
                        if not (0 < bv < 200 and 0 < wv < 200):
                            plausible = False
                except (ValueError, TypeError):
                    pass

            if plausible:
                score += 10
                feedback.append("C6: Report values are numerically plausible (+10)")
            else:
                feedback.append("C6: Report contains implausible values (+0)")
        except Exception:
            score += 5
            feedback.append("C6: Could not validate plausibility, partial credit (+5)")
    else:
        feedback.append("C6: No report to validate (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
