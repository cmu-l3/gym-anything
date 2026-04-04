#!/usr/bin/env python3
"""
Verifier for target_page_inlink_audit@1.

Scoring Breakdown (100 pts):
1.  CSV Creation (20 pts): 'attic_inlinks.csv' exists and was created/modified during task.
2.  Correct Export Type (30 pts): CSV contains "Anchor Text" column (distinguishes Inlinks export from main export).
3.  Correct Target Page (30 pts): The "Destination" or "To" column contains the specific "A Light in the Attic" URL.
4.  App Usage (10 pts): Screaming Frog is running.
5.  VLM Verification (10 pts): Trajectory shows "Inlinks" tab usage.

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import csv
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_target_page_inlink_audit(traj, env_info, task_info):
    """Verify the agent exported the Inlinks for the specific product page."""
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # 2. Load JSON Result
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        copy_from_env('/tmp/task_result.json', tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    # --- Criterion 1: File Existence & Modification (20 pts) ---
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified', False)
    
    if file_exists and file_modified:
        score += 20
        feedback_parts.append("Export file 'attic_inlinks.csv' created successfully (20/20)")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but timestamp check failed (stale file?) (5/20)")
    else:
        feedback_parts.append("Export file 'attic_inlinks.csv' not found (0/20)")

    # --- Criterion 2 & 3: CSV Content Analysis (60 pts) ---
    # We analyze the CSV file content if it was copied out
    csv_valid_score = 0
    target_found_score = 0
    
    if file_exists and file_modified:
        try:
            tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            tmp_csv.close()
            # The export script copies the file to /tmp/attic_inlinks_verify.csv if it exists
            copy_from_env('/tmp/attic_inlinks_verify.csv', tmp_csv.name)
            
            with open(tmp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames if reader.fieldnames else []
                
                # Check 2: Correct Columns (30 pts)
                # Look for "Anchor Text" or "Anchor" - key differentiator of Inlinks tab
                if any("anchor" in h.lower() for h in headers) and any("to" in h.lower() or "destination" in h.lower() for h in headers):
                    csv_valid_score = 30
                    feedback_parts.append("Export has correct Inlinks structure (Anchor Text column found) (30/30)")
                else:
                    feedback_parts.append("Export missing 'Anchor Text' column - likely wrong tab exported (0/30)")

                # Check 3: Correct Target Data (30 pts)
                # Verify rows point to the correct book
                rows = list(reader)
                target_fragment = "a-light-in-the-attic_1000"
                found_target = False
                
                if rows:
                    for row in rows:
                        # Check all values in row just to be safe, but focus on 'To'/'Destination'
                        row_str = str(row).lower()
                        if target_fragment in row_str:
                            found_target = True
                            break
                
                if found_target:
                    target_found_score = 30
                    feedback_parts.append("Export contains data for target page 'A Light in the Attic' (30/30)")
                elif len(rows) > 0:
                    feedback_parts.append("Export contains rows but NOT for the correct product page (0/30)")
                else:
                    feedback_parts.append("Export file is empty (0/30)")
            
            os.unlink(tmp_csv.name)

        except Exception as e:
            feedback_parts.append(f"Failed to verify CSV content: {str(e)}")

    score += csv_valid_score
    score += target_found_score

    # --- Criterion 4: App Usage (10 pts) ---
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # --- Criterion 5: VLM Trajectory Verification (10 pts) ---
    # We want to see if they actually navigated to the "Inlinks" tab
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Analyze these screenshots of Screaming Frog SEO Spider.
            I am looking for evidence that the user navigated to the 'Inlinks' tab in the bottom detail panel.
            
            Look for:
            1. A selected row in the top main table (highlighted blue).
            2. The bottom panel being visible.
            3. The 'Inlinks' tab being selected in the bottom panel (tabs include 'URL Details', 'Inlinks', 'Outlinks', 'Image Details', etc.).
            
            Return JSON: {"inlinks_tab_visible": boolean}
            """
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('inlinks_tab_visible', False):
                        vlm_score = 10
                        feedback_parts.append("VLM confirmed 'Inlinks' tab usage (10/10)")
                    else:
                        feedback_parts.append("VLM could not confirm 'Inlinks' tab usage (0/10)")
            except Exception:
                pass # Fail silently on VLM error
    
    score += vlm_score

    # Final Pass Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }