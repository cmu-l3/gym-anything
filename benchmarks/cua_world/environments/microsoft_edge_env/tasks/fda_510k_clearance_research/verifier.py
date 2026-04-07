#!/usr/bin/env python3
"""
Verifier for FDA 510(k) Clearance Research Task.
"""

import json
import re
import os
import tempfile
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fda_research(traj, env_info, task_info):
    """
    Verifies the FDA research task execution.
    
    Scoring Criteria (100 pts total):
    1. Directory Setup (10 pts): Output directory exists.
    2. FDA Database Access (10 pts): History shows visit to accessdata.fda.gov.
    3. PDF Downloads (30 pts): 3 distinct PDF files created during task.
    4. Log File Structure (20 pts): Log file exists and has 3 lines with ' | ' separators.
    5. Data Accuracy (30 pts): 
       - PDF filenames match K-numbers in log.
       - K-numbers follow format (K\d{6}).
       - Dates are within 2024.
    """
    
    # 1. Setup - Get data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Result Data
    score = 0
    feedback = []
    
    output_dir_exists = result.get('output_dir_exists', False)
    fda_visits = result.get('fda_visits_new', 0)
    pdf_files = result.get('pdf_files', [])
    log_exists = result.get('log_file_exists', False)
    log_content = result.get('log_content', "")

    # Criterion 1: Directory Setup (10 pts)
    if output_dir_exists:
        score += 10
        feedback.append("Output directory created.")
    else:
        feedback.append("Failed: Output directory /home/ga/Documents/FDA_Research not found.")

    # Criterion 2: FDA Access (10 pts)
    if fda_visits > 0:
        score += 10
        feedback.append("FDA database accessed.")
    else:
        feedback.append("Warning: No history of visiting accessdata.fda.gov detected (agent may have used Incognito or cleared history).")

    # Criterion 3: PDF Downloads (30 pts)
    # Filter for valid PDFs created during task
    valid_pdfs = [
        f for f in pdf_files 
        if f.get('valid_header', False) and f.get('created_during_task', False) and f.get('size', 0) > 1000
    ]
    
    pdf_count = len(valid_pdfs)
    if pdf_count >= 3:
        score += 30
        feedback.append(f"Successfully downloaded {pdf_count} valid PDF files.")
    elif pdf_count > 0:
        score += (pdf_count * 10)
        feedback.append(f"Partial success: Downloaded {pdf_count}/3 PDF files.")
    else:
        feedback.append("Failed: No valid PDF files found created during the task.")

    # Criterion 4 & 5: Log File Analysis (50 pts total)
    if log_exists and log_content.strip():
        lines = [l for l in log_content.strip().split('\n') if l.strip()]
        
        # Check basic structure (20 pts)
        valid_structure_count = 0
        parsed_entries = []
        
        for line in lines:
            # Format: K-Number | Applicant Name | Decision Date
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 3:
                valid_structure_count += 1
                parsed_entries.append({
                    'k_num': parts[0],
                    'applicant': parts[1],
                    'date': parts[2]
                })
        
        if valid_structure_count >= 3:
            score += 20
            feedback.append("Log file format is correct (3+ entries with separators).")
        else:
            score += int((valid_structure_count / 3) * 20)
            feedback.append(f"Log file format issues: found {valid_structure_count}/3 valid entries.")

        # Check Data Accuracy (30 pts)
        accuracy_score = 0
        k_pattern = re.compile(r'^K\d{6}$', re.IGNORECASE)
        # Date regex: simple check for /2024 or /24
        date_pattern = re.compile(r'2024') 
        
        valid_entries = 0
        
        pdf_filenames = [os.path.splitext(f['filename'])[0].upper() for f in valid_pdfs]
        
        for entry in parsed_entries:
            entry_valid = True
            
            # Check K-Number format
            if not k_pattern.match(entry['k_num']):
                entry_valid = False
            
            # Check Date (must be 2024)
            if not date_pattern.search(entry['date']):
                entry_valid = False
                
            # Check consistency with PDF files
            # The PDF filename should match the K-Number
            if entry['k_num'].upper() not in pdf_filenames:
                entry_valid = False
            
            if entry_valid:
                valid_entries += 1

        # Award points for accuracy
        # Max 30 pts, 10 pts per fully valid entry
        accuracy_points = min(valid_entries * 10, 30)
        score += accuracy_points
        
        if valid_entries >= 3:
            feedback.append("All entries valid and match downloaded PDFs.")
        else:
            feedback.append(f"Data accuracy issues: {valid_entries}/3 entries valid (K-number format, 2024 date, and matching PDF).")
            
    else:
        feedback.append("Failed: Log file missing or empty.")

    # Check anti-gaming: "Do Nothing" is handled by score initialization of 0
    # Files must be created > task_start_time (checked in export script)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }