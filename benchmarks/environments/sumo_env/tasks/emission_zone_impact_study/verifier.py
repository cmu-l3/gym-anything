#!/usr/bin/env python3
"""Verifier for emission_zone_impact_study task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran with emission output (15 pts)
  C2: LEZ implemented using at least 2 strategies (20 pts)
  C3: LEZ simulation ran with emission output (15 pts)
  C4: Emission impact report CSV with correct pollutants and numeric data (25 pts)
  C5: Environmental impact summary with numerical results (15 pts)
  C6: Report shows plausible emission reductions (10 pts)
"""

import json
import csv
import tempfile
import os
import io
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/emission_zone_impact_study_result.json"

REQUIRED_POLLUTANTS = ["co2", "co", "nox", "pmx", "hc"]
REQUIRED_COLUMNS = ["pollutant", "baseline_total_mg", "lez_total_mg", "reduction_pct"]


def verify_emission_zone_impact_study(traj, env_info, task_info):
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
    baseline_exists = result.get("baseline_em_exists", False)
    lez_exists = result.get("lez_em_exists", False)
    report_exists = result.get("report_exists", False)
    modifications = result.get("modifications", {})
    strategies_used = modifications.get("strategies_used", 0)

    if not baseline_exists and not lez_exists and not report_exists and strategies_used == 0:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No emission outputs, modifications, or report found."}

    # --- C1: Baseline emission output (15 pts) ---
    baseline_size = result.get("baseline_em_size", 0)
    if baseline_exists and baseline_size > 1000:
        score += 15
        feedback.append(f"C1: Baseline emission output generated ({baseline_size} bytes) (+15)")
    elif baseline_exists and baseline_size > 100:
        score += 8
        feedback.append(f"C1: Baseline emission file exists but small ({baseline_size} bytes) (+8)")
    elif baseline_exists:
        score += 4
        feedback.append(f"C1: Baseline emission file exists but nearly empty ({baseline_size} bytes) (+4)")
    else:
        feedback.append("C1: No baseline emission output found (+0)")

    # --- C2: LEZ implementation with >= 2 strategies (20 pts) ---
    net_modified = modifications.get("net_modified", False)
    vtypes_modified = modifications.get("vtypes_modified", False)
    routes_modified = modifications.get("routes_modified", False)
    edges_disallow = modifications.get("edges_with_disallow", 0)

    strategy_details = []
    if net_modified:
        strategy_details.append(f"edge restrictions ({edges_disallow} edges)")
    if vtypes_modified:
        strategy_details.append("emission class changes")
    if routes_modified:
        strategy_details.append("modified routes")

    if strategies_used >= 2:
        score += 20
        feedback.append(f"C2: LEZ uses {strategies_used} strategies: {', '.join(strategy_details)} (+20)")
    elif strategies_used == 1:
        score += 10
        feedback.append(f"C2: LEZ uses only 1 strategy: {', '.join(strategy_details)} (target: 2) (+10)")
    else:
        feedback.append("C2: No LEZ implementation strategies detected (+0)")

    # --- C3: LEZ simulation with emission output (15 pts) ---
    lez_size = result.get("lez_em_size", 0)
    if lez_exists and lez_size > 1000:
        score += 15
        feedback.append(f"C3: LEZ simulation emission output generated ({lez_size} bytes) (+15)")
    elif lez_exists and lez_size > 100:
        score += 8
        feedback.append(f"C3: LEZ emission file exists but small ({lez_size} bytes) (+8)")
    elif lez_exists:
        score += 4
        feedback.append(f"C3: LEZ emission file exists but nearly empty ({lez_size} bytes) (+4)")
    else:
        feedback.append("C3: No LEZ emission output found (+0)")

    # --- C4: Emission impact report CSV (25 pts) ---
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
            pollutants_found = set()
            for row in parsed_rows:
                pollutant = row.get("pollutant", "").strip().lower()
                for req in REQUIRED_POLLUTANTS:
                    if req in pollutant or pollutant in req:
                        pollutants_found.add(req)

            if len(pollutants_found) >= 5:
                c4_score += 10
                feedback.append("C4b: All 5 required pollutants present (+10)")
            elif len(pollutants_found) >= 3:
                c4_score += 6
                feedback.append(f"C4b: {len(pollutants_found)}/5 pollutants present (+6)")
            elif len(pollutants_found) >= 1:
                c4_score += 3
                feedback.append(f"C4b: {len(pollutants_found)}/5 pollutants present (+3)")
            else:
                feedback.append("C4b: No required pollutants found (+0)")

            # Check numeric values
            numeric_valid = 0
            for row in parsed_rows:
                try:
                    bv = float(row.get("baseline_total_mg", ""))
                    lv = float(row.get("lez_total_mg", ""))
                    if bv > 0 and lv > 0:
                        numeric_valid += 1
                except (ValueError, TypeError):
                    pass

            if numeric_valid >= 4:
                c4_score += 8
                feedback.append(f"C4c: {numeric_valid} pollutants have valid numeric data (+8)")
            elif numeric_valid >= 2:
                c4_score += 4
                feedback.append(f"C4c: {numeric_valid} pollutants have valid numeric data (+4)")
            else:
                feedback.append(f"C4c: Only {numeric_valid} entries with valid data (+0)")

        except Exception as e:
            feedback.append(f"C4: Error parsing CSV: {e} (+0)")

        score += c4_score
    else:
        feedback.append("C4: Report CSV not found or empty (+0)")

    # --- C5: Environmental impact summary (15 pts) ---
    summary_exists = result.get("summary_exists", False)
    summary_content = result.get("summary_content", "")
    summary_length = result.get("summary_length", 0)

    if summary_exists and summary_length > 100:
        c5_score = 0
        summary_lower = summary_content.lower()

        env_keywords = ["emission", "pollut", "co2", "nox", "particulate", "pm",
                        "air quality", "lez", "low emission", "zone", "hbefa",
                        "environment", "carbon", "dioxide", "nitrogen"]
        hits = sum(1 for k in env_keywords if k in summary_lower)
        if hits >= 5:
            c5_score += 8
            feedback.append(f"C5a: Summary contains {hits} environmental terms (+8)")
        elif hits >= 3:
            c5_score += 5
            feedback.append(f"C5a: Summary contains {hits} environmental terms (+5)")
        else:
            c5_score += 2
            feedback.append(f"C5a: Summary has {hits} relevant terms (+2)")

        # Check for numerical results
        import re
        numbers = re.findall(r'\d+\.?\d*\s*%', summary_content)
        if len(numbers) >= 2:
            c5_score += 7
            feedback.append(f"C5b: Summary includes {len(numbers)} numerical percentage results (+7)")
        elif len(numbers) >= 1:
            c5_score += 4
            feedback.append(f"C5b: Summary includes {len(numbers)} numerical result (+4)")
        else:
            # Check for any numbers at all
            any_numbers = re.findall(r'\d+\.?\d*', summary_content)
            if len(any_numbers) >= 3:
                c5_score += 3
                feedback.append("C5b: Summary includes numerical data but no percentage format (+3)")
            else:
                feedback.append("C5b: No numerical results in summary (+0)")

        score += c5_score
    elif summary_exists:
        score += 2
        feedback.append(f"C5: Summary exists but short ({summary_length} chars) (+2)")
    else:
        feedback.append("C5: Summary file not found (+0)")

    # --- C6: Plausible emission reductions (10 pts) ---
    if parsed_rows:
        reductions_found = 0
        for row in parsed_rows:
            try:
                bv = float(row.get("baseline_total_mg", "0"))
                lv = float(row.get("lez_total_mg", "0"))
                if bv > 0 and lv > 0 and lv < bv:
                    reductions_found += 1
            except (ValueError, TypeError):
                pass
            try:
                rp = float(row.get("reduction_pct", "0").replace("%", ""))
                if rp > 0:
                    reductions_found += 1
            except (ValueError, TypeError):
                pass

        if reductions_found >= 3:
            score += 10
            feedback.append(f"C6: Report shows emission reductions for multiple pollutants (+10)")
        elif reductions_found >= 1:
            score += 5
            feedback.append(f"C6: Report shows some emission reductions (+5)")
        else:
            feedback.append("C6: No emission reductions evident in report (+0)")
    else:
        feedback.append("C6: No report data to validate reductions (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
