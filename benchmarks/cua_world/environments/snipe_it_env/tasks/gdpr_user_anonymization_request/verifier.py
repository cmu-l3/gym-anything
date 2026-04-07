#!/usr/bin/env python3
"""Verifier for gdpr_user_anonymization_request task.

Scoring breakdown (100 points):
  C1: Asset EU-MAC-0142 checked in (20 pts)
  C2: Klaus Weber core identity properly anonymized (15 pts)
  C3: Klaus Weber extended PII safely cleared (15 pts)
  C4: Sofia Rossi core identity properly anonymized (15 pts)
  C5: Sofia Rossi extended PII safely cleared (15 pts)
  C6: Active employee Klaus Wagner remained unmodified (20 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/gdpr_result.json"


def verify_gdpr_anonymization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    kweber = result.get("kweber", {})
    srossi = result.get("srossi", {})
    kwagner = result.get("kwagner", {})

    # --- Do-nothing gate ---
    if (kweber.get("username") == "kweber" and 
        srossi.get("username") == "srossi" and 
        result.get("asset_checked_in") is False):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No changes detected."}

    # C1: Asset checked in (20 pts)
    if result.get("asset_checked_in"):
        score += 20
        feedback.append("C1: Asset EU-MAC-0142 successfully checked in (+20)")
    else:
        feedback.append("C1: Asset EU-MAC-0142 is still checked out (+0)")

    # C2: Klaus Weber core identity (15 pts)
    c2_pass = False
    if kweber.get("found"):
        fname = kweber.get("first_name", "")
        lname = kweber.get("last_name", "")
        uname = kweber.get("username", "")
        email = kweber.get("email", "")
        notes = kweber.get("notes", "")
        act = str(kweber.get("activated", ""))
        
        if (fname == "Anonymized" and lname == "User_KW" and 
            uname == "anon_kw" and email == "gdpr_kw@anonymized.local" and 
            notes == "GDPR Processed" and act in ["0", "", "False", "false"]):
            c2_pass = True
            
        if c2_pass:
            score += 15
            feedback.append("C2: Klaus Weber core identity properly anonymized (+15)")
        else:
            feedback.append(f"C2: Klaus Weber core identity incomplete or incorrect (fname='{fname}', lname='{lname}', uname='{uname}', email='{email}', notes='{notes}', activated='{act}') (+0)")
            if kweber.get("is_deleted"):
                feedback.append("  Note: User was soft-deleted but PII was not properly overwritten.")
    else:
        feedback.append("C2: Klaus Weber user not found in database (+0)")

    # C3: Klaus Weber extended PII cleared (15 pts)
    c3_pass = False
    if kweber.get("found"):
        fields = ["phone", "address", "city", "state", "zip", "country", "employee_num"]
        c3_pass = True
        for f in fields:
            val = kweber.get(f, "")
            if val and val != "NULL" and val.strip() != "":
                c3_pass = False
                feedback.append(f"  Failed C3 on {f}: '{val}' still exists")
                break
                
        if c3_pass:
            score += 15
            feedback.append("C3: Klaus Weber extended PII successfully cleared (+15)")
        else:
            feedback.append("C3: Klaus Weber extended PII not fully cleared (+0)")

    # C4: Sofia Rossi core identity (15 pts)
    c4_pass = False
    if srossi.get("found"):
        fname = srossi.get("first_name", "")
        lname = srossi.get("last_name", "")
        uname = srossi.get("username", "")
        email = srossi.get("email", "")
        notes = srossi.get("notes", "")
        act = str(srossi.get("activated", ""))
        
        if (fname == "Anonymized" and lname == "User_SR" and 
            uname == "anon_sr" and email == "gdpr_sr@anonymized.local" and 
            notes == "GDPR Processed" and act in ["0", "", "False", "false"]):
            c4_pass = True
            
        if c4_pass:
            score += 15
            feedback.append("C4: Sofia Rossi core identity properly anonymized (+15)")
        else:
            feedback.append(f"C4: Sofia Rossi core identity incomplete or incorrect (fname='{fname}', lname='{lname}', uname='{uname}') (+0)")
    else:
        feedback.append("C4: Sofia Rossi user not found in database (+0)")

    # C5: Sofia Rossi extended PII cleared (15 pts)
    c5_pass = False
    if srossi.get("found"):
        fields = ["phone", "address", "city", "state", "zip", "country", "employee_num"]
        c5_pass = True
        for f in fields:
            val = srossi.get(f, "")
            if val and val != "NULL" and val.strip() != "":
                c5_pass = False
                break
                
        if c5_pass:
            score += 15
            feedback.append("C5: Sofia Rossi extended PII successfully cleared (+15)")
        else:
            feedback.append("C5: Sofia Rossi extended PII not fully cleared (+0)")

    # C6: Klaus Wagner unmodified (20 pts)
    c6_pass = False
    if kwagner.get("found"):
        fname = kwagner.get("first_name", "")
        lname = kwagner.get("last_name", "")
        uname = kwagner.get("username", "")
        email = kwagner.get("email", "")
        
        if (fname == "Klaus" and lname == "Wagner" and 
            uname == "kwagner" and email == "klaus.wagner@example.com" and 
            not kwagner.get("is_deleted")):
            c6_pass = True
            
        if c6_pass:
            score += 20
            feedback.append("C6: Active employee Klaus Wagner remained unmodified (+20)")
        else:
            feedback.append(f"C6: Klaus Wagner was modified! (fname='{fname}', lname='{lname}', uname='{uname}') (+0)")
    else:
        feedback.append("C6: Klaus Wagner user was deleted! (+0)")

    # Threshold for passing is 70 points AND at least one user fully anonymized
    one_user_fully_anonymized = (c2_pass and c3_pass) or (c4_pass and c5_pass)
    passed = score >= 70 and one_user_fully_anonymized

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }