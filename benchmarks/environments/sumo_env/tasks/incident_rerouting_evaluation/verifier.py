#!/usr/bin/env python3
"""Verifier for incident_rerouting_evaluation task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran and network performance CSV produced (15 pts)
  C2: Rerouter additional file with valid rerouter elements closing >= 2 edges (20 pts)
  C3: Incident sumocfg created and incident simulation ran (15 pts)
  C4: Incident network performance CSV with valid numeric data (20 pts)
  C5: Incident assessment report with location, comparison, resilience analysis (15 pts)
  C6: Incident scenario shows plausible network degradation (15 pts)
"""

import json
import csv
import tempfile
import os
import io
import re
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/incident_rerouting_evaluation_result.json"

REQUIRED_METRICS = ["total_completed_trips", "avg_travel_time", "avg_time_loss", "total_vehicle_hours_delay"]


def verify_incident_rerouting_evaluation(traj, env_info, task_info):
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
    rerouter_exists = result.get("rerouter_file_exists", False)
    incident_cfg_exists = result.get("incident_cfg_exists", False)
    incident_metrics_exists = result.get("incident_metrics_exists", False)
    report_exists = result.get("report_exists", False)

    if not baseline_exists and not rerouter_exists and not incident_cfg_exists and not report_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No outputs found."}

    # --- C1: Baseline network performance CSV (15 pts) ---
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

            rows = list(reader)
            metrics_found = 0
            for row in rows:
                m = row.get("metric", "").strip().lower()
                try:
                    v = float(row.get("value", ""))
                    if v >= 0:
                        metrics_found += 1
                        baseline_parsed[m] = v
                except (ValueError, TypeError):
                    pass

            if metrics_found >= 4:
                c1_score += 10
                feedback.append(f"C1b: {metrics_found} metrics with valid values (+10)")
            elif metrics_found >= 2:
                c1_score += 6
                feedback.append(f"C1b: {metrics_found} metrics with valid values (+6)")
            elif metrics_found >= 1:
                c1_score += 3
                feedback.append(f"C1b: {metrics_found} metric(s) found (+3)")
            else:
                feedback.append("C1b: No valid metrics found (+0)")
        except Exception as e:
            feedback.append(f"C1: Error parsing CSV: {e} (+0)")

        score += c1_score
    else:
        feedback.append("C1: Baseline performance CSV not found or empty (+0)")

    # --- C2: Rerouter file with valid elements (20 pts) ---
    if rerouter_exists:
        c2_score = 0
        rerouter_count = result.get("rerouter_count", 0)
        closed_edges = result.get("closed_edges", [])
        has_closing = result.get("rerouter_has_closing", False)
        has_dest_prob = result.get("rerouter_has_dest_prob", False)

        if rerouter_count >= 1:
            c2_score += 5
            feedback.append(f"C2a: {rerouter_count} rerouter element(s) found (+5)")
        else:
            feedback.append("C2a: No rerouter elements in file (+0)")

        if len(closed_edges) >= 2:
            c2_score += 8
            feedback.append(f"C2b: {len(closed_edges)} edges affected by rerouters (target >= 2) (+8)")
        elif len(closed_edges) >= 1:
            c2_score += 4
            feedback.append(f"C2b: {len(closed_edges)} edge affected (target >= 2) (+4)")
        else:
            feedback.append("C2b: No edges specified in rerouters (+0)")

        if has_closing or has_dest_prob:
            c2_score += 7
            reroute_types = []
            if has_closing:
                reroute_types.append("closingReroute")
            if has_dest_prob:
                reroute_types.append("destProbReroute/routeProbReroute")
            feedback.append(f"C2c: Rerouting mechanism present: {', '.join(reroute_types)} (+7)")
        else:
            # Check if file at least has rerouter structure
            if rerouter_count > 0:
                c2_score += 3
                feedback.append("C2c: Rerouter defined but no closing/reroute mechanism found (+3)")
            else:
                feedback.append("C2c: No rerouting mechanism found (+0)")

        score += c2_score
    else:
        feedback.append("C2: Rerouter file not found (+0)")

    # --- C3: Incident sumocfg and simulation (15 pts) ---
    if incident_cfg_exists:
        c3_score = 0
        cfg_content = result.get("incident_cfg_content", "")

        if "incident_rerouters" in cfg_content or "rerouter" in cfg_content.lower():
            c3_score += 8
            feedback.append("C3a: Incident sumocfg references rerouter file (+8)")
        elif cfg_content:
            c3_score += 4
            feedback.append("C3a: Incident sumocfg exists but may not reference rerouters (+4)")
        else:
            feedback.append("C3a: Incident sumocfg is empty (+0)")

        if result.get("tripinfo_incident_exists", False):
            c3_score += 7
            feedback.append("C3b: Incident simulation tripinfo output found (+7)")
        elif incident_metrics_exists:
            c3_score += 5
            feedback.append("C3b: No tripinfo but incident metrics exist (sim likely ran) (+5)")
        else:
            feedback.append("C3b: No evidence incident simulation ran (+0)")

        score += c3_score
    else:
        feedback.append("C3: Incident sumocfg not found (+0)")

    # --- C4: Incident network performance CSV (20 pts) ---
    incident_parsed = {}
    if incident_metrics_exists:
        incident_content = result.get("incident_metrics_content", "")
        c4_score = 0
        try:
            reader = csv.DictReader(io.StringIO(incident_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            if "metric" in fieldnames and "value" in fieldnames:
                c4_score += 5
                feedback.append("C4a: Incident CSV has correct columns (+5)")

            rows = list(reader)
            metrics_found = 0
            for row in rows:
                m = row.get("metric", "").strip().lower()
                try:
                    v = float(row.get("value", ""))
                    if v >= 0:
                        metrics_found += 1
                        incident_parsed[m] = v
                except (ValueError, TypeError):
                    pass

            if metrics_found >= 4:
                c4_score += 15
                feedback.append(f"C4b: {metrics_found} metrics with valid values (+15)")
            elif metrics_found >= 2:
                c4_score += 8
                feedback.append(f"C4b: {metrics_found} metrics with valid values (+8)")
            elif metrics_found >= 1:
                c4_score += 4
                feedback.append(f"C4b: {metrics_found} metric(s) found (+4)")
            else:
                feedback.append("C4b: No valid metrics found (+0)")
        except Exception as e:
            feedback.append(f"C4: Error parsing CSV: {e} (+0)")

        score += c4_score
    else:
        feedback.append("C4: Incident performance CSV not found (+0)")

    # --- C5: Incident assessment report (15 pts) ---
    report_content = result.get("report_content", "")
    report_length = result.get("report_length", 0)

    if report_exists and report_length > 100:
        c5_score = 0
        report_lower = report_content.lower()

        incident_keywords = ["incident", "collision", "closure", "reroute", "rerouting",
                            "detour", "resilience", "degradation", "delay", "congestion",
                            "capacity", "alternate", "diversion", "blocked", "closed",
                            "travel time", "network", "impact", "assessment"]
        hits = sum(1 for k in incident_keywords if k in report_lower)
        if hits >= 6:
            c5_score += 8
            feedback.append(f"C5a: Report contains {hits} relevant incident terms (+8)")
        elif hits >= 3:
            c5_score += 5
            feedback.append(f"C5a: Report contains {hits} relevant terms (+5)")
        else:
            c5_score += 2
            feedback.append(f"C5a: Report has {hits} relevant terms (+2)")

        numbers = re.findall(r'\d+\.?\d*\s*%', report_content)
        if len(numbers) >= 2:
            c5_score += 7
            feedback.append(f"C5b: Report includes {len(numbers)} percentage values (+7)")
        elif len(numbers) >= 1:
            c5_score += 4
            feedback.append(f"C5b: Report includes {len(numbers)} percentage value (+4)")
        else:
            any_numbers = re.findall(r'\d+\.?\d*', report_content)
            if len(any_numbers) >= 5:
                c5_score += 3
                feedback.append("C5b: Report has numerical data but no percentage format (+3)")
            else:
                feedback.append("C5b: No numerical results in report (+0)")

        score += c5_score
    elif report_exists:
        score += 2
        feedback.append(f"C5: Report exists but short ({report_length} chars) (+2)")
    else:
        feedback.append("C5: Report not found (+0)")

    # --- C6: Plausible network degradation (15 pts) ---
    if baseline_parsed and incident_parsed:
        c6_score = 0
        degradations = []

        # For incident, we expect metrics to WORSEN (travel time up, delay up)
        for metric_key in baseline_parsed:
            bv = baseline_parsed.get(metric_key, 0)
            iv = incident_parsed.get(metric_key, 0)
            if bv > 0 and iv > 0:
                if "time" in metric_key or "delay" in metric_key or "loss" in metric_key:
                    if iv > bv:
                        pct = ((iv - bv) / bv) * 100
                        degradations.append(f"{metric_key}: +{pct:.1f}% increase")
                elif "trip" in metric_key or "completed" in metric_key:
                    if iv < bv:
                        pct = ((bv - iv) / bv) * 100
                        degradations.append(f"{metric_key}: {pct:.1f}% decrease")

        if len(degradations) >= 2:
            c6_score += 15
            feedback.append(f"C6: Incident scenario shows degradation in {len(degradations)} metrics: {'; '.join(degradations[:3])} (+15)")
        elif len(degradations) == 1:
            c6_score += 8
            feedback.append(f"C6: Degradation in 1 metric: {degradations[0]} (+8)")
        else:
            # Check if both sets have plausible data
            if len(incident_parsed) >= 2:
                c6_score += 4
                feedback.append("C6: Incident metrics exist but no clear degradation pattern (+4)")
            else:
                feedback.append("C6: Cannot verify degradation (+0)")

        score += c6_score
    else:
        feedback.append("C6: Cannot compare - baseline or incident data missing (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
