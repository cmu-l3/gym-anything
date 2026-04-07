#!/usr/bin/env python3
"""Verifier for collaborative_filtering_recommendation_engine.

Stub verifier — primary evaluation is performed externally via
vlm_checklist_verifier.  This stub checks key structural outputs so that
programmatic scoring gives a rough signal.
"""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(
            "/tmp/collaborative_filtering_recommendation_engine_result.json",
            tmp.name,
        )
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_composite_index(indexes):
    """Check for a UNIQUE composite index covering TargetEmail + HotelName."""
    for idx in indexes or []:
        if (idx.get("type") or "").upper() != "UNIQUE":
            continue
        fields = idx.get("fields") or []
        if len(fields) == 2 and "TargetEmail" in fields and "HotelName" in fields:
            return True
    return False


def verify_collaborative_filtering_recommendation_engine(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_st_count = metadata.get("expected_similar_edge_count", 8)
    expected_rec_count = metadata.get("expected_recommendation_count", 7)
    expected_profiles = metadata.get("expected_profiles_with_recs", 6)
    expected_hotel = metadata.get("expected_most_recommended_hotel", "Hotel Artemide")
    expected_pair = metadata.get(
        "expected_highest_similarity_pair",
        "david.jones@example.com|john.smith@example.com",
    )
    report_batch = metadata.get("report_batch", "collab_q1_2026")

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    score = 0
    feedback = []

    # ---- Phase 1: SimilarTraveler (30 pts) ----

    # 1a. SimilarTraveler class exists with mandatory props (10 pts)
    req_props = {"SharedHotelCount", "SimilarityScore"}
    props = set(result.get("similar_traveler_properties", []))
    mandatory = result.get("similar_traveler_mandatory", {})
    schema_ok = (
        result.get("similar_traveler_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if schema_ok:
        score += 10
        feedback.append("SimilarTraveler schema correct")
    else:
        feedback.append(
            f"SimilarTraveler schema incomplete; props={sorted(props)}, mandatory={mandatory}"
        )

    # 1b. Edge count = expected (10 pts)
    st_count = result.get("similar_traveler_edge_count", 0)
    if st_count == expected_st_count:
        score += 10
        feedback.append(f"SimilarTraveler edge count = {expected_st_count}")
    else:
        feedback.append(
            f"SimilarTraveler edge count: expected {expected_st_count}, got {st_count}"
        )

    # 1c. Spot-check john<->david score ~0.75 (10 pts)
    st_edges = result.get("similar_traveler_edges", [])
    spot_ok = False
    for e in st_edges:
        if (
            e.get("src") == "john.smith@example.com"
            and e.get("dst") == "david.jones@example.com"
        ):
            s = e.get("SimilarityScore")
            if s is not None and abs(float(s) - 0.75) <= 0.02:
                spot_ok = True
                break
    if spot_ok:
        score += 10
        feedback.append("john->david SimilarityScore ~0.75 verified")
    else:
        feedback.append("john->david SimilarityScore spot-check failed")

    # ---- Phase 2: HotelRecommendation (30 pts) ----

    # 2a. Class + UNIQUE composite index (10 pts)
    hr_ok = result.get("hotel_recommendation_exists") and _has_unique_composite_index(
        result.get("hotel_recommendation_indexes", [])
    )
    if hr_ok:
        score += 10
        feedback.append("HotelRecommendation class with UNIQUE composite index")
    else:
        feedback.append("HotelRecommendation class or composite index missing")

    # 2b. Recommendation count (10 pts)
    rec_count = result.get("hotel_recommendation_count", 0)
    if rec_count == expected_rec_count:
        score += 10
        feedback.append(f"HotelRecommendation count = {expected_rec_count}")
    else:
        feedback.append(
            f"HotelRecommendation count: expected {expected_rec_count}, got {rec_count}"
        )

    # 2c. Spot-check thomas->Savoy score ~0.667 (10 pts)
    hr_rows = result.get("hotel_recommendation_rows", [])
    rec_spot_ok = False
    for r in hr_rows:
        if (
            r.get("TargetEmail") == "thomas.schafer@example.com"
            and r.get("HotelName") == "The Savoy"
        ):
            s = r.get("Score")
            if s is not None and abs(float(s) - 0.667) <= 0.02:
                rec_spot_ok = True
                break
    if rec_spot_ok:
        score += 10
        feedback.append("thomas->Savoy recommendation score ~0.667 verified")
    else:
        feedback.append("thomas->Savoy recommendation spot-check failed")

    # ---- Phase 3: RecommendationReport (30 pts) ----
    rr = result.get("recommendation_report", {})

    # 3a. TotalRecommendations (5 pts)
    if rr.get("TotalRecommendations") == expected_rec_count:
        score += 5
        feedback.append(f"TotalRecommendations = {expected_rec_count}")
    else:
        feedback.append(
            f"TotalRecommendations: expected {expected_rec_count}, "
            f"got {rr.get('TotalRecommendations')}"
        )

    # 3b. ProfilesWithRecommendations (5 pts)
    if rr.get("ProfilesWithRecommendations") == expected_profiles:
        score += 5
        feedback.append(f"ProfilesWithRecommendations = {expected_profiles}")
    else:
        feedback.append(
            f"ProfilesWithRecommendations: expected {expected_profiles}, "
            f"got {rr.get('ProfilesWithRecommendations')}"
        )

    # 3c. MostRecommendedHotel (5 pts)
    if rr.get("MostRecommendedHotel") == expected_hotel:
        score += 5
        feedback.append(f"MostRecommendedHotel = {expected_hotel}")
    else:
        feedback.append(
            f"MostRecommendedHotel: expected {expected_hotel!r}, "
            f"got {rr.get('MostRecommendedHotel')!r}"
        )

    # 3d. HighestSimilarityPair (5 pts)
    if rr.get("HighestSimilarityPair") == expected_pair:
        score += 5
        feedback.append(f"HighestSimilarityPair correct")
    else:
        feedback.append(
            f"HighestSimilarityPair: expected {expected_pair!r}, "
            f"got {rr.get('HighestSimilarityPair')!r}"
        )

    # 3e. ReportBatch (5 pts)
    if rr.get("ReportBatch") == report_batch:
        score += 5
        feedback.append(f"ReportBatch = {report_batch}")
    else:
        feedback.append(
            f"ReportBatch: expected {report_batch!r}, got {rr.get('ReportBatch')!r}"
        )

    # 3f. Baseline delta (5 pts)
    baseline_st = int(result.get("baseline_similar_traveler_count", 0) or 0)
    baseline_rec = int(result.get("baseline_recommendation_count", 0) or 0)
    if st_count > baseline_st and rec_count > baseline_rec:
        score += 5
        feedback.append("Baseline delta confirms new work")
    else:
        feedback.append("Baseline delta check failed")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
