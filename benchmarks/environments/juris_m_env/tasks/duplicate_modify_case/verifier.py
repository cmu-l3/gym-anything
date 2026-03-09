#!/usr/bin/env python3
"""
Verifier for duplicate_modify_case task.

Verification Logic:
1. Verify "Brown v. Board of Education" (original) exists with 1954 date, vol 347.
2. Verify "Brown v. Board of Education II" (duplicate) exists with 1955 date, vol 349.
3. Verify the new item was created AFTER task start (dateAdded check).
4. Verify the new item has the correct updated abstract.
"""

import os
import json
import logging
import tempfile
from datetime import datetime
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_duplicate_modify_case(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/duplicate_modify_case_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"DB Error: {result['error']}"}

    items = result.get("items", [])
    task_start_ts = result.get("task_start", 0)

    # Criteria tracking
    original_intact = False
    new_case_exists = False
    new_case_correct_metadata = False
    new_case_fresh = False
    abstract_updated = False
    
    feedback = []

    # Helper to parse DB date string "YYYY-MM-DD HH:MM:SS" to timestamp
    def db_date_to_ts(date_str):
        try:
            dt = datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
            return dt.timestamp()
        except:
            return 0

    # Metadata targets
    target_new_name = "Brown v. Board of Education II"
    target_new_vol = "349"
    target_new_page = "294"
    target_new_year = "1955"
    
    # Analyze items
    for item in items:
        name = item.get("caseName", "")
        vol = item.get("reporterVolume", "")
        page = item.get("firstPage", "")
        year = item.get("dateDecided", "")
        abstract = item.get("abstractNote", "") or ""
        date_added_str = item.get("dateAdded", "")
        
        # Check for Original (1954)
        if "Brown v. Board of Education" in name and "II" not in name and year == "1954":
            if vol == "347" and page == "483":
                original_intact = True
            else:
                feedback.append(f"Original 1954 case modified incorrectly (Vol: {vol}, Page: {page})")

        # Check for New Case (1955 / II)
        if "II" in name or year == "1955":
            new_case_exists = True
            
            # Check Metadata
            meta_score = 0
            if target_new_name in name: meta_score += 1
            if vol == target_new_vol: meta_score += 1
            if page == target_new_page: meta_score += 1
            if year == target_new_year: meta_score += 1
            
            if meta_score == 4:
                new_case_correct_metadata = True
            else:
                feedback.append(f"New case metadata mismatch: Name='{name}', Vol='{vol}', Page='{page}', Year='{year}'")

            # Check Freshness (created during task)
            # Allow small clock skew (e.g. 10s buffer)
            item_ts = db_date_to_ts(date_added_str)
            if item_ts >= (task_start_ts - 10):
                new_case_fresh = True
            else:
                feedback.append("New case appears to be pre-existing (created before task start)")

            # Check Abstract
            keywords = ["implementation", "desegregation", "deliberate speed"]
            if any(k in abstract.lower() for k in keywords):
                abstract_updated = True
            else:
                feedback.append("Abstract not updated with required description")

    # Scoring
    score = 0
    
    if new_case_exists:
        score += 20
        feedback.append("Duplicate case item exists (+20)")
    else:
        feedback.append("No duplicate case found for 'Brown II'")

    if new_case_correct_metadata:
        score += 40
        feedback.append("New case metadata (Name, Vol, Page, Year) correct (+40)")
    elif new_case_exists:
        # Partial credit for metadata
        score += 10
        feedback.append("New case exists but metadata is incorrect (+10)")

    if abstract_updated:
        score += 20
        feedback.append("Abstract updated correctly (+20)")
    
    if original_intact:
        score += 10
        feedback.append("Original 1954 case preserved (+10)")
    else:
        feedback.append("Original 1954 case missing or modified")

    if new_case_fresh:
        score += 10
        feedback.append("Item created during task execution (+10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }