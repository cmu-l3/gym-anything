#!/usr/bin/env python3
"""
Verifier for state_dept_travel_advisory_research task.

Scoring Breakdown (100 pts):
1. History Check (20 pts): Visited Egypt, Japan, and India pages on travel.state.gov.
2. Bookmark Check (20 pts): 'Travel Risk Brief' folder exists with 3+ state.gov bookmarks.
3. File Check (15 pts): JSON file exists, is valid, and created during task.
4. Content Accuracy (45 pts):
   - Advisory Levels (15 pts): Captured plausible "Level X" strings.
   - Visa Requirements (15 pts): Correct boolean/status for each country.
   - Embassy Addresses (15 pts): Contains key city/street names.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_travel_advisory_research(traj, env_info, task_info):
    # 1. Setup and Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy metadata result
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    # Copy user output file
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    user_data = {}
    output_exists = meta.get("output_file_exists", False)
    
    if output_exists:
        try:
            copy_from_env(meta["output_file_path"], temp_output.name)
            with open(temp_output.name, 'r') as f:
                user_data = json.load(f)
        except Exception:
            logger.warning("Failed to read user output file despite it existing")
            user_data = {}
    
    if os.path.exists(temp_output.name):
        os.unlink(temp_output.name)

    # 2. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: History (20 pts)
    pages_visited = 0
    if meta.get("visited_egypt"): pages_visited += 1
    if meta.get("visited_japan"): pages_visited += 1
    if meta.get("visited_india"): pages_visited += 1
    
    hist_score = 0
    if pages_visited == 3:
        hist_score = 20
        feedback.append("All country pages visited.")
    elif pages_visited > 0:
        hist_score = 10
        feedback.append(f"Visited {pages_visited}/3 country pages.")
    else:
        feedback.append("No relevant country pages visited.")
    score += hist_score

    # Criterion 2: Bookmarks (20 pts)
    bm_score = 0
    if meta.get("bookmark_folder_exists"):
        count = meta.get("correct_bookmarks_in_folder", 0)
        if count >= 3:
            bm_score = 20
            feedback.append("Bookmark folder created with correct links.")
        elif count > 0:
            bm_score = 10
            feedback.append(f"Bookmark folder has {count}/3 required links.")
        else:
            bm_score = 5
            feedback.append("Bookmark folder empty or links incorrect.")
    else:
        feedback.append("Bookmark folder 'Travel Risk Brief' not found.")
    score += bm_score

    # Criterion 3: File Existence & Validity (15 pts)
    file_score = 0
    if output_exists and meta.get("output_file_fresh"):
        if user_data:
            file_score = 15
            feedback.append("Output JSON exists and is valid.")
        else:
            file_score = 5
            feedback.append("Output file exists but is empty or invalid JSON.")
    elif output_exists:
        file_score = 5
        feedback.append("Output file exists but was not created during this task session.")
    else:
        feedback.append("Output file not found.")
    score += file_score

    # Criterion 4: Content Accuracy (45 pts)
    content_score = 0
    if user_data:
        countries = ["egypt", "japan", "india"]
        
        # Advisory Levels (15 pts)
        adv_correct = 0
        for c in countries:
            val = str(user_data.get(c, {}).get("advisory_level", "")).lower()
            if "level" in val and any(n in val for n in ["1", "2", "3", "4"]):
                adv_correct += 1
        
        if adv_correct == 3: content_score += 15
        else: content_score += (adv_correct * 5)
        
        # Visa Requirements (15 pts)
        # Expectations: Egypt=True, Japan=False, India=True
        visa_correct = 0
        
        # Helper to strict boolean or string check
        def check_visa(val, expected):
            if isinstance(val, bool): return val == expected
            if isinstance(val, str):
                v = val.lower()
                if expected: return "yes" in v or "true" in v or "required" in v
                else: return "no" in v or "false" in v or "not" in v
            return False

        if check_visa(user_data.get("egypt", {}).get("visa_required"), True): visa_correct += 1
        if check_visa(user_data.get("japan", {}).get("visa_required"), False): visa_correct += 1
        if check_visa(user_data.get("india", {}).get("visa_required"), True): visa_correct += 1
        
        if visa_correct == 3: content_score += 15
        else: content_score += (visa_correct * 5)

        # Embassy Addresses (15 pts)
        addr_correct = 0
        
        e_addr = str(user_data.get("egypt", {}).get("embassy_address", "")).lower()
        if "cairo" in e_addr: addr_correct += 1
        
        j_addr = str(user_data.get("japan", {}).get("embassy_address", "")).lower()
        if "tokyo" in j_addr and ("akasaka" in j_addr or "minato" in j_addr): addr_correct += 1
        
        i_addr = str(user_data.get("india", {}).get("embassy_address", "")).lower()
        if "delhi" in i_addr and ("shantipath" in i_addr or "chanakyapuri" in i_addr): addr_correct += 1
        
        if addr_correct == 3: content_score += 15
        else: content_score += (addr_correct * 5)
        
        feedback.append(f"Content Analysis: Advisory {adv_correct}/3, Visa {visa_correct}/3, Address {addr_correct}/3")

    score += content_score

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }