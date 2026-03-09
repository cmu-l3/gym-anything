#!/usr/bin/env python3
"""Verifier for traffic_calming_zone_design task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran and tripinfo saved (15 pts)
  C2: Network modified with >= 8 edges reduced to 30 km/h (20 pts)
  C3: Modified simulation ran and tripinfo saved (15 pts)
  C4: Before-after report CSV with correct structure and metrics (25 pts)
  C5: Engineering summary with zone design documentation (15 pts)
  C6: Report values show plausible speed reduction in zone (10 pts)
"""

import json
import csv
import tempfile
import os
import io
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/traffic_calming_zone_design_result.json"

REQUIRED_METRICS = [
    "zone_avg_speed",
    "corridor_avg_travel_time",
    "total_throughput",
    "zone_85th_percentile_speed",
    "corridor_avg_speed",
]

REQUIRED_COLUMNS = ["metric", "baseline_value", "calming_value", "change_pct"]


def verify_traffic_calming_zone_design(traj, env_info, task_info):
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
    network_modified = result.get("network_modified", False)
    report_exists = result.get("report_exists", False)
    baseline_exists = result.get("baseline_exists", False)
    calming_exists = result.get("calming_exists", False)

    if not network_modified and not report_exists and not baseline_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No network modifications, simulations, or report found."}

    # --- C1: Baseline simulation (15 pts) ---
    baseline_size = result.get("baseline_size", 0)
    if baseline_exists and baseline_size > 1000:
        score += 15
        feedback.append(f"C1: Baseline tripinfo saved ({baseline_size} bytes) (+15)")
    elif baseline_exists:
        score += 8
        feedback.append(f"C1: Baseline tripinfo exists but small ({baseline_size} bytes) (+8)")
    else:
        feedback.append("C1: Baseline tripinfo not found (+0)")

    # --- C2: Network modified with 30 km/h zone (20 pts) ---
    edges_30 = result.get("edges_with_30kmh", 0)
    if edges_30 >= 8:
        score += 20
        feedback.append(f"C2: {edges_30} edges modified to 30 km/h (target: 8) (+20)")
    elif edges_30 >= 5:
        score += 14
        feedback.append(f"C2: {edges_30} edges modified to 30 km/h (target: 8) (+14)")
    elif edges_30 >= 3:
        score += 8
        feedback.append(f"C2: {edges_30} edges modified to 30 km/h (target: 8) (+8)")
    elif edges_30 >= 1:
        score += 4
        feedback.append(f"C2: Only {edges_30} edge(s) modified to 30 km/h (target: 8) (+4)")
    elif network_modified:
        score += 2
        feedback.append("C2: Network modified but no 30 km/h edges detected (+2)")
    else:
        feedback.append("C2: Network not modified — no speed reductions applied (+0)")

    # --- C3: Modified simulation ran (15 pts) ---
    calming_size = result.get("calming_size", 0)
    if calming_exists and calming_size > 1000:
        score += 15
        feedback.append(f"C3: Calming simulation tripinfo saved ({calming_size} bytes) (+15)")
    elif calming_exists:
        score += 8
        feedback.append(f"C3: Calming tripinfo exists but small ({calming_size} bytes) (+8)")
    else:
        feedback.append("C3: Calming simulation tripinfo not found (+0)")

    # --- C4: Before-after report CSV (25 pts) ---
    report_content = result.get("report_content", "")
    parsed_rows = []
    if report_exists and report_content:
        c4_score = 0
        try:
            reader = csv.DictReader(io.StringIO(report_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            cols_present = sum(1 for c in REQUIRED_COLUMNS if c in fieldnames)
            if cols_present >= 4:
                c4_score += 7
                feedback.append("C4a: All 4 required columns present (+7)")
            elif cols_present >= 3:
                c4_score += 4
                feedback.append(f"C4a: {cols_present}/4 required columns present (+4)")
            else:
                feedback.append(f"C4a: Only {cols_present}/4 columns present (+0)")

            parsed_rows = list(reader)
            metrics_found = set()
            for row in parsed_rows:
                metric = row.get("metric", "").strip().lower().replace(" ", "_")
                for req in REQUIRED_METRICS:
                    if req in metric or metric in req:
                        metrics_found.add(req)

            if len(metrics_found) >= 5:
                c4_score += 10
                feedback.append(f"C4b: All {len(metrics_found)} required metrics present (+10)")
            elif len(metrics_found) >= 3:
                c4_score += 6
                feedback.append(f"C4b: {len(metrics_found)}/5 required metrics present (+6)")
            elif len(metrics_found) >= 1:
                c4_score += 3
                feedback.append(f"C4b: {len(metrics_found)}/5 required metrics present (+3)")
            else:
                feedback.append("C4b: No required metrics found (+0)")

            # Check for numeric values
            numeric_valid = 0
            for row in parsed_rows:
                try:
                    bv = float(row.get("baseline_value", ""))
                    cv = float(row.get("calming_value", ""))
                    if bv > 0 and cv > 0:
                        numeric_valid += 1
                except (ValueError, TypeError):
                    pass

            if numeric_valid >= 4:
                c4_score += 8
                feedback.append(f"C4c: {numeric_valid} metrics have valid numeric before/after values (+8)")
            elif numeric_valid >= 2:
                c4_score += 4
                feedback.append(f"C4c: {numeric_valid} metrics have valid numeric values (+4)")
            else:
                feedback.append(f"C4c: Only {numeric_valid} valid numeric entries (+0)")

        except Exception as e:
            feedback.append(f"C4: Error parsing CSV: {e} (+0)")

        score += c4_score
    else:
        feedback.append("C4: Report CSV not found or empty (+0)")

    # --- C5: Engineering summary (15 pts) ---
    summary_exists = result.get("summary_exists", False)
    summary_content = result.get("summary_content", "")
    summary_length = result.get("summary_length", 0)

    if summary_exists and summary_length > 100:
        c5_score = 0
        summary_lower = summary_content.lower()

        design_keywords = ["zone", "30", "km/h", "speed", "calming", "residential",
                           "edge", "arterial", "corridor", "traffic", "reduce",
                           "safety", "limit"]
        hits = sum(1 for k in design_keywords if k in summary_lower)
        if hits >= 5:
            c5_score += 10
            feedback.append(f"C5a: Summary contains {hits} traffic calming terms (+10)")
        elif hits >= 3:
            c5_score += 6
            feedback.append(f"C5a: Summary contains {hits} traffic calming terms (+6)")
        else:
            c5_score += 2
            feedback.append(f"C5a: Summary has {hits} relevant terms (+2)")

        impact_keywords = ["impact", "throughput", "travel time", "before",
                           "after", "comparison", "reduction", "maintain",
                           "arterial", "capacity"]
        imp_hits = sum(1 for k in impact_keywords if k in summary_lower)
        if imp_hits >= 3:
            c5_score += 5
            feedback.append("C5b: Summary discusses impact assessment (+5)")
        elif imp_hits >= 1:
            c5_score += 2
            feedback.append("C5b: Summary partially discusses impact (+2)")
        else:
            feedback.append("C5b: No impact assessment in summary (+0)")

        score += c5_score
    elif summary_exists:
        score += 3
        feedback.append(f"C5: Summary exists but short ({summary_length} chars) (+3)")
    else:
        feedback.append("C5: Summary file not found (+0)")

    # --- C6: Plausible speed reduction in report (10 pts) ---
    if parsed_rows:
        speed_reduced = False
        for row in parsed_rows:
            metric = row.get("metric", "").strip().lower()
            if "zone" in metric and "speed" in metric:
                try:
                    bv = float(row.get("baseline_value", "0"))
                    cv = float(row.get("calming_value", "0"))
                    if cv < bv and cv > 0:
                        speed_reduced = True
                except (ValueError, TypeError):
                    pass

        if speed_reduced:
            score += 10
            feedback.append("C6: Report shows plausible speed reduction in calming zone (+10)")
        else:
            feedback.append("C6: No speed reduction evidence in report data (+0)")
    else:
        feedback.append("C6: No report data to validate (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
