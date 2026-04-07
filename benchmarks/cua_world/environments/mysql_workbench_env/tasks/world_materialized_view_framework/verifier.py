#!/usr/bin/env python3
"""
Verifier for world_materialized_view_framework task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_world_materialized_view_framework(traj, env_info, task_info):
    """
    Verify the materialized view framework task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    table_exists = result.get('table_exists', 0) == 1
    has_required_cols = result.get('has_required_cols', False)
    row_count = result.get('row_count', 0)
    proc_exists = result.get('proc_exists', 0) == 1
    index_exists = result.get('index_exists', 0) == 1
    
    usa_stats = result.get('usa_stats', {})
    jpn_stats = result.get('jpn_stats', {})
    ata_stats = result.get('ata_stats', {})
    
    # 1. Table Structure (10 pts)
    if table_exists and has_required_cols:
        score += 10
        feedback_parts.append("Table created with correct structure (10/10)")
    elif table_exists:
        score += 5
        feedback_parts.append("Table created but missing columns (5/10)")
    else:
        feedback_parts.append("Table mv_country_stats not found (0/10)")

    # 2. Data Population (10 pts)
    if row_count >= 200:
        score += 10
        feedback_parts.append(f"Table populated with {row_count} rows (10/10)")
    else:
        feedback_parts.append(f"Table has insufficient rows: {row_count} (0/10)")

    # 3. Calculation Accuracy - GNP Per Capita (15 pts)
    # USA GNP: 8510700.00, Pop: 278357000. Formula: (8510700 * 1000000) / 278357000 ≈ 30574.76
    # Note: World DB data varies slightly by version, checking range.
    # Official sample: GNP=8510700, Pop=278357000 -> 30574.76
    # Task description example calculation used older values, let's use broad range
    usa_gnp = usa_stats.get('gnp_per_capita')
    if usa_gnp is not None:
        try:
            val = float(usa_gnp)
            if 25000 <= val <= 35000:
                score += 15
                feedback_parts.append("GNP per capita calculation correct (15/15)")
            else:
                feedback_parts.append(f"GNP per capita out of range: {val} (0/15)")
        except:
            feedback_parts.append("GNP per capita invalid format (0/15)")
    else:
        feedback_parts.append("GNP per capita is NULL for USA (0/15)")

    # 4. Calculation Accuracy - Population Density (10 pts)
    # JPN Pop: 126714000, Area: 377829. Density ≈ 335.37
    jpn_density = jpn_stats.get('population_density')
    if jpn_density is not None:
        try:
            val = float(jpn_density)
            if 330 <= val <= 345:
                score += 10
                feedback_parts.append("Population density calculation correct (10/10)")
            else:
                feedback_parts.append(f"Population density out of range: {val} (0/10)")
        except:
            feedback_parts.append("Population density invalid (0/10)")
    else:
        feedback_parts.append("Population density missing (0/10)")

    # 5. Aggregation - City Count (10 pts)
    # USA has ~274 cities
    usa_cities = usa_stats.get('city_count')
    if usa_cities == 274:
        score += 10
        feedback_parts.append("City count correct (10/10)")
    elif usa_cities is not None:
        feedback_parts.append(f"City count incorrect: {usa_cities} (0/10)")
    else:
        feedback_parts.append("City count missing (0/10)")

    # 6. Aggregation - Language Count (5 pts)
    # USA has 12 languages
    usa_langs = usa_stats.get('language_count')
    if usa_langs == 12:
        score += 5
        feedback_parts.append("Language count correct (5/5)")
    else:
        feedback_parts.append(f"Language count incorrect: {usa_langs} (0/5)")

    # 7. Subquery/Window - Largest City (10 pts)
    # USA largest city is New York
    usa_largest = usa_stats.get('largest_city_name')
    if usa_largest == 'New York':
        score += 10
        feedback_parts.append("Largest city determination correct (10/10)")
    else:
        feedback_parts.append(f"Largest city incorrect: {usa_largest} (0/10)")

    # 8. NULL Handling (5 pts)
    # Antarctica (ATA) has 0 population -> GNP/Capita should be NULL
    ata_gnp = ata_stats.get('gnp_per_capita')
    if ata_gnp is None:
        score += 5
        feedback_parts.append("NULL handling correct (5/5)")
    else:
        feedback_parts.append(f"NULL handling failed: ATA GNP is {ata_gnp} (0/5)")

    # 9. Procedure Existence (10 pts)
    if proc_exists:
        score += 10
        feedback_parts.append("Refresh procedure exists (10/10)")
    else:
        feedback_parts.append("Refresh procedure missing (0/10)")

    # 10. Index Existence (5 pts)
    if index_exists:
        score += 5
        feedback_parts.append("Index exists (5/5)")
    else:
        feedback_parts.append("Index missing (0/5)")

    # 11. CSV Export (10 pts)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    csv_mtime = int(result.get('csv_mtime', 0))
    task_start = int(result.get('task_start', 0))
    
    if csv_exists and csv_rows >= 200 and csv_mtime > task_start:
        score += 10
        feedback_parts.append("Valid CSV export created (10/10)")
    else:
        feedback_parts.append("CSV export missing, old, or empty (0/10)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }