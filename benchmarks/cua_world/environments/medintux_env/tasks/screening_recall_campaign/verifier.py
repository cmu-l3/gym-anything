#!/usr/bin/env python3
"""
Verifier for MedinTux Screening Recall Campaign task.

Verifies:
1. CSV output existence and format (headers).
2. CSV content accuracy against database ground truth (eligible patients only).
3. Summary text file accuracy (counts match ground truth).
4. Data quality flags (contact_complet logic).
"""

import json
import os
import csv
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_summary_file(file_path):
    """Parse the summary text file into a dictionary."""
    summary_data = {}
    try:
        with open(file_path, 'r') as f:
            for line in f:
                if ':' in line:
                    key, value = line.split(':', 1)
                    summary_data[key.strip()] = int(value.strip())
    except Exception as e:
        logger.warning(f"Failed to parse summary file: {e}")
    return summary_data

def verify_screening_recall_campaign(traj, env_info, task_info):
    """
    Verify the screening recall campaign output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup paths
    metadata = task_info.get('metadata', {})
    required_headers = metadata.get('required_headers', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and User Files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    
    files_retrieved = {
        'json': False,
        'csv': False,
        'summary': False
    }
    
    try:
        # Get JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_data = json.load(f)
            files_retrieved['json'] = True
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}

        # Get CSV
        if result_data.get('csv_exists'):
            try:
                copy_from_env("/tmp/user_recall_list.csv", temp_csv)
                files_retrieved['csv'] = True
            except Exception:
                feedback_parts.append("CSV reported existing but failed to copy.")
        
        # Get Summary
        if result_data.get('summary_exists'):
            try:
                copy_from_env("/tmp/user_recall_summary.txt", temp_summary)
                files_retrieved['summary'] = True
            except Exception:
                feedback_parts.append("Summary reported existing but failed to copy.")

    finally:
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)

    # Ground Truth from Export
    gt = result_data.get('ground_truth', {})
    
    # === SCORING ===
    
    # 1. CSV Existence and Structure (10 pts)
    if files_retrieved['csv']:
        try:
            with open(temp_csv, 'r', encoding='utf-8') as f:
                reader = csv.reader(f)
                headers = next(reader, None)
                
                # Normalize headers for comparison
                headers = [h.strip().lower() for h in (headers or [])]
                required_norm = [h.strip().lower() for h in required_headers]
                
                missing_headers = [h for h in required_norm if h not in headers]
                
                if not missing_headers:
                    score += 10
                    feedback_parts.append("CSV created with correct headers")
                else:
                    score += 5
                    feedback_parts.append(f"CSV created but missing headers: {', '.join(missing_headers)}")
                    
                # Read rows for content verification
                rows = list(reader)
        except Exception as e:
            feedback_parts.append(f"CSV unreadable: {e}")
            rows = []
    else:
        feedback_parts.append("CSV file not found")
        rows = []

    # 2. Content Verification (30 pts)
    # Check if rows match expected eligible count and eligibility logic
    
    user_row_count = len(rows)
    expected_count = gt.get('total_eligible', 0)
    
    # Pts for matching count (approximate tolerance +/- 1)
    if abs(user_row_count - expected_count) <= 1 and expected_count > 0:
        score += 15
        feedback_parts.append(f"Patient count correct ({user_row_count})")
    elif user_row_count > 0:
        score += 5
        feedback_parts.append(f"Patient count mismatch: found {user_row_count}, expected {expected_count}")
    else:
        feedback_parts.append("No patients found in CSV")

    # Check logic of contact_complet column (15 pts)
    # Format: nom,prenom,date_naissance,adresse,code_postal,ville,telephone,contact_complet
    # Indexes: 0   1      2              3       4           5     6         7
    
    logic_errors = 0
    date_errors = 0
    
    if required_headers and len(headers) >= 8 and rows:
        try:
            # map header name to index
            idx_addr = headers.index('adresse')
            idx_cp = headers.index('code_postal')
            idx_ville = headers.index('ville')
            idx_complete = headers.index('contact_complet')
            idx_dob = headers.index('date_naissance')
            
            for row in rows:
                if len(row) <= max(idx_addr, idx_cp, idx_ville, idx_complete, idx_dob):
                    continue
                
                # Check logic
                is_complete = bool(row[idx_addr].strip() and row[idx_cp].strip() and row[idx_ville].strip())
                user_val = row[idx_complete].strip().upper()
                expected_val = "OUI" if is_complete else "NON"
                
                if user_val != expected_val:
                    logic_errors += 1
                
                # Check Date Range (Rough string check or parsing)
                dob_str = row[idx_dob].strip()
                # Try simple year extraction
                try:
                    year = int(dob_str[:4]) # Expecting YYYY-MM-DD
                    if year < 1950 or year > 1974:
                        date_errors += 1
                except:
                    pass # Date format mismatch, ignore specific year check
                    
            if logic_errors == 0:
                score += 10
                feedback_parts.append("Contact status logic correct")
            elif logic_errors < user_row_count / 2:
                score += 5
                feedback_parts.append(f"Contact status logic had {logic_errors} errors")
            else:
                feedback_parts.append("Contact status logic incorrect")
                
            if date_errors == 0:
                score += 5
                feedback_parts.append("All patients in age range")
            else:
                feedback_parts.append(f"{date_errors} patients outside target age range")
                
        except ValueError:
            feedback_parts.append("Could not verify logic due to column mapping issues")

    # 3. Summary File Verification (30 pts)
    if files_retrieved['summary']:
        user_summary = parse_summary_file(temp_summary)
        
        # Check required keys present (5 pts)
        required_keys = ["TOTAL_ELIGIBLE", "CONTACT_COMPLET", "CONTACT_INCOMPLET", "AVEC_TELEPHONE", "SANS_TELEPHONE"]
        if all(k in user_summary for k in required_keys):
            score += 10
            feedback_parts.append("Summary file format correct")
        else:
            feedback_parts.append("Summary file missing required lines")
            
        # Check values (20 pts)
        val_matches = 0
        total_checks = 0
        
        checks = [
            ('TOTAL_ELIGIBLE', gt.get('total_eligible')),
            ('CONTACT_COMPLET', gt.get('contact_complet')),
            ('CONTACT_INCOMPLET', gt.get('contact_incomplet')),
            ('AVEC_TELEPHONE', gt.get('avec_telephone')),
            ('SANS_TELEPHONE', gt.get('sans_telephone'))
        ]
        
        for key, expected in checks:
            if expected is not None:
                total_checks += 1
                if user_summary.get(key) == expected:
                    val_matches += 1
        
        if total_checks > 0:
            # Proportional score for matches
            match_score = int((val_matches / total_checks) * 20)
            score += match_score
            if val_matches == total_checks:
                feedback_parts.append("All summary counts match ground truth")
            else:
                feedback_parts.append(f"{val_matches}/{total_checks} summary counts match")
    else:
        feedback_parts.append("Summary file not found")

    # 4. CSV vs Summary Consistency (15 pts)
    # Does the CSV row count match the Summary TOTAL_ELIGIBLE?
    if files_retrieved['csv'] and files_retrieved['summary']:
        summary_total = user_summary.get('TOTAL_ELIGIBLE', -1)
        if summary_total == user_row_count and user_row_count > 0:
            score += 15
            feedback_parts.append("CSV count consistent with Summary")
        else:
            feedback_parts.append(f"Inconsistency: CSV has {user_row_count} rows, Summary says {summary_total}")

    # Cleanup
    if os.path.exists(temp_csv): os.unlink(temp_csv)
    if os.path.exists(temp_summary): os.unlink(temp_summary)

    passed = (score >= 60) and files_retrieved['csv'] and (user_row_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }