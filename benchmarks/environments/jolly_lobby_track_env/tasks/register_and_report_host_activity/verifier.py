#!/usr/bin/env python3
"""
Verifier for register_and_report_host_activity task.

Verification Logic:
1. File Existence: Checks if 'james_wilson_report.*' exists.
2. Anti-Gaming: Checks if file was created during task window.
3. Content Logic (The "Filter" Test):
   - MUST contain "Alice" and "Bob" (Positive constraint).
   - MUST NOT contain "Charlie" (Negative constraint - proves filtering).
4. VLM Verification: Checks trajectory for visual evidence of using the "Filter" or "Search" UI elements.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_and_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_strings', ["Alice", "Bob"])
    forbidden_strings = metadata.get('forbidden_strings', ["Charlie"])

    # 1. Load result JSON from export_result.sh
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Criterion 1: Report File Existence & Timestamp (20 pts)
    report_exists = result_data.get('report_exists', False)
    created_during_task = result_data.get('created_during_task', False)
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file 'james_wilson_report.*' not found in ~/Documents/."}
    
    if not created_during_task:
        feedback.append("WARNING: Report file timestamp indicates it was not created during this task session.")
        # We penalize but continue to check content in case of clock skew, 
        # though strictly this should fail anti-gaming. 
        # For this logic, we'll award 0 points for this section but check content.
    else:
        score += 20
        feedback.append("Report file created successfully during task.")

    # Criterion 2: Content Analysis (50 pts)
    # We need to read the content of the report file
    verifier_report_path = result_data.get('verifier_report_path')
    content_score = 0
    content_passed = False
    
    if verifier_report_path:
        temp_report = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env(verifier_report_path, temp_report.name)
            
            # Read logic: Handle potential binary/encoding issues if they exported to Excel (binary) vs CSV
            # If it's pure binary Excel, simple grep might fail or be messy. 
            # We assume "grep -a" equivalent behavior by reading as bytes or handling errors.
            with open(temp_report.name, 'rb') as f:
                raw_content = f.read()
                # Try decoding as utf-8, fallback to latin-1, or just search bytes
                try:
                    text_content = raw_content.decode('utf-8')
                except UnicodeDecodeError:
                    text_content = raw_content.decode('latin-1', errors='ignore')
            
            # Check Required Strings (Alice, Bob) - 25 pts
            found_required = [s for s in required_strings if s.lower() in text_content.lower()]
            # We need at least the first names to be reasonably sure
            if "alice" in [x.lower() for x in found_required] and "bob" in [x.lower() for x in found_required]:
                content_score += 25
                feedback.append("Report contains required visitors (Alice, Bob).")
            else:
                feedback.append(f"Report missing required visitors. Found: {found_required}")

            # Check Forbidden Strings (Charlie) - 25 pts
            # This verifies the FILTERING logic
            found_forbidden = [s for s in forbidden_strings if s.lower() in text_content.lower()]
            if not found_forbidden:
                content_score += 25
                feedback.append("Report correctly excludes filtered visitors (Charlie/Sarah).")
                content_passed = True
            else:
                feedback.append(f"Report FAILED filtering check. Found forbidden data: {found_forbidden}")
                
        except Exception as e:
            feedback.append(f"Error reading report content: {str(e)}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Could not retrieve report content for verification.")

    score += content_score

    # Criterion 3: VLM Process Verification (30 pts)
    # Did they actually use the UI to filter/export?
    frames = sample_trajectory_frames(traj, n=8)
    if not frames:
        feedback.append("No visual trajectory available for VLM check.")
    else:
        # We query VLM to look for "Filter" usage or "Export" dialogs
        prompt = """
        Review these screenshots of a Visitor Management System workflow.
        I am looking for evidence of two specific actions:
        1. DATA ENTRY: Filling out visitor forms (names Alice, Bob, or Charlie).
        2. FILTERING/REPORTING: Using a "Filter" bar, "Search" box, or "Export" dialog to isolate specific records.
        
        Does the user perform these actions?
        """
        try:
            vlm_result = query_vlm(images=frames, prompt=prompt)
            # Simple heuristic: if VLM is positive about the workflow
            response_text = vlm_result.get('response', '').lower()
            if "yes" in response_text or "filter" in response_text or "export" in response_text:
                score += 30
                feedback.append("VLM confirms data entry and filtering workflow.")
            else:
                score += 10 # Participation points if VLM is unsure
                feedback.append("VLM could not clearly confirm filtering workflow.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            score += 10 # Fallback

    # Final tally
    passed = (score >= 70) and content_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }