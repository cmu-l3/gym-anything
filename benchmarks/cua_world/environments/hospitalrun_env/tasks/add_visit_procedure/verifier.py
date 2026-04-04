#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_visit_procedure(traj, env_info, task_info):
    """
    Verify that the agent added the correct surgical procedure record.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy function missing)"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    db_check = result.get("database_check", {})
    found_docs = db_check.get("docs", [])
    
    # Metadata for verification
    metadata = task_info.get("metadata", {})
    expected_desc = metadata.get("procedure_description", "Laparoscopic Cholecystectomy")
    expected_date = metadata.get("procedure_date", "01/15/2025")
    expected_physician = metadata.get("procedure_physician", "Dr. James Morrison")
    note_keywords = metadata.get("procedure_notes_keywords", ["cholelithiasis", "gallbladder"])

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    if not found_docs:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No procedure record found for Mei Lin Chen matching 'Laparoscopic Cholecystectomy'."
        }

    # Analyze the best matching document
    doc = found_docs[0]
    score += 20 # Document exists and links to correct patient (filtered in export script)
    feedback.append("Procedure document created and linked to correct patient.")

    # Check Description (already roughly checked in export, checking specifics here)
    desc = doc.get("description", doc.get("procedureDescription", ""))
    if "laparoscopic cholecystectomy" in desc.lower():
        score += 20
        feedback.append("Description matches.")
    else:
        feedback.append(f"Description mismatch. Expected '{expected_desc}', got '{desc}'.")

    # Check Date
    # Date formats can vary (YYYY-MM-DD vs MM/DD/YYYY). We check strict or substring.
    doc_date = doc.get("procedureDate", doc.get("date", ""))
    # Normalize slashes/dashes
    if "2025-01-15" in doc_date or "01/15/2025" in doc_date or "15/01/2025" in doc_date:
        score += 15
        feedback.append("Date is correct.")
    else:
        feedback.append(f"Date mismatch. Expected '{expected_date}', got '{doc_date}'.")

    # Check Physician
    physician = doc.get("physician", doc.get("doctor", ""))
    if "morrison" in physician.lower():
        score += 15
        feedback.append("Physician is correct.")
    else:
        feedback.append(f"Physician mismatch. Expected '{expected_physician}', got '{physician}'.")

    # Check Notes
    notes = doc.get("notes", doc.get("procedureNotes", ""))
    found_keywords = [kw for kw in note_keywords if kw.lower() in notes.lower()]
    if len(found_keywords) >= 2:
        score += 15
        feedback.append("Notes contain sufficient clinical detail.")
    elif len(found_keywords) > 0:
        score += 10
        feedback.append("Notes contain some detail, but incomplete.")
    else:
        feedback.append("Notes missing or lack expected keywords.")

    # Check Patient Linkage (Explicit check of field if available)
    # The export script filtered by 'patient_p1_000003' in string, but let's be sure
    patient_ref = doc.get("patient", "")
    visit_ref = doc.get("visit", "")
    if "patient_p1_000003" in patient_ref or "P00003" in patient_ref:
        score += 15
        feedback.append("Record correctly linked to patient ID.")
    elif "visit_p1_000003" in visit_ref:
        score += 15
        feedback.append("Record correctly linked to visit ID.")
    else:
        feedback.append("Linkage to specific patient/visit ID unclear in document.")

    # 4. Final Determination
    # Pass threshold: Procedure exists, correct type, and reasonable data (>= 55 points)
    passed = (score >= 55)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }