#!/usr/bin/env python3
"""
Verifier for OER Textbook Curriculum Sourcing task.
Verifies:
1. Browser history indicates research on OpenStax.
2. Bookmark folder "Fall Curriculum OER" exists with required links.
3. PDF textbook downloaded (>5MB).
4. JSON report file exists, is valid, and contains correct metadata.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_isbn(isbn):
    """Normalize ISBN string by removing dashes and spaces."""
    if not isbn:
        return ""
    return re.sub(r'[-\s]', '', str(isbn))

def verify_oer_sourcing(traj, env_info, task_info):
    """
    Verify the OER sourcing task.
    """
    # 0. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    metadata = task_info.get('metadata', {})
    expected_isbns = metadata.get('expected_isbns', {})
    expected_authors = metadata.get('expected_authors', {})
    
    # 1. Retrieve export result
    export_path = "/tmp/task_result.json"
    temp_export = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    
    try:
        copy_from_env(export_path, temp_export.name)
        with open(temp_export.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load export result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_export.name):
            os.unlink(temp_export.name)

    # 2. Retrieve Agent's JSON Report
    report_path = "/home/ga/Documents/oer_report.json"
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    report_content = None
    
    try:
        if result_data.get("report_exists"):
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to retrieve agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion A: Browser History (10 pts)
    visits = result_data.get("history_visits_openstax", 0)
    if visits > 0:
        score += 10
        feedback.append("History check passed (OpenStax visited).")
    else:
        feedback.append("History check failed (OpenStax not visited).")

    # Criterion B: Bookmark Organization (30 pts total)
    # - Folder exists (15 pts)
    # - Correct number of OpenStax links (15 pts)
    if result_data.get("bookmark_folder_found", False):
        score += 15
        feedback.append("Bookmark folder 'Fall Curriculum OER' created.")
        
        bm_count = result_data.get("openstax_bookmarks_count", 0)
        if bm_count >= 3:
            score += 15
            feedback.append(f"Bookmarks verified ({bm_count} OpenStax links).")
        elif bm_count > 0:
            score += 5
            feedback.append(f"Partial bookmarks found ({bm_count}/3).")
        else:
            feedback.append("No OpenStax bookmarks found in folder.")
    else:
        feedback.append("Bookmark folder 'Fall Curriculum OER' NOT found.")

    # Criterion C: PDF Download (20 pts)
    if result_data.get("pdf_download_found", False):
        score += 20
        fname = result_data.get("pdf_filename", "unknown")
        feedback.append(f"PDF Download verified ({fname}).")
    else:
        feedback.append("PDF download missing or too small (<5MB).")

    # Criterion D: JSON Report Quality (40 pts total)
    # - Structure (10 pts)
    # - Data Accuracy (30 pts)
    if report_content:
        score += 10
        feedback.append("JSON report structure valid.")
        
        resources = report_content.get("resources", [])
        data_score = 0
        
        if not isinstance(resources, list) or len(resources) < 3:
             feedback.append("JSON report missing resources entries.")
        else:
            # Check each required book
            required_books = ["Psychology", "Calculus", "Microbiology"]
            
            for req in required_books:
                # Find matching entry
                entry = next((item for item in resources if req.lower() in item.get("title", "").lower()), None)
                
                if entry:
                    # Check ISBN
                    agent_isbn = normalize_isbn(entry.get("isbn_13_digital", ""))
                    # Simple matching: check if specific patterns exist
                    # Note: OpenStax uses 978-1-975076-45-0 for Psych 2e
                    target_isbn_norm = normalize_isbn(expected_isbns.get(entry.get("title"))) # Try exact title match first
                    
                    # Fuzzy match fallback if title mismatch
                    if not target_isbn_norm:
                        if "psychology" in req.lower(): target_isbn_norm = normalize_isbn(expected_isbns["Psychology 2e"])
                        elif "calculus" in req.lower(): target_isbn_norm = normalize_isbn(expected_isbns["Calculus Volume 1"])
                        elif "microbiology" in req.lower(): target_isbn_norm = normalize_isbn(expected_isbns["Microbiology"])

                    if agent_isbn == target_isbn_norm:
                        data_score += 5
                    else:
                        feedback.append(f"ISBN mismatch for {req}")

                    # Check Authors (partial match of last name)
                    agent_authors = entry.get("authors", [])
                    if isinstance(agent_authors, list) and len(agent_authors) > 0:
                        # Get expected author surnames
                        if "psychology" in req.lower(): target_auth = expected_authors["Psychology 2e"]
                        elif "calculus" in req.lower(): target_auth = expected_authors["Calculus Volume 1"]
                        elif "microbiology" in req.lower(): target_auth = expected_authors["Microbiology"]
                        else: target_auth = []

                        # Check if any target author surname appears in any agent author string
                        match = False
                        for t_auth in target_auth:
                            for a_auth in agent_authors:
                                if t_auth.lower() in a_auth.lower():
                                    match = True
                                    break
                        if match:
                            data_score += 5
                        else:
                            feedback.append(f"Author mismatch for {req}")
                    else:
                        feedback.append(f"Authors list missing/empty for {req}")
                else:
                    feedback.append(f"Entry for {req} missing in report.")
            
            score += data_score
            feedback.append(f"Data accuracy score: {data_score}/30")
    else:
        feedback.append("JSON report missing or invalid.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }