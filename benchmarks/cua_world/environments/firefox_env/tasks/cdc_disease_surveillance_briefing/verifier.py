#!/usr/bin/env python3
"""
Verifier for CDC Disease Surveillance Briefing Task.

Scoring Breakdown (100 points total):
1. Firefox History (15 pts):
   - Visited CDC.gov (10 pts)
   - Visited WHO.int (5 pts)
2. Bookmarks (10 pts):
   - Folder "Disease Surveillance" exists (5 pts)
   - Contains >= 5 bookmarks (5 pts)
3. Report File (75 pts):
   - File exists and is fresh (10 pts)
   - Valid JSON structure (10 pts)
   - Influenza section valid (15 pts)
   - MMWR section valid (15 pts)
   - WHO Outbreak section valid (15 pts)
   - Notifiable diseases list valid (10 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

# Known CDC notifiable diseases (partial list for validation)
NOTIFIABLE_DISEASES = {
    "anthrax", "babesiosis", "botulism", "brucellosis", "campylobacteriosis", 
    "chancroid", "chlamydia", "cholera", "coccidioidomycosis", "cryptosporidiosis", 
    "cyclosporiasis", "dengue", "diphtheria", "ehrlichiosis", "giardiasis", 
    "gonorrhea", "haemophilus", "hansen", "hantavirus", "hepatitis", "hiv", 
    "influenza", "legionellosis", "leptospirosis", "listeriosis", "lyme", 
    "malaria", "measles", "meningococcal", "mpox", "mumps", "pertussis", 
    "plague", "poliomyelitis", "psittacosis", "q fever", "rabies", "rubella", 
    "salmonellosis", "sars", "shigellosis", "smallpox", "spotted fever", 
    "syphilis", "tetanus", "toxic shock", "trichinellosis", "tuberculosis", 
    "tularemia", "typhoid", "varicella", "vibriosis", "yellow fever", "zika"
}

def verify_cdc_briefing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify History (15 pts)
    cdc_visits = result.get('cdc_history_count', 0)
    who_visits = result.get('who_history_count', 0)
    
    if cdc_visits >= 3:
        score += 10
        feedback.append("CDC history valid (10/10)")
    elif cdc_visits > 0:
        score += 5
        feedback.append("CDC history partial (5/10)")
    else:
        feedback.append("No CDC visits found (0/10)")

    if who_visits >= 1:
        score += 5
        feedback.append("WHO history valid (5/5)")
    else:
        feedback.append("No WHO visits found (0/5)")

    # 3. Verify Bookmarks (10 pts)
    folder_exists = result.get('bookmark_folder_exists', False)
    bm_count = result.get('bookmark_count', 0)
    
    if folder_exists:
        score += 5
        feedback.append("Bookmark folder found (5/5)")
        if bm_count >= 5:
            score += 5
            feedback.append(f"Bookmark count {bm_count} >= 5 (5/5)")
        else:
            feedback.append(f"Bookmark count {bm_count} < 5 (0/5)")
    else:
        feedback.append("Bookmark folder 'Disease Surveillance' not found (0/10)")

    # 4. Verify Report File (75 pts)
    file_exists = result.get('file_exists', False)
    file_fresh = result.get('file_fresh', False)
    content = result.get('file_content', {})

    if not file_exists:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback + ["Report file missing"])}
    
    if not file_fresh:
        feedback.append("Report file not created during task (0/10)")
    else:
        score += 10
        feedback.append("Report file created during task (10/10)")

    if content.get('error') == 'invalid_json':
        feedback.append("Report file is not valid JSON (0/65)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    
    # Valid JSON structure
    score += 10
    
    # Check 1: Influenza Section (15 pts)
    flu = content.get('influenza', {})
    if isinstance(flu, dict) and "cdc.gov" in flu.get('source_url', '').lower():
        if len(flu.get('ili_activity_summary', '')) > 5:
            score += 15
            feedback.append("Influenza section valid (15/15)")
        else:
            score += 5
            feedback.append("Influenza section incomplete (5/15)")
    else:
        feedback.append("Influenza section missing/invalid source (0/15)")

    # Check 2: MMWR Section (15 pts)
    mmwr = content.get('mmwr_latest', {})
    if isinstance(mmwr, dict) and "cdc.gov" in mmwr.get('source_url', '').lower():
        pub_date = mmwr.get('publication_date', '')
        if "2024" in pub_date or "2025" in pub_date:
            score += 15
            feedback.append("MMWR section valid (15/15)")
        else:
            score += 5
            feedback.append("MMWR date invalid/old (5/15)")
    else:
        feedback.append("MMWR section missing/invalid source (0/15)")

    # Check 3: WHO Outbreak News (15 pts)
    who = content.get('who_outbreak_news', {})
    if isinstance(who, dict) and "who.int" in who.get('source_url', '').lower():
        news_date = who.get('date', '')
        if "2024" in news_date or "2025" in news_date:
            score += 15
            feedback.append("WHO section valid (15/15)")
        else:
            score += 5
            feedback.append("WHO date invalid/old (5/15)")
    else:
        feedback.append("WHO section missing/invalid source (0/15)")

    # Check 4: Notifiable Diseases (10 pts)
    diseases = content.get('notifiable_diseases', [])
    if isinstance(diseases, list) and len(diseases) >= 3:
        # Check against list
        valid_count = 0
        for d in diseases:
            if any(nd in str(d).lower() for nd in NOTIFIABLE_DISEASES):
                valid_count += 1
        
        if valid_count >= 2:
            score += 10
            feedback.append("Notifiable diseases valid (10/10)")
        else:
            score += 5
            feedback.append("Diseases list present but unrecognized names (5/10)")
    else:
        feedback.append("Notifiable diseases list missing or too short (0/10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }