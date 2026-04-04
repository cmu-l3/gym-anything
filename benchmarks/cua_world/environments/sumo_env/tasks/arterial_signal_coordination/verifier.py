#!/usr/bin/env python3
"""Verifier for arterial_signal_coordination task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran and corridor metrics CSV produced (15 pts)
  C2: Coordinated TLS file with offset modifications for >= 4 intersections (20 pts)
  C3: Modified sumocfg created and coordinated simulation ran (15 pts)
  C4: Coordinated corridor metrics CSV with valid numeric data (20 pts)
  C5: Signal coordination report with offsets, comparison, improvements (15 pts)
  C6: Coordinated simulation shows plausible corridor improvement (15 pts)
"""

import json
import csv
import tempfile
import os
import io
import re
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/arterial_signal_coordination_result.json"

REQUIRED_METRICS = ["avg_travel_time_s", "avg_waiting_time_s", "avg_time_loss_s", "total_vehicles"]


def verify_arterial_signal_coordination(traj, env_info, task_info):
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
    baseline_exists = result.get("baseline_metrics_exists", False)
    coord_tls_exists = result.get("coordinated_tls_exists", False)
    coord_cfg_exists = result.get("coordinated_cfg_exists", False)
    coord_metrics_exists = result.get("coordinated_metrics_exists", False)
    report_exists = result.get("report_exists", False)
    num_modified = result.get("num_modified_offsets", 0)

    if not baseline_exists and not coord_tls_exists and not coord_cfg_exists and not report_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No outputs found. No baseline metrics, coordinated TLS, config, or report."}

    # --- C1: Baseline corridor metrics CSV (15 pts) ---
    baseline_content = result.get("baseline_metrics_content", "")
    baseline_parsed = {}
    if baseline_exists and baseline_content:
        c1_score = 0
        try:
            reader = csv.DictReader(io.StringIO(baseline_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            if "metric" in fieldnames and "value" in fieldnames:
                c1_score += 5
                feedback.append("C1a: Baseline CSV has correct columns (+5)")
            else:
                feedback.append(f"C1a: Baseline CSV columns: {fieldnames} (expected metric,value) (+0)")

            rows = list(reader)
            metrics_found = set()
            for row in rows:
                m = row.get("metric", "").strip().lower()
                for req in REQUIRED_METRICS:
                    if req in m or m in req:
                        metrics_found.add(req)
                        try:
                            baseline_parsed[req] = float(row.get("value", ""))
                        except (ValueError, TypeError):
                            pass

            if len(metrics_found) >= 4:
                c1_score += 5
                feedback.append(f"C1b: All 4 required metrics present ({len(metrics_found)}) (+5)")
            elif len(metrics_found) >= 2:
                c1_score += 3
                feedback.append(f"C1b: {len(metrics_found)}/4 metrics present (+3)")
            else:
                feedback.append(f"C1b: Only {len(metrics_found)} metrics found (+0)")

            numeric_valid = sum(1 for v in baseline_parsed.values() if v > 0)
            if numeric_valid >= 3:
                c1_score += 5
                feedback.append(f"C1c: {numeric_valid} metrics have valid positive values (+5)")
            elif numeric_valid >= 1:
                c1_score += 2
                feedback.append(f"C1c: {numeric_valid} metrics with valid values (+2)")
            else:
                feedback.append("C1c: No valid numeric values in baseline (+0)")

        except Exception as e:
            feedback.append(f"C1: Error parsing baseline CSV: {e} (+0)")

        score += c1_score
    else:
        feedback.append("C1: Baseline corridor metrics CSV not found or empty (+0)")

    # --- C2: Coordinated TLS file with offset modifications (20 pts) ---
    if coord_tls_exists:
        c2_score = 0
        coord_size = result.get("coordinated_tls_size", 0)

        if coord_size > 500:
            c2_score += 5
            feedback.append(f"C2a: Coordinated TLS file exists ({coord_size} bytes) (+5)")
        elif coord_size > 0:
            c2_score += 2
            feedback.append(f"C2a: Coordinated TLS file exists but small ({coord_size} bytes) (+2)")
        else:
            feedback.append("C2a: Coordinated TLS file is empty (+0)")

        if num_modified >= 4:
            c2_score += 15
            feedback.append(f"C2b: {num_modified} intersections have modified offsets (target >= 4) (+15)")
        elif num_modified >= 2:
            c2_score += 8
            feedback.append(f"C2b: {num_modified} intersections have modified offsets (target >= 4) (+8)")
        elif num_modified >= 1:
            c2_score += 4
            feedback.append(f"C2b: Only {num_modified} intersection(s) modified (+4)")
        else:
            # Check if offsets exist but are same as original (all were 0)
            coord_offsets = result.get("coordinated_offsets", {})
            if coord_offsets and any(v != 0 for v in coord_offsets.values()):
                c2_score += 10
                feedback.append(f"C2b: Coordinated offsets found with non-zero values (+10)")
            else:
                feedback.append("C2b: No offset modifications detected (+0)")

        score += c2_score
    else:
        feedback.append("C2: Coordinated TLS file not found (+0)")

    # --- C3: Modified sumocfg and coordinated simulation (15 pts) ---
    if coord_cfg_exists:
        c3_score = 0
        cfg_content = result.get("coordinated_cfg_content", "")

        if "coordinated" in cfg_content.lower() or "acosta_tls_coordinated" in cfg_content:
            c3_score += 8
            feedback.append("C3a: Modified sumocfg references coordinated TLS file (+8)")
        elif cfg_content:
            c3_score += 4
            feedback.append("C3a: Modified sumocfg exists but may not reference coordinated TLS (+4)")
        else:
            feedback.append("C3a: Modified sumocfg is empty (+0)")

        # Check if coordinated simulation produced tripinfo
        if result.get("tripinfo_coordinated_exists", False):
            c3_score += 7
            feedback.append("C3b: Coordinated simulation tripinfo output found (+7)")
        elif coord_metrics_exists:
            c3_score += 5
            feedback.append("C3b: No tripinfo found but coordinated metrics exist (simulation likely ran) (+5)")
        else:
            feedback.append("C3b: No evidence coordinated simulation ran (+0)")

        score += c3_score
    else:
        feedback.append("C3: Modified sumocfg not found (+0)")

    # --- C4: Coordinated corridor metrics CSV (20 pts) ---
    coordinated_parsed = {}
    if coord_metrics_exists:
        coord_content = result.get("coordinated_metrics_content", "")
        c4_score = 0
        try:
            reader = csv.DictReader(io.StringIO(coord_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            if "metric" in fieldnames and "value" in fieldnames:
                c4_score += 5
                feedback.append("C4a: Coordinated CSV has correct columns (+5)")
            else:
                feedback.append(f"C4a: Coordinated CSV columns: {fieldnames} (+0)")

            rows = list(reader)
            metrics_found = set()
            for row in rows:
                m = row.get("metric", "").strip().lower()
                for req in REQUIRED_METRICS:
                    if req in m or m in req:
                        metrics_found.add(req)
                        try:
                            coordinated_parsed[req] = float(row.get("value", ""))
                        except (ValueError, TypeError):
                            pass

            if len(metrics_found) >= 4:
                c4_score += 7
                feedback.append(f"C4b: All 4 required metrics present ({len(metrics_found)}) (+7)")
            elif len(metrics_found) >= 2:
                c4_score += 4
                feedback.append(f"C4b: {len(metrics_found)}/4 metrics present (+4)")
            else:
                feedback.append(f"C4b: Only {len(metrics_found)} metrics found (+0)")

            numeric_valid = sum(1 for v in coordinated_parsed.values() if v > 0)
            if numeric_valid >= 3:
                c4_score += 8
                feedback.append(f"C4c: {numeric_valid} metrics have valid positive values (+8)")
            elif numeric_valid >= 1:
                c4_score += 4
                feedback.append(f"C4c: {numeric_valid} metrics with valid values (+4)")
            else:
                feedback.append("C4c: No valid numeric values in coordinated metrics (+0)")

        except Exception as e:
            feedback.append(f"C4: Error parsing coordinated CSV: {e} (+0)")

        score += c4_score
    else:
        feedback.append("C4: Coordinated corridor metrics CSV not found (+0)")

    # --- C5: Signal coordination report (15 pts) ---
    report_content = result.get("report_content", "")
    report_length = result.get("report_length", 0)

    if report_exists and report_length > 100:
        c5_score = 0
        report_lower = report_content.lower()

        signal_keywords = ["offset", "coordination", "green wave", "signal", "cycle",
                           "intersection", "travel time", "waiting", "delay",
                           "corridor", "arterial", "progressive", "bandwidth",
                           "phase", "timing", "speed", "improvement"]
        hits = sum(1 for k in signal_keywords if k in report_lower)
        if hits >= 6:
            c5_score += 8
            feedback.append(f"C5a: Report contains {hits} relevant engineering terms (+8)")
        elif hits >= 3:
            c5_score += 5
            feedback.append(f"C5a: Report contains {hits} relevant terms (+5)")
        else:
            c5_score += 2
            feedback.append(f"C5a: Report has {hits} relevant terms (+2)")

        numbers = re.findall(r'\d+\.?\d*\s*%', report_content)
        if len(numbers) >= 2:
            c5_score += 7
            feedback.append(f"C5b: Report includes {len(numbers)} percentage comparisons (+7)")
        elif len(numbers) >= 1:
            c5_score += 4
            feedback.append(f"C5b: Report includes {len(numbers)} percentage value (+4)")
        else:
            any_numbers = re.findall(r'\d+\.?\d*', report_content)
            if len(any_numbers) >= 5:
                c5_score += 3
                feedback.append("C5b: Report includes numerical data but no percentage format (+3)")
            else:
                feedback.append("C5b: No numerical results in report (+0)")

        score += c5_score
    elif report_exists:
        score += 2
        feedback.append(f"C5: Report exists but short ({report_length} chars) (+2)")
    else:
        feedback.append("C5: Report not found (+0)")

    # --- C6: Plausible corridor improvement (15 pts) ---
    if baseline_parsed and coordinated_parsed:
        c6_score = 0
        improvements = []

        for metric in ["avg_travel_time_s", "avg_waiting_time_s", "avg_time_loss_s"]:
            bv = baseline_parsed.get(metric, 0)
            cv = coordinated_parsed.get(metric, 0)
            if bv > 0 and cv > 0 and cv < bv:
                pct = ((bv - cv) / bv) * 100
                improvements.append(f"{metric}: {pct:.1f}% reduction")

        if len(improvements) >= 2:
            c6_score += 15
            feedback.append(f"C6: Coordinated sim shows improvement in {len(improvements)} metrics: {'; '.join(improvements)} (+15)")
        elif len(improvements) == 1:
            c6_score += 8
            feedback.append(f"C6: Improvement in 1 metric: {improvements[0]} (+8)")
        else:
            # Check if values are at least plausible (positive, reasonable range)
            plausible = 0
            for metric in ["avg_travel_time_s", "avg_waiting_time_s"]:
                cv = coordinated_parsed.get(metric, 0)
                if 0 < cv < 10000:
                    plausible += 1
            if plausible >= 2:
                c6_score += 4
                feedback.append("C6: Coordinated metrics are plausible but no improvement over baseline (+4)")
            else:
                feedback.append("C6: Cannot verify improvement - metrics missing or implausible (+0)")

        score += c6_score
    else:
        feedback.append("C6: Cannot compare metrics - baseline or coordinated data missing (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
