#!/usr/bin/env python3
"""
Verifier for world_schema_evolution_computed task.

Verifies:
1. Generated columns created in country table (30 pts)
2. continent_stats table created and populated (20 pts)
3. Stored function created and working (15 pts)
4. View created with correct logic (20 pts)
5. Data exported to CSV (15 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_world_schema_evolution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/schema_evolution_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in container"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # 1. Verify Generated Columns (30 pts total)
    # gdp_per_capita (15 pts)
    if result.get('gdp_col_exists', False):
        if result.get('gdp_col_generated', False):
            score += 15
            feedback_parts.append("gdp_per_capita generated column created (15/15)")
        else:
            score += 5
            feedback_parts.append("gdp_per_capita column exists but NOT generated (5/15)")
    else:
        feedback_parts.append("gdp_per_capita column missing (0/15)")

    # population_density (15 pts)
    if result.get('pop_col_exists', False):
        if result.get('pop_col_generated', False):
            score += 15
            feedback_parts.append("population_density generated column created (15/15)")
        else:
            score += 5
            feedback_parts.append("population_density column exists but NOT generated (5/15)")
    else:
        feedback_parts.append("population_density column missing (0/15)")

    # 2. Verify continent_stats table (20 pts)
    if result.get('stats_table_exists', False):
        row_count = int(result.get('stats_row_count', 0))
        # Expecting 7 continents
        if row_count == 7:
            # Check population sum to verify data aggregation (approx 6 billion+ in World DB)
            total_pop = float(result.get('stats_total_pop', 0))
            if total_pop > 6000000000:
                score += 20
                feedback_parts.append("continent_stats table populated correctly (20/20)")
            else:
                score += 10
                feedback_parts.append("continent_stats table exists but population sum seems low (10/20)")
        else:
            score += 5
            feedback_parts.append(f"continent_stats table has wrong row count: {row_count} (expected 7) (5/20)")
    else:
        feedback_parts.append("continent_stats table missing (0/20)")

    # 3. Verify Stored Function (15 pts)
    if result.get('func_exists', False):
        test_val = result.get('func_test_result', '')
        if test_val == 'High':
            score += 15
            feedback_parts.append("fn_classify_development function verified (15/15)")
        else:
            score += 10
            feedback_parts.append(f"fn_classify_development exists but returned unexpected value '{test_val}' for input 20000 (10/15)")
    else:
        feedback_parts.append("fn_classify_development function missing (0/15)")

    # 4. Verify View (20 pts)
    if result.get('view_exists', False):
        if result.get('view_has_class_col', False):
            rows = int(result.get('view_row_count', 0))
            if rows >= 239:
                score += 20
                feedback_parts.append("v_country_development_profile view verified (20/20)")
            else:
                score += 10
                feedback_parts.append(f"view exists but has {rows} rows (expected ~239) (10/20)")
        else:
            score += 5
            feedback_parts.append("view exists but missing 'development_class' column (5/20)")
    else:
        feedback_parts.append("v_country_development_profile view missing (0/20)")

    # 5. Verify CSV Export (15 pts)
    csv_exists = result.get('csv_exists', False)
    csv_rows = int(result.get('csv_rows', 0))
    csv_mtime = int(result.get('csv_mtime', 0))
    task_start = int(result.get('task_start', 0))

    if csv_exists and csv_rows >= 230 and csv_mtime > task_start:
        score += 15
        feedback_parts.append("CSV export verified (15/15)")
    elif csv_exists:
        feedback_parts.append("CSV export exists but failed validation (timestamp or row count) (5/15)")
        score += 5
    else:
        feedback_parts.append("CSV export missing (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }