#!/usr/bin/env python3
"""
Verifier for ICD-10 Clinical Coding Research Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_icd10_clinical_coding(traj, env_info, task_info):
    """
    Verifies the ICD-10 coding task.
    
    Scoring Breakdown (100 pts):
    1. Output File (10 pts): Exists, valid JSON, fresh.
    2. Codes Correctness (42 pts): 
       - Scenarios 1-5 checked against ground truth.
       - Scenario 1 (Diabetes+CKD) requires two codes for full points.
    3. Research Evidence (24 pts):
       - History visits to relevant sites.
       - Code descriptions present in JSON.
    4. Bookmarks (24 pts):
       - Folder exists.
       - Correct number of bookmarks.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    score = 0
    feedback = []
    
    # 1. Retrieve 'task_result.json' (Metadata about system state)
    sys_stats = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            sys_stats = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metrics: {str(e)}"}
        finally:
            try: os.unlink(f.name) 
            except: pass

    # 2. Retrieve Agent's Output File
    agent_output = {}
    output_valid = False
    
    if sys_stats.get("file_exists") and sys_stats.get("file_fresh"):
        score += 10
        feedback.append("Output file exists and is fresh (+10).")
        
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            try:
                copy_from_env("/home/ga/Documents/icd10_coding_sheet.json", f.name)
                f.seek(0)
                agent_output = json.load(f)
                output_valid = True
            except json.JSONDecodeError:
                feedback.append("Output file is not valid JSON.")
            except Exception as e:
                feedback.append(f"Could not read output file: {str(e)}")
            finally:
                try: os.unlink(f.name)
                except: pass
    else:
        feedback.append("Output file missing or not created during task.")

    # 3. Verify Codes (42 pts total)
    # Ground truth from metadata
    gt = task_info.get("metadata", {}).get("ground_truth", {})
    
    if output_valid:
        # Scenario 1: Diabetes + CKD (10 pts)
        # Expecting E11.22 AND N18.3x
        s1 = agent_output.get("scenario_1", {})
        s1_codes = [c.upper().strip() for c in s1.get("codes", [])]
        
        has_diabetes = any("E11.22" in c for c in s1_codes)
        has_ckd = any("N18.3" in c for c in s1_codes) # Matches N18.3, N18.30, etc.
        
        if has_diabetes and has_ckd:
            score += 10
            feedback.append("Scenario 1: Perfect match (+10).")
        elif has_diabetes or has_ckd:
            score += 5
            feedback.append("Scenario 1: Partial match (missing etiology or manifestation) (+5).")
        else:
            feedback.append(f"Scenario 1: Incorrect. Got {s1_codes}")

        # Scenario 2: STEMI (8 pts)
        # Expect I21.02 or I21.0
        s2_codes = [c.upper().strip() for c in agent_output.get("scenario_2", {}).get("codes", [])]
        if any(c in ["I21.02", "I21.0", "I21.09"] for c in s2_codes):
            score += 8
            feedback.append("Scenario 2: Correct (+8).")
        else:
            feedback.append(f"Scenario 2: Incorrect. Got {s2_codes}")

        # Scenario 3: Depression (8 pts)
        # Expect F33.1x
        s3_codes = [c.upper().strip() for c in agent_output.get("scenario_3", {}).get("codes", [])]
        if any("F33.1" in c for c in s3_codes):
            score += 8
            feedback.append("Scenario 3: Correct (+8).")
        else:
            feedback.append(f"Scenario 3: Incorrect. Got {s3_codes}")

        # Scenario 4: Hip OA (8 pts)
        # Expect M16.11 (right) or M16.1 (unilateral)
        s4_codes = [c.upper().strip() for c in agent_output.get("scenario_4", {}).get("codes", [])]
        if any(c in ["M16.11", "M16.1"] for c in s4_codes):
            score += 8
            feedback.append("Scenario 4: Correct (+8).")
        else:
            feedback.append(f"Scenario 4: Incorrect. Got {s4_codes}")

        # Scenario 5: Pneumonia (8 pts)
        # Expect J13
        s5_codes = [c.upper().strip() for c in agent_output.get("scenario_5", {}).get("codes", [])]
        if any("J13" == c for c in s5_codes):
            score += 8
            feedback.append("Scenario 5: Correct (+8).")
        else:
            feedback.append(f"Scenario 5: Incorrect. Got {s5_codes}")
    else:
        feedback.append("Skipping code verification due to invalid output file.")

    # 4. Verify History/Research (24 pts)
    # Check history hits
    hist = sys_stats.get("history_hits", {})
    total_hits = hist.get("who", 0) + hist.get("icd10data", 0) + hist.get("cms", 0)
    
    if total_hits >= 3:
        score += 15
        feedback.append(f"Research history confirmed ({total_hits} visits) (+15).")
    elif total_hits > 0:
        score += 8
        feedback.append(f"Minimal research history found ({total_hits} visits) (+8).")
    else:
        feedback.append("No history of visiting standard ICD-10 coding sites.")
        
    # Check descriptions in JSON (simple non-empty check)
    if output_valid:
        desc_count = 0
        for k in ["scenario_1", "scenario_2", "scenario_3", "scenario_4", "scenario_5"]:
            d = agent_output.get(k, {}).get("code_descriptions", [])
            if d and len(d) > 0 and isinstance(d[0], str) and len(d[0]) > 5:
                desc_count += 1
        
        if desc_count >= 4:
            score += 9
            feedback.append("Code descriptions present (+9).")
        elif desc_count > 0:
            score += 4
            feedback.append("Some code descriptions present (+4).")

    # 5. Verify Bookmarks (24 pts)
    bms = sys_stats.get("bookmarks", {})
    if bms.get("folder_found"):
        score += 10
        feedback.append("Bookmark folder 'Medical Coding Resources' exists (+10).")
        count = bms.get("count_in_folder", 0)
        if count >= 4:
            score += 14
            feedback.append(f"Found {count} bookmarks in folder (+14).")
        elif count > 0:
            score += 7
            feedback.append(f"Found only {count} bookmarks in folder (required 4) (+7).")
        else:
            feedback.append("Folder is empty.")
    else:
        feedback.append("Bookmark folder 'Medical Coding Resources' not found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }