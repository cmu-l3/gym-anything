#!/usr/bin/env python3
"""Verifier for building_market_segmentation task.

Scoring (100 points total):
  Gate:        do-nothing check
  Criterion 1 (20 pts): building_clusters.csv exists, is new, has >= 500 rows,
                         has required columns (building_id, cluster_id, price_per_sqft)
  Criterion 2 (25 pts): exactly 3 distinct cluster IDs; cluster count is plausible
                         relative to GT eligible building count
  Criterion 3 (25 pts): cluster_profiles.csv has exactly 3 rows with required columns;
                         price ratio (max/min cluster mean) >= 1.5
  Criterion 4 (20 pts): scatter plot chart exists, is new, and > 10 KB
  Criterion 5 (10 pts): notebook has >= 4 executed code cells

Pass threshold: 60
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_building_segmentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    result = {}
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        tmp.close()
        copy_from_env("/tmp/building_segmentation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

    # Do-nothing gate
    if not result.get('clusters_csv_exists') and not result.get('profiles_csv_exists'):
        return {"passed": False, "score": 0, "feedback": "No output files produced (do-nothing)"}

    gt = result.get('gt', {})
    score = 0
    fb = []

    # ── Criterion 1: building_clusters.csv ───────────────────────────────
    c1 = 0
    if result.get('clusters_csv_exists'):
        c1 += 3
        if result.get('clusters_csv_is_new'):
            c1 += 4
        rows = result.get('clusters_csv_rows', 0)
        if rows >= 500:
            c1 += 5
        elif rows >= 100:
            c1 += 2
        if result.get('clusters_has_building_id'):
            c1 += 3
        if result.get('clusters_has_cluster_id'):
            c1 += 3
        if result.get('clusters_has_price_per_sqft'):
            c1 += 2
    score += c1
    fb.append(f"C1 clusters-csv: {c1}/20 (rows={result.get('clusters_csv_rows',0)})")

    # ── Criterion 2: Exactly 3 clusters ──────────────────────────────────
    c2 = 0
    cluster_ids = result.get('cluster_ids_found', [])
    n_clusters = len(cluster_ids)
    if n_clusters == 3:
        c2 += 20
    elif n_clusters == 2 or n_clusters == 4:
        c2 += 8  # close but not exact
    # Plausibility: clusters CSV rows should be close to GT eligible buildings
    eligible_gt = gt.get('eligible_building_count', 0)
    clusters_rows = result.get('clusters_csv_rows', 0)
    if eligible_gt > 0 and clusters_rows > 0:
        ratio = clusters_rows / eligible_gt
        if 0.5 <= ratio <= 1.5:
            c2 += 5
    score += c2
    fb.append(f"C2 cluster-count: {c2}/25 (found {n_clusters} clusters, need 3)")

    # ── Criterion 3: cluster_profiles.csv validity ───────────────────────
    c3 = 0
    if result.get('profiles_csv_exists'):
        c3 += 3
        if result.get('profiles_csv_is_new'):
            c3 += 3
        if result.get('profiles_csv_rows') == 3:
            c3 += 8
        elif result.get('profiles_csv_rows', 0) in [2, 4]:
            c3 += 3
        if result.get('profiles_has_cluster_id'):
            c3 += 2
        if result.get('profiles_has_mean_price'):
            c3 += 2
        if result.get('profiles_has_mean_age'):
            c3 += 2
        if result.get('profiles_has_building_count'):
            c3 += 2
        # Price distinctiveness check
        ratio = result.get('price_ratio_max_min')
        min_ratio = metadata.get('min_price_ratio', 1.5)
        if ratio is not None:
            if ratio >= min_ratio:
                c3 += 3
            elif ratio >= 1.2:
                c3 += 1
    score += c3
    fb.append(f"C3 profiles: {c3}/25 (rows={result.get('profiles_csv_rows',0)}, "
              f"price_ratio={result.get('price_ratio_max_min')})")

    # ── Criterion 4: Chart ───────────────────────────────────────────────
    c4 = 0
    if result.get('chart_exists'):
        c4 += 6
        if result.get('chart_is_new'):
            c4 += 8
        if result.get('chart_size_kb', 0) > 10:
            c4 += 6
    score += c4
    fb.append(f"C4 chart: {c4}/20 (size={result.get('chart_size_kb',0):.1f}KB)")

    # ── Criterion 5: Notebook executed ───────────────────────────────────
    c5 = 0
    exec_cells = result.get('notebook_executed_cells', 0)
    if exec_cells >= 5:
        c5 = 10
    elif exec_cells >= 3:
        c5 = 7
    elif exec_cells >= 1:
        c5 = 3
    score += c5
    fb.append(f"C5 notebook: {c5}/10 (executed_cells={exec_cells})")

    score = min(score, 100)
    passed = score >= metadata.get('pass_threshold', 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }
