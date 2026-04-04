#!/usr/bin/env python3
"""Verifier for congestion_pricing_scenario task.

Scoring breakdown (100 points, pass >= 60):
  C1: Baseline simulation ran and traffic economics CSV produced (15 pts)
  C2: Priced route file with 15-25% demand reduction, buses preserved (20 pts)
  C3: Pricing sumocfg created and simulation ran (10 pts)
  C4: Pricing scenario economics CSV with valid data (15 pts)
  C5: CBA report CSV with monetized values for required categories (25 pts)
  C6: Executive policy brief with economic analysis and recommendations (15 pts)
"""

import json
import csv
import tempfile
import os
import io
import re
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/congestion_pricing_scenario_result.json"

REQUIRED_CBA_CATEGORIES = [
    "travel_time_savings", "fuel_savings", "emission_reduction_co2",
    "congestion_charge_revenue", "total_net_benefit"
]


def verify_congestion_pricing_scenario(traj, env_info, task_info):
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
    baseline_exists = result.get("baseline_econ_exists", False)
    priced_route_exists = result.get("priced_route_exists", False)
    priced_cfg_exists = result.get("priced_cfg_exists", False)
    cba_exists = result.get("cba_exists", False)
    brief_exists = result.get("brief_exists", False)

    if not baseline_exists and not priced_route_exists and not cba_exists and not brief_exists:
        return {"passed": False, "score": 0,
                "feedback": "DO-NOTHING: No outputs found."}

    # --- C1: Baseline traffic economics CSV (15 pts) ---
    baseline_content = result.get("baseline_econ_content", "")
    if baseline_exists and baseline_content:
        c1_score = 0
        try:
            reader = csv.DictReader(io.StringIO(baseline_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["metric", "value", "unit"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 3:
                c1_score += 5
                feedback.append("C1a: Baseline CSV has all 3 required columns (+5)")
            elif cols_found >= 2:
                c1_score += 3
                feedback.append(f"C1a: {cols_found}/3 columns present (+3)")
            else:
                feedback.append(f"C1a: Missing columns ({fieldnames}) (+0)")

            rows = list(reader)
            valid_metrics = 0
            for row in rows:
                try:
                    v = float(row.get("value", ""))
                    if v >= 0:
                        valid_metrics += 1
                except (ValueError, TypeError):
                    pass

            if valid_metrics >= 5:
                c1_score += 10
                feedback.append(f"C1b: {valid_metrics} metrics with valid values (+10)")
            elif valid_metrics >= 3:
                c1_score += 6
                feedback.append(f"C1b: {valid_metrics} metrics found (+6)")
            elif valid_metrics >= 1:
                c1_score += 3
                feedback.append(f"C1b: {valid_metrics} metric(s) found (+3)")
            else:
                feedback.append("C1b: No valid metrics (+0)")

        except Exception as e:
            feedback.append(f"C1: Error parsing CSV: {e} (+0)")

        score += c1_score
    else:
        feedback.append("C1: Baseline traffic economics CSV not found (+0)")

    # --- C2: Priced route file with demand reduction (20 pts) ---
    if priced_route_exists:
        c2_score = 0
        priced_veh = result.get("priced_vehicle_count", 0)
        orig_private = result.get("initial_data", {}).get("private_vehicle_count", 0)
        reduction_pct = result.get("demand_reduction_pct", 0)
        bus_preserved = result.get("priced_bus_preserved", False)

        if priced_veh > 0:
            c2_score += 5
            feedback.append(f"C2a: Priced route file has {priced_veh} vehicles (+5)")
        else:
            feedback.append("C2a: Priced route file empty or no vehicles (+0)")

        if 10 <= reduction_pct <= 35:
            c2_score += 10
            feedback.append(f"C2b: Demand reduction of {reduction_pct}% (target 15-25%) (+10)")
        elif 5 <= reduction_pct <= 50:
            c2_score += 5
            feedback.append(f"C2b: Demand reduction of {reduction_pct}% (outside 15-25% but reasonable) (+5)")
        elif reduction_pct > 0:
            c2_score += 3
            feedback.append(f"C2b: Demand reduction of {reduction_pct}% (too high or too low) (+3)")
        else:
            feedback.append(f"C2b: No demand reduction detected (orig: {orig_private}, priced: {priced_veh}) (+0)")

        if bus_preserved:
            c2_score += 5
            feedback.append("C2c: Bus vehicles correctly preserved (not removed) (+5)")
        else:
            feedback.append("C2c: Cannot confirm bus preservation (+0)")

        score += c2_score
    else:
        feedback.append("C2: Priced route file not found (+0)")

    # --- C3: Pricing sumocfg and simulation (10 pts) ---
    if priced_cfg_exists:
        c3_score = 0
        cfg_content = result.get("priced_cfg_content", "")

        if "priced" in cfg_content.lower() or "pasubio_priced" in cfg_content:
            c3_score += 5
            feedback.append("C3a: Pricing sumocfg references priced route file (+5)")
        elif cfg_content:
            c3_score += 3
            feedback.append("C3a: Pricing sumocfg exists but may not reference priced routes (+3)")
        else:
            feedback.append("C3a: Pricing sumocfg is empty (+0)")

        priced_econ_exists = result.get("priced_econ_exists", False)
        if priced_econ_exists:
            c3_score += 5
            feedback.append("C3b: Pricing scenario metrics exist (simulation ran) (+5)")
        else:
            feedback.append("C3b: No pricing scenario metrics found (+0)")

        score += c3_score
    else:
        feedback.append("C3: Pricing sumocfg not found (+0)")

    # --- C4: Pricing scenario economics CSV (15 pts) ---
    if result.get("priced_econ_exists", False):
        priced_content = result.get("priced_econ_content", "")
        c4_score = 0
        try:
            reader = csv.DictReader(io.StringIO(priced_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            cols_found = sum(1 for c in ["metric", "value", "unit"] if c in fieldnames)
            if cols_found >= 3:
                c4_score += 5
                feedback.append("C4a: Priced CSV has all columns (+5)")
            elif cols_found >= 2:
                c4_score += 3
                feedback.append(f"C4a: {cols_found}/3 columns (+3)")

            rows = list(reader)
            valid = sum(1 for r in rows if float(r.get("value", "0")) >= 0)
            if valid >= 5:
                c4_score += 10
                feedback.append(f"C4b: {valid} metrics with valid values (+10)")
            elif valid >= 3:
                c4_score += 6
                feedback.append(f"C4b: {valid} metrics found (+6)")
            elif valid >= 1:
                c4_score += 3
                feedback.append(f"C4b: {valid} metric(s) (+3)")
            else:
                feedback.append("C4b: No valid metrics (+0)")
        except Exception as e:
            feedback.append(f"C4: Error parsing CSV: {e} (+0)")

        score += c4_score
    else:
        feedback.append("C4: Pricing scenario economics CSV not found (+0)")

    # --- C5: CBA report CSV (25 pts) ---
    if cba_exists:
        cba_content = result.get("cba_content", "")
        c5_score = 0
        try:
            reader = csv.DictReader(io.StringIO(cba_content))
            fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]

            expected_cols = ["category", "baseline_value", "priced_value",
                           "change_pct", "annual_monetized_eur"]
            cols_found = sum(1 for c in expected_cols if c in fieldnames)
            if cols_found >= 5:
                c5_score += 7
                feedback.append("C5a: All 5 required CBA columns present (+7)")
            elif cols_found >= 3:
                c5_score += 4
                feedback.append(f"C5a: {cols_found}/5 columns present (+4)")
            elif cols_found >= 2:
                c5_score += 2
                feedback.append(f"C5a: {cols_found}/5 columns present (+2)")
            else:
                feedback.append(f"C5a: Missing columns ({fieldnames}) (+0)")

            rows = list(reader)
            categories_found = set()
            for row in rows:
                cat = row.get("category", "").strip().lower()
                for req in REQUIRED_CBA_CATEGORIES:
                    if req in cat or cat in req:
                        categories_found.add(req)

            if len(categories_found) >= 5:
                c5_score += 8
                feedback.append("C5b: All 5 required CBA categories present (+8)")
            elif len(categories_found) >= 3:
                c5_score += 5
                feedback.append(f"C5b: {len(categories_found)}/5 categories present (+5)")
            elif len(categories_found) >= 1:
                c5_score += 3
                feedback.append(f"C5b: {len(categories_found)}/5 categories present (+3)")
            else:
                feedback.append("C5b: No required categories found (+0)")

            # Check for valid monetized values
            monetized_valid = 0
            for row in rows:
                try:
                    mv = float(row.get("annual_monetized_eur", ""))
                    if mv != 0:
                        monetized_valid += 1
                except (ValueError, TypeError):
                    pass

            if monetized_valid >= 4:
                c5_score += 10
                feedback.append(f"C5c: {monetized_valid} categories with monetized EUR values (+10)")
            elif monetized_valid >= 2:
                c5_score += 6
                feedback.append(f"C5c: {monetized_valid} categories with monetized values (+6)")
            elif monetized_valid >= 1:
                c5_score += 3
                feedback.append(f"C5c: {monetized_valid} category with monetized value (+3)")
            else:
                feedback.append("C5c: No monetized EUR values found (+0)")

        except Exception as e:
            feedback.append(f"C5: Error parsing CBA CSV: {e} (+0)")

        score += c5_score
    else:
        feedback.append("C5: CBA report CSV not found (+0)")

    # --- C6: Executive policy brief (15 pts) ---
    brief_content = result.get("brief_content", "")
    brief_length = result.get("brief_length", 0)

    if brief_exists and brief_length > 100:
        c6_score = 0
        brief_lower = brief_content.lower()

        policy_keywords = ["congestion", "pricing", "charge", "demand", "reduction",
                         "benefit", "cost", "revenue", "emission", "co2",
                         "travel time", "value of time", "fuel", "policy",
                         "implementation", "exemption", "zone", "cordon",
                         "monetize", "economic", "welfare"]
        hits = sum(1 for k in policy_keywords if k in brief_lower)
        if hits >= 8:
            c6_score += 8
            feedback.append(f"C6a: Brief contains {hits} policy/economic terms (+8)")
        elif hits >= 4:
            c6_score += 5
            feedback.append(f"C6a: Brief contains {hits} terms (+5)")
        else:
            c6_score += 2
            feedback.append(f"C6a: Brief has {hits} terms (+2)")

        # Check for EUR values and percentages
        eur_refs = re.findall(r'(?:EUR|eur|€)\s*[\d,.]+|[\d,.]+\s*(?:EUR|eur|€)', brief_content)
        pct_refs = re.findall(r'\d+\.?\d*\s*%', brief_content)
        if len(eur_refs) >= 2 or len(pct_refs) >= 3:
            c6_score += 7
            feedback.append(f"C6b: Brief includes {len(eur_refs)} EUR values and {len(pct_refs)} percentages (+7)")
        elif len(eur_refs) >= 1 or len(pct_refs) >= 2:
            c6_score += 4
            feedback.append(f"C6b: Brief has some quantitative values (+4)")
        else:
            any_numbers = re.findall(r'\d+\.?\d*', brief_content)
            if len(any_numbers) >= 5:
                c6_score += 3
                feedback.append("C6b: Brief has numerical data but limited EUR/% format (+3)")
            else:
                feedback.append("C6b: Insufficient quantitative data in brief (+0)")

        score += c6_score
    elif brief_exists:
        score += 2
        feedback.append(f"C6: Brief exists but short ({brief_length} chars) (+2)")
    else:
        feedback.append("C6: Policy brief not found (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
