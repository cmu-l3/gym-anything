#!/usr/bin/env python3
"""
Verifier for world_bank_dev_research task.

Verifies:
1. Browser History: Visits to World Bank data portal.
2. Bookmarks: "World Bank Research" folder creation and usage.
3. Report: JSON file existence, freshness, structure, and data plausibility.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_world_bank_dev_research(traj, env_info, task_info):
    """
    Verify the World Bank research task.
    """
    # 1. Setup and copy result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    result_path = "/tmp/world_bank_result.json"
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    local_tmp.close()

    try:
        copy_from_env(result_path, local_tmp.name)
        with open(local_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(local_tmp.name):
            os.unlink(local_tmp.name)

    # 2. Extract Data
    wb_visits = result.get('wb_visits', 0)
    country_visits = result.get('country_visits', 0)
    folder_exists = result.get('folder_exists', 0)
    folder_bookmark_count = result.get('folder_bookmark_count', 0)
    report_exists = result.get('report_exists', 0)
    report_fresh = result.get('report_fresh', 0)
    report_content = result.get('report_content', {})

    metadata = task_info.get('metadata', {})
    plausibility = metadata.get('plausibility_ranges', {})

    score = 0
    feedback = []

    # 3. Scoring Criteria

    # Criterion A: Browser Navigation (25 pts)
    # - Visited World Bank (15)
    # - Visited specific country pages (10)
    if wb_visits >= 3:
        score += 15
        feedback.append("Visits to World Bank confirmed (+15).")
    elif wb_visits > 0:
        score += 5
        feedback.append("Minimal visits to World Bank (+5).")
    else:
        feedback.append("No visits to World Bank detected.")

    if country_visits >= 3:
        score += 10
        feedback.append("Visits to specific country pages confirmed (+10).")
    else:
        feedback.append(f"Insufficient country-specific navigation (Count: {country_visits}).")

    # Criterion B: Bookmarks (20 pts)
    # - Folder exists (10)
    # - At least 4 bookmarks (10)
    if folder_exists:
        score += 10
        feedback.append("'World Bank Research' bookmark folder found (+10).")
        
        if folder_bookmark_count >= 4:
            score += 10
            feedback.append(f"Bookmark folder contains {folder_bookmark_count} items (+10).")
        elif folder_bookmark_count >= 1:
            score += 5
            feedback.append(f"Bookmark folder contains only {folder_bookmark_count} items (+5).")
        else:
            feedback.append("Bookmark folder is empty.")
    else:
        feedback.append("Bookmark folder 'World Bank Research' not found.")

    # Criterion C: Report Existence & Structure (20 pts)
    if report_exists and report_fresh:
        score += 10
        feedback.append("Report file exists and was created during task (+10).")
        
        # Check structure
        countries = report_content.get('countries', {})
        if isinstance(countries, dict) and all(k in countries for k in ['nigeria', 'kenya', 'south_africa']):
            score += 10
            feedback.append("Report has correct JSON structure (+10).")
        else:
            feedback.append("Report missing required country keys.")
    else:
        feedback.append("Report file missing or not created during this task.")

    # Criterion D: Data Plausibility (35 pts)
    # Check data for each country against ranges
    if report_exists and isinstance(report_content.get('countries'), dict):
        data_score = 0
        total_checks = 0
        passed_checks = 0
        
        countries_data = report_content['countries']
        
        for country_key, ranges in plausibility.items():
            if country_key not in countries_data:
                continue
                
            c_data = countries_data[country_key]
            
            # Check 5 indicators per country
            indicators = ['gdp_billions_usd', 'gdp_per_capita_usd', 'life_expectancy_years', 'population_millions', 'electricity_access_pct']
            
            for ind in indicators:
                total_checks += 1
                val = c_data.get(ind)
                
                # Handle possible string inputs from JSON
                try:
                    if val is not None:
                        val = float(val)
                        min_v, max_v = ranges.get(ind, [0, 0])
                        if min_v <= val <= max_v:
                            passed_checks += 1
                except (ValueError, TypeError):
                    pass

        # Calculate score proportional to passed checks (35 pts max)
        # 3 countries * 5 indicators = 15 checks
        if total_checks > 0:
            fraction = passed_checks / total_checks
            points = int(fraction * 35)
            data_score += points
            score += points
            feedback.append(f"Data plausibility check: {passed_checks}/{total_checks} values within range (+{points}).")
        else:
            feedback.append("No data found to verify.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }