#!/usr/bin/env python3
"""
Verifier for chinook_acquisition_merger task.

Scoring Criteria:
1. Deduplication (20 pts): Known duplicate emails should not be added (count remains 1).
2. Name Parsing (20 pts): Full Name split correctly into First/Last.
3. Country Mapping (20 pts): ISO codes mapped to full names (US->USA, CA->Canada, MX->Mexico).
4. Defaults (10 pts): SupportRepId set to 3 for new records.
5. Record Count (10 pts): Correct number of new records added (~15).
6. Artifacts (20 pts): CSV and SQL files exist.

Total: 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_acquisition_merger(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Deduplication (20 pts)
    # Check if 'luisg@embraer.com.br' count is 1. If > 1, dedupe failed.
    dup_count = result.get('duplicate_check_count', 0)
    if dup_count == 1:
        score += 20
        feedback.append("Deduplication successful (no duplicates added).")
    elif dup_count > 1:
        feedback.append(f"Deduplication FAILED: Found {dup_count} records for existing email.")
    else:
        feedback.append("Critical Error: Existing record deleted?")

    # 2. Name Parsing (20 pts)
    # Expected: "Gary|Moore|USA|3"
    gary_record = result.get('gary_record', "")
    if gary_record:
        parts = gary_record.split('|')
        if len(parts) >= 2:
            first, last = parts[0], parts[1]
            if first == "Gary" and last == "Moore":
                score += 20
                feedback.append("Name parsing successful (Gary Moore).")
            else:
                feedback.append(f"Name parsing incorrect: got '{first} {last}'.")
        else:
            feedback.append("Name parsing failed (record format error).")
    else:
        feedback.append("Target record 'Gary Moore' not found.")

    # 3. Country Mapping (20 pts)
    # Check USA, Canada, Mexico mapping
    country_score = 0
    gary_country = gary_record.split('|')[2] if gary_record and len(gary_record.split('|')) > 2 else ""
    jean_country = result.get('jean_country', "")
    pablo_country = result.get('pablo_country', "")

    if gary_country == "USA": country_score += 7
    if jean_country == "Canada": country_score += 7
    if pablo_country == "Mexico": country_score += 6
    
    score += country_score
    if country_score == 20:
        feedback.append("Country mapping successful (USA, Canada, Mexico).")
    else:
        feedback.append(f"Country mapping partial/failed: US->{gary_country}, CA->{jean_country}, MX->{pablo_country}.")

    # 4. Defaults (10 pts)
    # SupportRepId should be 3 for new records
    # We checked 2 records in export_result.sh, expect 2
    rep_check = result.get('rep_check_count', 0)
    if rep_check >= 2:
        score += 10
        feedback.append("Default SupportRepId assignment successful.")
    else:
        feedback.append("Default SupportRepId incorrect or records missing.")

    # 5. Record Count (10 pts)
    # We added 15 new records in setup.
    added = result.get('added_count', 0)
    if 14 <= added <= 16:
        score += 10
        feedback.append(f"Record count correct ({added} added).")
    else:
        feedback.append(f"Record count deviation: added {added} (expected 15).")

    # 6. Artifacts (20 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("CSV export found.")
    else:
        feedback.append("CSV export missing.")
        
    if result.get('sql_exists'):
        score += 10
        feedback.append("SQL script found.")
    else:
        feedback.append("SQL script missing.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }