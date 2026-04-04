#!/usr/bin/env python3
"""Verifier for intersection_safety_audit task.

Scoring breakdown (100 points, pass >= 60):
  C1: SSM device configured and SSM output file generated (20 pts)
  C2: Simulation ran to completion with tripinfo output (15 pts)
  C3: Safety report CSV has correct structure with required columns (20 pts)
  C4: Report contains plausible junction data with risk ratings (20 pts)
  C5: Summary identifies highest-risk junction and recommends countermeasures (15 pts)
  C6: Wrong-target gate - reported junctions must be real network junctions (10 pts)
"""

import json
import csv
import tempfile
import os
import io
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/intersection_safety_audit_result.json"

REQUIRED_COLUMNS = [
    "junction_id", "junction_type", "num_ttc_critical",
    "num_drac_critical", "total_conflicts", "risk_rating"
]


def verify_intersection_safety_audit(traj, env_info, task_info):
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
    ssm_exists = result.get("ssm_exists", False)
    report_exists = result.get("report_exists", False)
    sim_ran = result.get("sim_ran", False)

    if not ssm_exists and not report_exists and not sim_ran:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No SSM output, report, or simulation evidence found."}

    # --- C1: SSM device configured and output generated (20 pts) ---
    ssm_configured = result.get("ssm_configured", False)
    ssm_has_conflicts = result.get("ssm_has_conflicts", False)
    ssm_size = result.get("ssm_size", 0)

    if ssm_exists and ssm_has_conflicts and ssm_size > 1000:
        score += 20
        feedback.append(f"C1: SSM output exists with conflict data ({ssm_size} bytes) (+20)")
    elif ssm_exists and ssm_size > 100:
        score += 12
        feedback.append(f"C1: SSM output exists but may lack conflict data ({ssm_size} bytes) (+12)")
    elif ssm_configured:
        score += 5
        feedback.append("C1: SSM device configured but no output generated (+5)")
    else:
        feedback.append("C1: SSM device not configured and no output found (+0)")

    # --- C2: Simulation ran to completion (15 pts) ---
    if sim_ran:
        score += 15
        feedback.append("C2: Simulation ran and produced tripinfo output (+15)")
    elif ssm_exists and ssm_size > 1000:
        score += 10
        feedback.append("C2: SSM output suggests simulation ran, but no tripinfo (+10)")
    else:
        feedback.append("C2: No evidence of simulation completion (+0)")

    # --- C3: Report CSV structure (20 pts) ---
    report_content = result.get("report_content", "")
    parsed_rows = []
    if report_exists and report_content:
        c3_score = 0
        try:
            reader = csv.DictReader(io.StringIO(report_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            cols_present = sum(1 for c in REQUIRED_COLUMNS if c in fieldnames)
            if cols_present >= 6:
                c3_score += 10
                feedback.append("C3a: All 6 required columns present (+10)")
            elif cols_present >= 4:
                c3_score += 6
                feedback.append(f"C3a: {cols_present}/6 required columns present (+6)")
            elif cols_present >= 2:
                c3_score += 3
                feedback.append(f"C3a: {cols_present}/6 required columns present (+3)")
            else:
                feedback.append(f"C3a: Only {cols_present}/6 required columns present (+0)")

            parsed_rows = list(reader)
            data_rows = len(parsed_rows)
            if data_rows >= 3:
                c3_score += 10
                feedback.append(f"C3b: {data_rows} junction data rows in report (+10)")
            elif data_rows >= 1:
                c3_score += 5
                feedback.append(f"C3b: Only {data_rows} junction data rows (+5)")
            else:
                feedback.append("C3b: No data rows in report (+0)")

        except Exception as e:
            feedback.append(f"C3: Error parsing CSV: {e} (+0)")

        score += c3_score
    else:
        feedback.append("C3: Report CSV not found or empty (+0)")

    # --- C4: Plausible junction data with risk ratings (20 pts) ---
    if parsed_rows:
        c4_score = 0
        has_risk_ratings = False
        valid_ratings = 0
        numeric_conflict_data = 0

        for row in parsed_rows:
            # Normalize keys
            row_lower = {k.strip().lower(): v for k, v in row.items()}

            # Check risk ratings
            rating = row_lower.get("risk_rating", "").strip().upper()
            if rating in ("HIGH", "MEDIUM", "LOW"):
                valid_ratings += 1
                has_risk_ratings = True

            # Check numeric conflict counts
            try:
                ttc = int(row_lower.get("num_ttc_critical", row_lower.get("ttc_critical", "0")))
                drac = int(row_lower.get("num_drac_critical", row_lower.get("drac_critical", "0")))
                total = int(row_lower.get("total_conflicts", row_lower.get("conflicts", "0")))
                if ttc >= 0 and drac >= 0 and total >= 0:
                    numeric_conflict_data += 1
            except (ValueError, TypeError):
                pass

        if valid_ratings >= 3:
            c4_score += 10
            feedback.append(f"C4a: {valid_ratings} junctions have valid risk ratings (+10)")
        elif valid_ratings >= 1:
            c4_score += 5
            feedback.append(f"C4a: {valid_ratings} junctions have valid risk ratings (+5)")
        else:
            feedback.append("C4a: No valid risk ratings found (+0)")

        if numeric_conflict_data >= 3:
            c4_score += 10
            feedback.append(f"C4b: {numeric_conflict_data} rows have valid numeric conflict data (+10)")
        elif numeric_conflict_data >= 1:
            c4_score += 5
            feedback.append(f"C4b: {numeric_conflict_data} rows have valid numeric data (+5)")
        else:
            feedback.append("C4b: No valid numeric conflict data found (+0)")

        score += c4_score
    else:
        feedback.append("C4: No parsed data to evaluate (+0)")

    # --- C5: Summary with highest-risk junction and countermeasures (15 pts) ---
    summary_exists = result.get("summary_exists", False)
    summary_content = result.get("summary_content", "")
    summary_length = result.get("summary_length", 0)

    if summary_exists and summary_length > 80:
        c5_score = 0
        summary_lower = summary_content.lower()

        # Check for junction identification
        safety_keywords = ["junction", "intersection", "risk", "high",
                           "dangerous", "critical", "ttc", "collision",
                           "conflict", "safety"]
        keyword_hits = sum(1 for k in safety_keywords if k in summary_lower)
        if keyword_hits >= 4:
            c5_score += 8
            feedback.append(f"C5a: Summary contains {keyword_hits} safety-relevant terms (+8)")
        elif keyword_hits >= 2:
            c5_score += 4
            feedback.append(f"C5a: Summary contains {keyword_hits} safety-relevant terms (+4)")
        else:
            feedback.append(f"C5a: Summary lacks safety-relevant terminology (+0)")

        # Check for countermeasure recommendations
        countermeasure_keywords = ["recommend", "countermeasure", "improve",
                                   "signal", "redesign", "reduce", "install",
                                   "phase", "timing", "geometry", "protected",
                                   "pedestrian", "speed", "calming"]
        cm_hits = sum(1 for k in countermeasure_keywords if k in summary_lower)
        if cm_hits >= 3:
            c5_score += 7
            feedback.append(f"C5b: Summary contains {cm_hits} countermeasure terms (+7)")
        elif cm_hits >= 1:
            c5_score += 3
            feedback.append(f"C5b: Summary contains {cm_hits} countermeasure terms (+3)")
        else:
            feedback.append("C5b: No countermeasure recommendations found (+0)")

        score += c5_score
    elif summary_exists:
        score += 2
        feedback.append(f"C5: Summary exists but too short ({summary_length} chars) (+2)")
    else:
        feedback.append("C5: Summary file not found (+0)")

    # --- C6: Wrong-target gate - junctions must be real (10 pts) ---
    junction_info = result.get("junction_info", {})
    real_junction_ids = set(junction_info.keys()) - {"error"}

    if parsed_rows and real_junction_ids:
        reported_ids = set()
        for row in parsed_rows:
            row_lower = {k.strip().lower(): v for k, v in row.items()}
            jid = row_lower.get("junction_id", "").strip()
            if jid:
                reported_ids.add(jid)

        if reported_ids:
            valid_ids = reported_ids & real_junction_ids
            if len(valid_ids) >= len(reported_ids) * 0.5:
                score += 10
                feedback.append(f"C6: {len(valid_ids)}/{len(reported_ids)} reported junctions are real network junctions (+10)")
            elif len(valid_ids) >= 1:
                score += 5
                feedback.append(f"C6: Only {len(valid_ids)}/{len(reported_ids)} junctions match real network (+5)")
            else:
                feedback.append(f"C6: No reported junctions match real network junction IDs (+0)")
        else:
            feedback.append("C6: No junction IDs found in report (+0)")
    else:
        score += 5
        feedback.append("C6: Could not validate junction IDs (partial credit) (+5)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
