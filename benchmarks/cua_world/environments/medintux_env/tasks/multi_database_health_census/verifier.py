#!/usr/bin/env python3
"""
Verifier for multi_database_health_census task.

Checks:
1. Report existence and anti-gaming (created during task)
2. Completeness (mentions all 4 DBs)
3. Accuracy of counts (tables, patients, codes)
4. Schema documentation accuracy
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for easier searching."""
    return text.lower().replace("_", "").replace("-", "")

def extract_number_near_keyword(text, keyword, window=50):
    """Try to find a number near a keyword in text."""
    idx = text.lower().find(keyword.lower())
    if idx == -1:
        return None
    
    start = max(0, idx - window)
    end = min(len(text), idx + len(keyword) + window)
    snippet = text[start:end]
    
    # Find all numbers in the snippet
    numbers = re.findall(r'\d+', snippet)
    return [int(n) for n in numbers]

def verify_multi_database_health_census(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    report_exists = result.get('report_exists', False)
    created_fresh = result.get('report_created_during_task', False)
    content = result.get('report_content', "")
    gt = result.get('ground_truth', {})
    
    score = 0
    feedback = []

    # Criterion 1: Report Existence & Anti-Gaming (10 pts)
    if report_exists and len(content.strip()) > 50:
        if created_fresh:
            score += 10
            feedback.append("Report created successfully during task.")
        else:
            score += 5
            feedback.append("Report exists but timestamp indicates pre-existence (anti-gaming penalty).")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found or empty."}

    # Criterion 2: Mentioning all Databases (10 pts)
    dbs_found = 0
    for db in ["DrTuxTest", "MedicaTuxTest", "CIM10Test", "CCAMTest"]:
        if db.lower() in content.lower():
            dbs_found += 1
    
    if dbs_found == 4:
        score += 10
        feedback.append("All 4 databases identified.")
    else:
        score += (dbs_found * 2)
        feedback.append(f"Identified {dbs_found}/4 databases.")

    # Criterion 3: Table Counts (20 pts)
    # Strategy: Look for the specific ground truth number in the text
    # This is a loose check because parsing structured text is hard without strict format
    table_counts_correct = 0
    gt_counts = gt.get('table_counts', {})
    
    # Check if we can find the exact count numbers in the report
    for db, count in gt_counts.items():
        if count is None: continue
        # Simple heuristic: is the number present?
        if str(count) in content:
            # Better: is it near the DB name?
            nums = extract_number_near_keyword(content, db)
            if nums and count in nums:
                table_counts_correct += 1
            elif str(count) in content:
                # Fallback: exact number exists somewhere
                table_counts_correct += 0.5
    
    score += min(20, int(table_counts_correct * 5))
    feedback.append(f"Table count verification score: {min(20, int(table_counts_correct * 5))}/20")

    # Criterion 4: Patient Count (15 pts)
    pat_count = gt.get('patient_count', 0)
    nums_near_patient = extract_number_near_keyword(content, "patient")
    nums_near_dossier = extract_number_near_keyword(content, "dossier")
    
    found_pat = False
    if nums_near_patient and pat_count in nums_near_patient:
        found_pat = True
    elif nums_near_dossier and pat_count in nums_near_dossier:
        found_pat = True
    elif str(pat_count) in content:
        # Fallback
        found_pat = True
        
    if found_pat:
        score += 15
        feedback.append(f"Patient count ({pat_count}) verified.")
    else:
        feedback.append(f"Patient count ({pat_count}) not clearly identified.")

    # Criterion 5: Top 5 Tables (15 pts)
    top_tables = gt.get('top_5_tables', [])
    tables_found = 0
    for table in top_tables:
        if table.lower() in content.lower():
            tables_found += 1
            
    score += (tables_found * 3)
    feedback.append(f"Top tables identified: {tables_found}/5")

    # Criterion 6: fchpat Schema (15 pts)
    fchpat_cols = gt.get('fchpat_columns', [])
    # We'll check for a subset of common columns to be safe
    key_cols = [c for c in fchpat_cols if c in ['FchPat_NomFille', 'FchPat_Nee', 'FchPat_Sexe', 'FchPat_Ville', 'FchPat_NumSS']]
    cols_found = 0
    for col in key_cols:
        if col.lower() in content.lower():
            cols_found += 1
    
    # Also check generic matches if exact column names aren't used (e.g. "Name", "City")
    # But for a schema dump, we expect technical names
    if cols_found >= 3:
        score += 15
        feedback.append("fchpat schema details found.")
    elif cols_found > 0:
        score += 5
        feedback.append("Partial fchpat schema details found.")
    else:
        feedback.append("fchpat schema details missing.")

    # Criterion 7: CIM10 / CCAM Code Counts (15 pts)
    cim10_cnt = gt.get('cim10_codes', 0)
    ccam_cnt = gt.get('ccam_codes', 0)
    
    code_score = 0
    # Allow 10% tolerance for these counts as they might query different tables
    found_cim = False
    found_ccam = False
    
    all_nums = [int(n) for n in re.findall(r'\d+', content)]
    
    for n in all_nums:
        if cim10_cnt > 0 and abs(n - cim10_cnt) / cim10_cnt < 0.1:
            found_cim = True
        if ccam_cnt > 0 and abs(n - ccam_cnt) / ccam_cnt < 0.1:
            found_ccam = True
            
    if found_cim: code_score += 8
    if found_ccam: code_score += 7
    
    score += code_score
    feedback.append(f"Code dictionary counts score: {code_score}/15")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }