#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clinical_trials_monitoring(traj, env_info, task_info):
    """
    Verifies the Clinical Trials Competitor Monitoring task.
    
    Criteria:
    1. Firefox History: Visited ClinicalTrials.gov and used correct filters (20 pts).
    2. Bookmarks: "Glioblastoma Phase 3" folder exists (20 pts).
    3. Bookmarks: Folder contains >= 4 items (15 pts).
    4. Output File: Created and is fresh (15 pts).
    5. Data Quality: JSON content is valid, contains 3 trials, valid NCT IDs (30 pts).
    """
    
    # 1. Setup & Read Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing."}

    # Helper to fetch files
    def fetch_file(remote_path):
        local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        local_tmp.close()
        try:
            copy_from_env(remote_path, local_tmp.name)
            if os.path.getsize(local_tmp.name) == 0:
                return None
            with open(local_tmp.name, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to fetch {remote_path}: {e}")
            return None
        finally:
            if os.path.exists(local_tmp.name):
                os.unlink(local_tmp.name)

    # Fetch result metrics
    metrics = fetch_file("/tmp/task_result.json")
    if not metrics:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metrics."}

    # Fetch user output
    user_data = fetch_file("/tmp/trial_intelligence.json")

    # 2. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: History & Filters (20 pts)
    # Check if they visited the site
    if metrics.get("history_visits_ct", 0) > 0:
        if metrics.get("history_has_filters", False):
            score += 20
            feedback.append("History: Validated search on ClinicalTrials.gov with filters.")
        else:
            score += 10
            feedback.append("History: Visited ClinicalTrials.gov, but filters (Glioblastoma+Recruiting) not clearly detected in URLs.")
    else:
        feedback.append("History: No evidence of visiting ClinicalTrials.gov.")

    # Criterion 2: Bookmark Folder (20 pts)
    if metrics.get("bookmark_folder_found", False):
        score += 20
        feedback.append("Bookmarks: 'Glioblastoma Phase 3' folder found.")
    else:
        feedback.append("Bookmarks: Required folder not found.")

    # Criterion 3: Bookmark Count (15 pts)
    count = metrics.get("bookmark_count_in_folder", 0)
    if count >= 4:
        score += 15
        feedback.append(f"Bookmarks: Found {count} bookmarks (minimum 4 met).")
    elif count >= 1:
        score += 5
        feedback.append(f"Bookmarks: Found {count} bookmarks (minimum 4 required).")
    else:
        feedback.append("Bookmarks: Folder is empty.")

    # Criterion 4: Output File Existence/Freshness (15 pts)
    if metrics.get("file_exists") and metrics.get("file_fresh"):
        score += 15
        feedback.append("Output: File 'trial_intelligence.json' created successfully.")
    elif metrics.get("file_exists"):
        score += 5
        feedback.append("Output: File exists but timestamp indicates it might be stale/pre-existing.")
    else:
        feedback.append("Output: 'trial_intelligence.json' not found.")

    # Criterion 5: Data Quality (30 pts)
    data_score = 0
    if user_data:
        # Check structure
        trials = user_data.get("trials", [])
        search_crit = user_data.get("search_criteria", {})
        
        # Check criteria mirroring
        if "Glioblastoma" in str(search_crit.get("condition", "")) and \
           "Phase 3" in str(search_crit.get("phase", "")):
            data_score += 5
            
        # Check trial count
        if isinstance(trials, list) and len(trials) >= 3:
            data_score += 10
            
            # Check individual trial validity
            valid_ncts = 0
            distinct_ids = set()
            for t in trials:
                nct = t.get("nct_id", "")
                # Regex for NCT + 8 digits
                if re.match(r"^NCT\d{8}$", nct):
                    distinct_ids.add(nct)
                    # Check other fields non-empty
                    if t.get("intervention") and t.get("sponsor"):
                        valid_ncts += 1
            
            if len(distinct_ids) >= 3:
                data_score += 10 # Unique IDs
            if valid_ncts >= 3:
                data_score += 5  # Detailed metadata
                
            if valid_ncts < 3:
                feedback.append(f"Data: Found {valid_ncts} valid trials (need 3 fully populated).")
        else:
            feedback.append("Data: Output JSON must contain a 'trials' list with at least 3 entries.")
    else:
        feedback.append("Data: Output file could not be parsed or is empty.")
    
    score += data_score
    if data_score == 30:
        feedback.append("Data: JSON content is valid and high quality.")
    else:
        feedback.append(f"Data: Partial credit ({data_score}/30).")

    # Final Verdict
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }