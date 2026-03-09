#!/usr/bin/env python3
"""
Verifier for filter_south_america_major task.

Task: Select countries in South America with POP_EST > 5,000,000
      and export to /home/ga/gvsig_exports/south_america_major.shp

Scoring criteria (100 pts total):
  GATE: Any feature with CONTINENT != 'South America' → score=0 immediately
  1. Output file exists                       (15 pts)
  2. All features are in South America        (20 pts)
  3. All features have POP_EST > 5,000,000    (25 pts)
  4. Brazil is present (mandatory country)    (20 pts)
  5. Feature count in valid range [7, 13]     (20 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_filter_south_america_major(traj, env_info, task_info):
    """
    Verify that South America major countries filter was applied and exported.

    Reads /tmp/filter_south_america_major_result.json written by export_result.sh.

    Scoring (100 points total):
    - File exists: 15 pts
    - All features in South America: 20 pts (gate: wrong continent = score 0)
    - All features have POP_EST > 5,000,000: 25 pts
    - Brazil present: 20 pts
    - Feature count in range [7, 13]: 20 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERROR: copy_from_env not available in env_info.",
            "subscores": {}
        }

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/filter_south_america_major_result.json', temp_path)
            with open(temp_path, 'r') as f:
                data = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}",
            "subscores": {}
        }

    logger.info(f"Task result: {data}")

    score = 0
    subscores = {}
    feedback_parts = []

    # Criterion 1: File exists (15 pts)
    if data.get('file_exists'):
        subscores['file_exists'] = 15
        score += 15
        feedback_parts.append("Output shapefile exists.")
    else:
        subscores['file_exists'] = 0
        feedback_parts.append("FAIL: /home/ga/gvsig_exports/south_america_major.shp not found.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # GATE: Wrong-target check — if any feature is NOT in South America → score=0
    all_sa = data.get('all_south_america', False)
    continent_values = data.get('continent_values', [])
    if not all_sa:
        non_sa = [c for c in continent_values if c != 'South America']
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"GATE FAIL: Output contains features outside South America. "
                f"Continent values found: {continent_values}. "
                "The task requires ONLY South American countries."
            ),
            "subscores": {'file_exists': 15, 'wrong_target_gate': 0}
        }

    # Criterion 2: All features are in South America (20 pts)
    subscores['all_south_america'] = 20
    score += 20
    feedback_parts.append("All features are in South America.")

    # Criterion 3: All features have POP_EST > 5,000,000 (25 pts)
    min_pop = data.get('min_pop')
    if data.get('all_pop_gt_5m'):
        subscores['pop_filter'] = 25
        score += 25
        pop_note = f" (min pop in output: {min_pop:,})" if min_pop else ""
        feedback_parts.append(f"All features have POP_EST > 5,000,000{pop_note}.")
    else:
        subscores['pop_filter'] = 0
        if min_pop is not None:
            feedback_parts.append(
                f"FAIL: Some features have POP_EST ≤ 5,000,000. Min population in output: {min_pop:,}."
            )
        else:
            feedback_parts.append(
                "FAIL: Could not verify population filter (POP_EST field may be missing)."
            )

    # Criterion 4: Brazil is present (20 pts)
    country_names = [n.lower() for n in data.get('country_names', [])]
    brazil_present = any('brazil' in n for n in country_names)
    if brazil_present:
        subscores['brazil_present'] = 20
        score += 20
        feedback_parts.append("Brazil present in output.")
    else:
        subscores['brazil_present'] = 0
        feedback_parts.append("FAIL: Brazil not found in output (expected as largest SA country).")

    # Criterion 5: Feature count in valid range [7, 10] (20 pts)
    # SA has 12 total countries; ~9 have pop > 5M. Tight range [7,10] excludes "all SA" submissions (12).
    fc = data.get('feature_count')
    if fc is not None and 7 <= fc <= 10:
        subscores['feature_count'] = 20
        score += 20
        feedback_parts.append(f"Feature count: {fc} (expected ~9 qualifying SA countries).")
    elif fc is not None and 5 <= fc <= 12:
        subscores['feature_count'] = 8
        score += 8
        feedback_parts.append(
            f"WARN: Feature count {fc} is outside the tight expected range [7, 10]. "
            "If you selected all SA countries without filtering by POP_EST>5M, "
            "there are ~12 features — the population filter is required."
        )
    else:
        subscores['feature_count'] = 0
        feedback_parts.append(
            f"FAIL: Feature count {fc} is outside the expected range. "
            "Check that you applied both conditions: CONTINENT='South America' AND POP_EST>5000000."
        )

    names_str = ', '.join(data.get('country_names', [])[:12])
    if names_str:
        feedback_parts.append(f"Countries found: {names_str}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
