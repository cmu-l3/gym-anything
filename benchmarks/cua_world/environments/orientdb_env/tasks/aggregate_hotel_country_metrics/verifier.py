#!/usr/bin/env python3
"""Verifier for aggregate_hotel_country_metrics."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/aggregate_hotel_country_metrics_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_country_index(indexes):
    for idx in indexes or []:
        if (idx.get("type") or "").upper() != "UNIQUE":
            continue
        if idx.get("name") == "HotelCountryMetrics.Country":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "Country":
            return True
    return False


def verify_aggregate_hotel_country_metrics(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_metrics = metadata.get("expected_metrics", {})
    valid_countries = set(metadata.get("valid_countries", []))

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    # Wrong-target rejection: any country not in the Hotels table
    unexpected = result.get("unexpected_countries", [])
    if unexpected:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"HotelCountryMetrics rows for invalid countries: {unexpected}",
        }

    score = 0
    feedback = []
    metrics_rows = result.get("metrics_rows", {})

    # Criterion 1: Schema — HotelCountryMetrics exists with all 4 mandatory properties (20 pts)
    req_props = {"Country", "TotalHotels", "LuxuryCount", "ReportBatch"}
    props = set(result.get("hotel_country_metrics_properties", []))
    mandatory = result.get("hotel_country_metrics_mandatory", {})
    schema_ok = (
        result.get("hotel_country_metrics_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if schema_ok:
        score += 20
        feedback.append("HotelCountryMetrics schema is correct with all mandatory properties")
    else:
        feedback.append(f"Schema incomplete; found props={sorted(props)}, mandatory={mandatory}")

    # Criterion 2: UNIQUE index on Country (15 pts)
    if _has_unique_country_index(result.get("hotel_country_metrics_indexes", [])):
        score += 15
        feedback.append("HotelCountryMetrics.Country UNIQUE index present")
    else:
        feedback.append("HotelCountryMetrics.Country UNIQUE index missing")

    # Criterion 3: Exact row count = 11 (10 pts)
    row_count = result.get("metrics_row_count", 0)
    if row_count == 11:
        score += 10
        feedback.append("Correct row count: 11 countries")
    else:
        feedback.append(f"Row count mismatch: expected 11, got {row_count}")

    # Criterion 4: Italy — TotalHotels=3, LuxuryCount=2 (15 pts)
    italy = metrics_rows.get("Italy", {})
    if italy.get("TotalHotels") == 3 and italy.get("LuxuryCount") == 2:
        score += 15
        feedback.append("Italy: TotalHotels=3, LuxuryCount=2 correct")
    else:
        feedback.append(f"Italy incorrect: TotalHotels={italy.get('TotalHotels')}, LuxuryCount={italy.get('LuxuryCount')}")

    # Criterion 5: Germany — TotalHotels=2, LuxuryCount=1 (10 pts)
    germany = metrics_rows.get("Germany", {})
    if germany.get("TotalHotels") == 2 and germany.get("LuxuryCount") == 1:
        score += 10
        feedback.append("Germany: TotalHotels=2, LuxuryCount=1 correct")
    else:
        feedback.append(f"Germany incorrect: TotalHotels={germany.get('TotalHotels')}, LuxuryCount={germany.get('LuxuryCount')}")

    # Criterion 6: France — TotalHotels=2, LuxuryCount=1 (10 pts)
    france = metrics_rows.get("France", {})
    if france.get("TotalHotels") == 2 and france.get("LuxuryCount") == 1:
        score += 10
        feedback.append("France: TotalHotels=2, LuxuryCount=1 correct")
    else:
        feedback.append(f"France incorrect: TotalHotels={france.get('TotalHotels')}, LuxuryCount={france.get('LuxuryCount')}")

    # Criterion 7: Single-hotel countries all have TotalHotels=1, LuxuryCount=1 (15 pts)
    single_countries = [
        "United Kingdom", "United States", "Japan",
        "Australia", "Brazil", "Spain", "Greece", "Netherlands"
    ]
    single_ok = sum(
        1 for c in single_countries
        if metrics_rows.get(c, {}).get("TotalHotels") == 1
        and metrics_rows.get(c, {}).get("LuxuryCount") == 1
    )
    single_pts = int(15 * single_ok / len(single_countries))
    score += single_pts
    if single_ok == len(single_countries):
        feedback.append("All 8 single-hotel countries correct")
    else:
        wrong = [c for c in single_countries if not (
            metrics_rows.get(c, {}).get("TotalHotels") == 1
            and metrics_rows.get(c, {}).get("LuxuryCount") == 1
        )]
        feedback.append(f"Single-hotel countries incorrect for: {wrong}")

    # Criterion 8: ReportBatch = 'bi_q1_2026' on all rows (5 pts)
    batch_correct = all(
        v.get("ReportBatch") == "bi_q1_2026" for v in metrics_rows.values()
    ) if metrics_rows else False
    if batch_correct:
        score += 5
        feedback.append("ReportBatch='bi_q1_2026' correct on all rows")
    else:
        feedback.append("ReportBatch value missing or incorrect on some rows")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
