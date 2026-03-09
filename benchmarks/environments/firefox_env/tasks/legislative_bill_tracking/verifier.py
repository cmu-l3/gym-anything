#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_legislative_bill_tracking(traj, env_info, task_info):
    """
    Verifies the legislative_bill_tracking task.
    
    Score Breakdown (100 pts total):
    1. Browser History (10 pts): Visited congress.gov.
    2. Bookmarks (20 pts): Folder 'AI Legislation 118th' exists with 3 bookmarks.
    3. PDF Download (20 pts): 'hr5077_text.pdf' exists, >10KB, created during task.
    4. JSON Report Existence (10 pts): File exists and is valid JSON.
    5. JSON Report Content (40 pts): Accurate data for 3 bills (Sponsors, Dates).
    """
    
    # 1. Setup - Get Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve Exported System State
    system_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                system_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve system state: {e}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 3. Retrieve User's Report File
    user_report = None
    report_path = system_result.get("report_path", "/home/ga/Documents/legislative_report.json")
    
    if system_result.get("report_exists"):
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            try:
                copy_from_env(report_path, tmp.name)
                with open(tmp.name, 'r') as f:
                    user_report = json.load(f)
            except json.JSONDecodeError:
                user_report = "INVALID_JSON"
            except Exception:
                user_report = None
            finally:
                if os.path.exists(tmp.name):
                    os.unlink(tmp.name)

    # 4. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: History (10 pts)
    if system_result.get("history_congress_visits", 0) > 0:
        score += 10
        feedback.append("Browser history confirmed.")
    else:
        feedback.append("No history of visiting congress.gov.")

    # Criterion 2: Bookmarks (20 pts)
    if system_result.get("bookmark_folder_exists"):
        count = system_result.get("bookmark_count", 0)
        if count >= 3:
            score += 20
            feedback.append(f"Bookmarks verified: Folder found with {count} items.")
        else:
            score += 10
            feedback.append(f"Bookmark folder found, but contains {count}/3 items (Partial credit).")
    else:
        feedback.append("Bookmark folder 'AI Legislation 118th' not found.")

    # Criterion 3: PDF Download (20 pts)
    if system_result.get("pdf_exists"):
        if system_result.get("pdf_fresh"):
            # Check size (expecting >10KB for a typical bill text PDF)
            if system_result.get("pdf_size", 0) > 10240:
                score += 20
                feedback.append("PDF download verified.")
            else:
                score += 10
                feedback.append("PDF exists but seems too small (<10KB).")
        else:
            feedback.append("PDF file exists but was not downloaded during this task.")
    else:
        feedback.append("PDF file 'hr5077_text.pdf' not found in ~/Documents/Bills/.")

    # Criterion 4 & 5: Report (50 pts total)
    if user_report == "INVALID_JSON":
        feedback.append("Report file exists but contains invalid JSON.")
    elif user_report is None:
        feedback.append("Report file not found.")
    else:
        # File exists and is valid JSON (10 pts)
        score += 10
        feedback.append("Report JSON valid.")
        
        # Check Content (40 pts)
        # Expected Data
        targets = {
            "H.R. 926": {"sponsor": "Lieu", "intro": "2023-02-09"},
            "S. 2293": {"sponsor": "Schatz", "intro": "2023-07-13"},
            "H.R. 5077": {"sponsor": "Eshoo", "intro": "2023-07-28"}
        }
        
        bills_found = user_report.get("bills", [])
        if not isinstance(bills_found, list):
            feedback.append("Report structure incorrect: 'bills' should be a list.")
        else:
            correct_entries = 0
            for target_num, target_data in targets.items():
                # Find matching entry in user report
                match = None
                for entry in bills_found:
                    # Loose matching on bill number
                    if target_num.replace(" ","").replace(".","").lower() in str(entry.get("bill_number","")).replace(" ","").replace(".","").lower():
                        match = entry
                        break
                
                if match:
                    # Check details
                    sponsor_ok = target_data["sponsor"].lower() in str(match.get("primary_sponsor", "")).lower()
                    date_ok = target_data["intro"] == str(match.get("introduced_date", ""))
                    
                    if sponsor_ok and date_ok:
                        correct_entries += 1
                    else:
                        feedback.append(f"Data mismatch for {target_num}: Expected {target_data}, got Sponsor='{match.get('primary_sponsor')}' Date='{match.get('introduced_date')}'")
                else:
                    feedback.append(f"Missing entry for {target_num}")

            # 40 pts distributed across 3 bills (~13.3 pts each). 
            # Let's do: 3 correct = 40, 2 correct = 25, 1 correct = 10.
            if correct_entries == 3:
                score += 40
                feedback.append("All bill data accurate.")
            elif correct_entries == 2:
                score += 25
                feedback.append("2/3 bills accurate.")
            elif correct_entries == 1:
                score += 10
                feedback.append("1/3 bills accurate.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }