#!/usr/bin/env python3
"""
Verifier for Informed Consent Research Survey Configuration Task.

Verification relies on the JSON exported by export_result.sh, which contains
database states of the created survey.

Criteria:
1. Survey Existence & Title (Gate)
2. Consent Text Content (Keywords)
3. Debrief Text Content (Keywords)
4. Settings (URL, Anonymized, Navigation)
5. Structure (Groups, Questions, Mandatory Consent)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_informed_consent_research_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Metadata / Requirements
    metadata = task_info.get('metadata', {})
    req_consent_kws = metadata.get('required_consent_keywords', 
        ["voluntary", "withdraw", "risk", "anonymous", "smitchell@sampleuniversity.edu", "irb@sampleuniversity.edu"])
    req_debrief_kws = metadata.get('required_debrief_keywords', 
        ["thank", "social media", "smitchell@sampleuniversity.edu"])
    
    score = 0
    feedback = []
    
    # 1. Gate: Survey Exists (0 or Pass to continue)
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No survey found with 'Social Media' in the title."
        }
    
    feedback.append(f"Survey found: {result.get('title')} (SID: {result.get('sid')})")
    
    # 2. Welcome Text / Informed Consent (20 pts)
    # Check for keywords case-insensitive
    welcome_text = result.get('welcome_text', '').lower()
    found_consent_kws = [kw for kw in req_consent_kws if kw.lower() in welcome_text]
    
    # Map 'anonymous' check to also accept 'confidential' as per design
    if "anonymous" in req_consent_kws and "anonymous" not in found_consent_kws:
        if "confidential" in welcome_text:
            found_consent_kws.append("anonymous (as confidential)")

    # Scoring: 20 pts if >= 5 keywords found
    if len(found_consent_kws) >= 5:
        score += 20
        feedback.append(f"Informed consent text sufficient ({len(found_consent_kws)}/{len(req_consent_kws)} keywords).")
    elif len(found_consent_kws) >= 3:
        score += 10
        feedback.append(f"Informed consent text partial ({len(found_consent_kws)}/{len(req_consent_kws)} keywords). Missing some required legal/contact info.")
    else:
        feedback.append("Informed consent text missing key elements (voluntary, withdraw, risk, anonymity, contacts).")

    # 3. End Text / Debrief (10 pts)
    end_text = result.get('end_text', '').lower()
    found_debrief_kws = [kw for kw in req_debrief_kws if kw.lower() in end_text]
    
    if len(found_debrief_kws) >= 2:
        score += 10
        feedback.append("Debriefing text sufficient.")
    else:
        feedback.append("Debriefing text missing key elements (thank you, hypothesis explanation, contact).")

    # 4. Settings & URL (30 pts)
    # End URL (10)
    url = result.get('url', '').lower()
    if "sampleuniversity.edu/research/participation-credit" in url:
        score += 10
        feedback.append("End URL correct.")
    else:
        feedback.append(f"End URL incorrect: {url}")

    # Format (10) - Group by Group ('G')
    fmt = result.get('format', 'S')
    if fmt == 'G':
        score += 10
        feedback.append("Format is Group-by-Group.")
    else:
        feedback.append(f"Format incorrect: expected 'G' (Group-by-Group), got '{fmt}'.")

    # Anonymized (10)
    anon = result.get('anonymized', 'N')
    if anon == 'Y':
        score += 10
        feedback.append("Anonymized responses enabled.")
    else:
        feedback.append("Anonymized responses NOT enabled.")

    # 5. Presentation Details (10 pts)
    # Progress Bar (5)
    prog = result.get('showprogress', 'N')
    if prog == 'Y':
        score += 5
        feedback.append("Progress bar enabled.")
    
    # Back Button (5) - Should be 'N'
    prev = result.get('allowprev', 'Y')
    if prev == 'N':
        score += 5
        feedback.append("Back button disabled.")
    else:
        feedback.append("Back button not disabled.")

    # 6. Structure & Content (20 pts)
    # Groups >= 3 (10)
    g_count = result.get('group_count', 0)
    if g_count >= 3:
        score += 10
        feedback.append(f"Structure correct: {g_count} groups.")
    else:
        feedback.append(f"Structure incorrect: found {g_count} groups, expected at least 3.")

    # Mandatory Consent (5)
    if result.get('mandatory_consent_exists'):
        score += 5
        feedback.append("Mandatory consent question found in Group 1.")
    else:
        feedback.append("No mandatory question found in Group 1.")

    # Total Questions >= 5 (5)
    q_count = result.get('question_count', 0)
    if q_count >= 5:
        score += 5
        feedback.append(f"Question count sufficient: {q_count}.")
    else:
        feedback.append(f"Question count low: {q_count} (expected >= 5).")

    # 7. Activation (10 pts)
    active = result.get('active', 'N')
    if active == 'Y':
        score += 10
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }