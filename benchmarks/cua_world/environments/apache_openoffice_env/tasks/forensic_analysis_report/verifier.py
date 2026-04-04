#!/usr/bin/env python3
"""
Verifier for forensic_analysis_report@1

This script evaluates the JSON result exported from the ODT file analysis.
It checks for:
1. File existence and creation.
2. Structure (Headings, Tables, TOC).
3. Data Accuracy (Case Number, Hash, Path).
4. Formatting (Monospace font usage).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment connection failed (copy_from_env missing)."}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Logic
    score = 0
    feedback = []
    
    # 1. File Existence (Gatekeeper)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file was not created."}
    
    score += 10
    feedback.append("File created.")

    # 2. Anti-Gaming (File created during task)
    if result.get("created_during_task"):
        score += 10
        feedback.append("File timestamp valid.")
    else:
        feedback.append("Warning: File timestamp indicates it might be stale.")

    # 3. Structure (Headings, TOC)
    # Expecting at least Executive Summary, Evidence, Analysis, Conclusion (4 headings)
    h1_count = result.get("h1_count", 0)
    if h1_count >= 4:
        score += 15
        feedback.append(f"Structure good ({h1_count} main sections).")
    elif h1_count > 0:
        score += 5
        feedback.append(f"Structure weak ({h1_count} main sections, expected 4).")
    else:
        feedback.append("No Heading 1 sections found.")

    if result.get("has_toc"):
        score += 10
        feedback.append("Table of Contents present.")
    else:
        feedback.append("Table of Contents missing.")
        
    if result.get("has_page_numbers"):
        score += 5
        feedback.append("Page numbers present.")

    # 4. Evidence Table
    if result.get("table_count", 0) >= 1:
        score += 15
        feedback.append("Evidence table present.")
    else:
        feedback.append("No tables found (Evidence List missing).")

    # 5. Data Integrity (The most critical forensic part)
    if result.get("contains_case_number"):
        score += 5
        feedback.append("Case number correct.")
    else:
        feedback.append("Case number missing or incorrect.")

    # The SHA-256 Hash must be exact
    if result.get("contains_hash"):
        score += 15
        feedback.append("Malware hash correctly recorded.")
    else:
        feedback.append("Critical: Malware hash missing or incorrect.")

    # The File Path
    if result.get("contains_path"):
        score += 5
        feedback.append("File path correctly recorded.")
    else:
        feedback.append("File path missing or incorrect.")

    # 6. Formatting (Monospace)
    if result.get("monospace_fonts_detected"):
        score += 10
        feedback.append("Technical data formatted with monospace font.")
    else:
        feedback.append("Technical data NOT formatted with monospace font (Style requirement).")

    # Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }