#!/usr/bin/env python3
"""Verifier for public_transit_service_redesign task.

Scoring breakdown (100 points, pass >= 60):
  C1: New bus stops added to the network (>= 4 new stops) (20 pts)
  C2: Express bus line created with >= 3 vehicles and proper stop sequence (20 pts)
  C3: Pedestrian/person trips added (>= 50 person trips) (15 pts)
  C4: Modified simulation ran to completion (15 pts)
  C5: Service report CSV with correct structure and stop-level data (20 pts)
  C6: Service improvement summary with substantive analysis (10 pts)
"""

import json
import csv
import tempfile
import os
import io
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/public_transit_service_redesign_result.json"

REQUIRED_COLUMNS = [
    "stop_id", "stop_name_or_lane", "is_new", "line_served",
    "boarding_count", "alighting_count"
]


def verify_public_transit_service_redesign(traj, env_info, task_info):
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

    initial_data = result.get("initial_data", {})
    initial_stop_count = initial_data.get("initial_stop_count", 0)
    initial_bus_count = initial_data.get("initial_bus_count", 0)

    # --- Do-nothing gate ---
    current_stops = result.get("current_stop_count", 0)
    total_buses = result.get("total_bus_count", 0)
    person_trips = result.get("person_trip_count", 0)
    report_exists = result.get("report_exists", False)

    new_stops_added = current_stops - initial_stop_count if current_stops > initial_stop_count else 0
    new_buses_added = total_buses - initial_bus_count if total_buses > initial_bus_count else 0

    if new_stops_added == 0 and new_buses_added == 0 and person_trips == 0 and not report_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No new stops, buses, person trips, or report found."}

    # --- C1: New bus stops (20 pts) ---
    if new_stops_added >= 4:
        score += 20
        feedback.append(f"C1: {new_stops_added} new bus stops added (target: 4) (+20)")
    elif new_stops_added >= 2:
        score += 12
        feedback.append(f"C1: {new_stops_added} new bus stops added (target: 4) (+12)")
    elif new_stops_added >= 1:
        score += 6
        feedback.append(f"C1: {new_stops_added} new bus stop added (target: 4) (+6)")
    else:
        feedback.append(f"C1: No new bus stops added (current: {current_stops}, initial: {initial_stop_count}) (+0)")

    # --- C2: Express bus line with vehicles (20 pts) ---
    express_count = result.get("express_bus_count", 0)
    if express_count >= 3:
        score += 20
        feedback.append(f"C2: {express_count} express bus vehicles created (target: 3) (+20)")
    elif express_count >= 2:
        score += 14
        feedback.append(f"C2: {express_count} express bus vehicles created (target: 3) (+14)")
    elif express_count >= 1:
        score += 8
        feedback.append(f"C2: {express_count} express bus vehicle created (target: 3) (+8)")
    elif new_buses_added >= 3:
        score += 12
        feedback.append(f"C2: {new_buses_added} new bus vehicles added (not named express) (+12)")
    elif new_buses_added >= 1:
        score += 5
        feedback.append(f"C2: {new_buses_added} new bus vehicles added (not named express) (+5)")
    else:
        feedback.append("C2: No new bus vehicles found (+0)")

    # --- C3: Person trips (15 pts) ---
    if person_trips >= 50:
        score += 15
        feedback.append(f"C3: {person_trips} person trips added (target: 50) (+15)")
    elif person_trips >= 30:
        score += 10
        feedback.append(f"C3: {person_trips} person trips added (target: 50) (+10)")
    elif person_trips >= 10:
        score += 6
        feedback.append(f"C3: {person_trips} person trips added (target: 50) (+6)")
    elif person_trips >= 1:
        score += 3
        feedback.append(f"C3: {person_trips} person trips added (target: 50) (+3)")
    else:
        feedback.append("C3: No person trips found (+0)")

    # --- C4: Simulation ran (15 pts) ---
    sim_ran = result.get("sim_ran", False)
    tripinfo_size = result.get("tripinfo_size", 0)

    if sim_ran and tripinfo_size > 1000:
        score += 15
        feedback.append(f"C4: Simulation ran with substantial output ({tripinfo_size} bytes) (+15)")
    elif sim_ran:
        score += 10
        feedback.append(f"C4: Simulation ran but small tripinfo ({tripinfo_size} bytes) (+10)")
    elif result.get("modified_cfg", False):
        score += 3
        feedback.append("C4: Modified config created but simulation may not have completed (+3)")
    else:
        feedback.append("C4: No evidence simulation ran (+0)")

    # --- C5: Service report CSV (20 pts) ---
    report_content = result.get("report_content", "")
    if report_exists and report_content:
        c5_score = 0
        try:
            reader = csv.DictReader(io.StringIO(report_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            cols_present = sum(1 for c in REQUIRED_COLUMNS if c in fieldnames)
            if cols_present >= 5:
                c5_score += 8
                feedback.append(f"C5a: {cols_present}/6 required columns present (+8)")
            elif cols_present >= 3:
                c5_score += 4
                feedback.append(f"C5a: {cols_present}/6 required columns present (+4)")
            else:
                feedback.append(f"C5a: Only {cols_present}/6 required columns present (+0)")

            rows = list(reader)
            if len(rows) >= 5:
                c5_score += 6
                feedback.append(f"C5b: {len(rows)} stop data rows (+6)")
            elif len(rows) >= 2:
                c5_score += 3
                feedback.append(f"C5b: {len(rows)} stop data rows (+3)")
            else:
                feedback.append(f"C5b: Only {len(rows)} data rows (+0)")

            # Check for new stops marked
            has_new_marker = any(
                row.get("is_new", "").strip().lower() in ("true", "yes", "1", "new")
                for row in rows
            )
            if has_new_marker:
                c5_score += 6
                feedback.append("C5c: Report distinguishes new vs existing stops (+6)")
            else:
                feedback.append("C5c: No stops marked as new in report (+0)")

        except Exception as e:
            feedback.append(f"C5: Error parsing CSV: {e} (+0)")

        score += c5_score
    else:
        feedback.append("C5: Report CSV not found or empty (+0)")

    # --- C6: Service improvement summary (10 pts) ---
    summary_exists = result.get("summary_exists", False)
    summary_content = result.get("summary_content", "")
    summary_length = result.get("summary_length", 0)

    if summary_exists and summary_length > 80:
        c6_score = 0
        summary_lower = summary_content.lower()

        transit_keywords = ["bus", "route", "stop", "service", "coverage",
                            "frequency", "headway", "passenger", "ridership",
                            "transit", "express", "line", "pedestrian"]
        hits = sum(1 for k in transit_keywords if k in summary_lower)

        if hits >= 5:
            c6_score += 7
            feedback.append(f"C6a: Summary contains {hits} transit-relevant terms (+7)")
        elif hits >= 3:
            c6_score += 4
            feedback.append(f"C6a: Summary contains {hits} transit-relevant terms (+4)")
        else:
            c6_score += 1
            feedback.append(f"C6a: Summary contains only {hits} transit-relevant terms (+1)")

        improvement_keywords = ["improve", "increase", "added", "new", "connect",
                                "reduce", "better", "enhance", "expand"]
        imp_hits = sum(1 for k in improvement_keywords if k in summary_lower)
        if imp_hits >= 2:
            c6_score += 3
            feedback.append("C6b: Summary describes improvements (+3)")
        else:
            feedback.append("C6b: Summary lacks improvement description (+0)")

        score += c6_score
    elif summary_exists:
        score += 2
        feedback.append(f"C6: Summary exists but short ({summary_length} chars) (+2)")
    else:
        feedback.append("C6: Summary file not found (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
