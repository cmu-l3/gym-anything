#!/usr/bin/env python3
"""
Verifier for anonymize_patient_export task.
Checks CSV structure, content, and CRITICALLY checks for PII leakage
against ground truth files hidden in the container.
"""

import json
import os
import sys
import tempfile
import csv
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anonymize_patient_export(traj, env_info, task_info):
    """
    Verify the agent successfully anonymized the patient data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    csv_path = "/home/ga/research_export/anonymized_patients.csv"
    audit_path = "/home/ga/research_export/anonymization_audit.txt"
    pii_dir = "/tmp/task_verification"
    expected_count_path = "/tmp/expected_patient_count.txt"
    
    # Files to retrieve
    files_to_copy = {
        "result_json": "/tmp/task_result.json",
        "csv": csv_path,
        "audit": audit_path,
        "names": f"{pii_dir}/original_names.txt",
        "prenoms": f"{pii_dir}/original_prenoms.txt",
        "ssn": f"{pii_dir}/original_ssn.txt",
        "addresses": f"{pii_dir}/original_addresses.txt",
        "phones": f"{pii_dir}/original_phones.txt",
        "guids": f"{pii_dir}/original_guids.txt",
        "count": expected_count_path
    }
    
    # Create temp directory for verification files
    temp_dir = tempfile.mkdtemp()
    local_files = {}
    
    try:
        # Copy files from container
        for key, remote_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, key)
            try:
                copy_from_env(remote_path, local_path)
                local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {remote_path}: {e}")
        
        # Load task result metadata
        if "result_json" in local_files and os.path.exists(local_files["result_json"]):
            with open(local_files["result_json"], 'r') as f:
                task_result = json.load(f)
        else:
            return {"passed": False, "score": 0, "feedback": "Task result metadata not found."}

        score = 0
        feedback_parts = []
        pii_breach = False
        pii_details = []

        # ============================================================
        # 1. Check File Existence (10 pts)
        # ============================================================
        if task_result.get("csv_exists") and task_result.get("csv_created_during_task"):
            score += 5
            feedback_parts.append("CSV file created.")
        else:
            feedback_parts.append("CSV file missing or not created during task.")

        if task_result.get("audit_exists") and task_result.get("audit_created_during_task"):
            score += 5
            feedback_parts.append("Audit report created.")
        else:
            feedback_parts.append("Audit report missing.")

        # ============================================================
        # 2. Check CSV Structure & Content (40 pts)
        # ============================================================
        csv_valid = False
        row_count = 0
        
        if "csv" in local_files and os.path.exists(local_files["csv"]):
            try:
                with open(local_files["csv"], 'r', encoding='utf-8', errors='replace') as f:
                    # Read header
                    header_line = f.readline().strip()
                    # Clean up header for comparison (remove spaces/quotes)
                    header_clean = header_line.replace('"', '').replace(" ", "")
                    expected_header = "pseudo_id,sex,age_band,department_code,title"
                    
                    if header_clean == expected_header.replace(" ", ""):
                        score += 10
                        feedback_parts.append("CSV header correct.")
                        
                        # Read rows
                        reader = csv.reader(f) # Reader continues from line 2
                        rows = list(reader)
                        row_count = len(rows)
                        
                        # Check row count
                        expected_count = 12 # Default
                        if "count" in local_files:
                            try:
                                with open(local_files["count"], 'r') as cf:
                                    expected_count = int(cf.read().strip())
                            except:
                                pass
                        
                        if row_count == expected_count:
                            score += 10
                            feedback_parts.append(f"Row count correct ({row_count}).")
                        else:
                            feedback_parts.append(f"Row count mismatch: {row_count} (expected {expected_count}).")

                        # Check format of columns
                        bad_ids = 0
                        bad_ages = 0
                        bad_depts = 0
                        
                        for row in rows:
                            if len(row) < 5: continue
                            # pseudo_id: PATIENT_\d{3}
                            if not re.match(r'^PATIENT_\d{3}$', row[0]): bad_ids += 1
                            # age_band: \d+-\d+ or UNKNOWN
                            if not re.match(r'^(\d+-\d+|UNKNOWN)$', row[2]): bad_ages += 1
                            # dept: \d{2}000 or 00000
                            if not re.match(r'^(\d{2}000|00000)$', row[3]): bad_depts += 1
                        
                        if bad_ids == 0 and row_count > 0: score += 10
                        elif bad_ids < 3 and row_count > 0: score += 5
                        
                        if bad_ages == 0 and row_count > 0: score += 5
                        if bad_depts == 0 and row_count > 0: score += 5
                        
                        if bad_ids == 0 and bad_ages == 0 and bad_depts == 0:
                            feedback_parts.append("Data formats correct.")
                        else:
                            feedback_parts.append(f"Format errors: IDs({bad_ids}), Ages({bad_ages}), Depts({bad_depts}).")
                            
                        csv_valid = True
                    else:
                        feedback_parts.append(f"Invalid header: {header_line}")
            except Exception as e:
                feedback_parts.append(f"Error parsing CSV: {e}")

        # ============================================================
        # 3. PII Leakage Check (25 pts) - CRITICAL
        # ============================================================
        # Helper to check file content against a list of PII strings
        def check_pii(target_files, pii_file, pii_type, min_len=3):
            leaks = []
            if pii_file not in local_files or not os.path.exists(local_files[pii_file]):
                return []
                
            with open(local_files[pii_file], 'r', encoding='utf-8', errors='ignore') as f:
                pii_values = [line.strip() for line in f if len(line.strip()) >= min_len]
            
            # Read output contents once
            contents = ""
            for t_key in target_files:
                if t_key in local_files and os.path.exists(local_files[t_key]):
                    with open(local_files[t_key], 'r', encoding='utf-8', errors='ignore') as f:
                        contents += f.read() + "\n"
            
            contents_lower = contents.lower()
            
            for val in pii_values:
                # Basic check: is the value in the output?
                # Case insensitive for text, sensitive for IDs usually, but let's be strict
                if val.lower() in contents_lower:
                    leaks.append(val)
            return leaks

        target_outputs = ["csv", "audit"]
        
        # Check names (Names are sensitive)
        name_leaks = check_pii(target_outputs, "names", "Name", min_len=4)
        if name_leaks:
            pii_breach = True
            pii_details.append(f"Names leaked: {len(name_leaks)} (e.g. {name_leaks[0]})")
            
        # Check SSNs (Critical)
        ssn_leaks = check_pii(target_outputs, "ssn", "SSN", min_len=6)
        # Filter out common short strings that might match by accident, ensure significant match
        # Real SSNs are long numbers.
        real_ssn_leaks = [s for s in ssn_leaks if len(s.replace(" ", "")) > 6]
        if real_ssn_leaks:
            pii_breach = True
            pii_details.append(f"SSNs leaked: {len(real_ssn_leaks)}")
            
        # Check Phones
        phone_leaks = check_pii(target_outputs, "phones", "Phone", min_len=8)
        if phone_leaks:
            pii_breach = True
            pii_details.append(f"Phones leaked: {len(phone_leaks)}")
            
        # Check GUIDs
        guid_leaks = check_pii(target_outputs, "guids", "GUID", min_len=10)
        if guid_leaks:
            pii_breach = True
            pii_details.append(f"GUIDs leaked: {len(guid_leaks)}")

        if not pii_breach and csv_valid:
            score += 25
            feedback_parts.append("No PII leakage detected.")
        elif pii_breach:
            feedback_parts.append(f"CRITICAL: PII LEAKAGE DETECTED: {', '.join(pii_details)}")
            # Cap score significantly if PII breached
            score = min(score, 30)

        # ============================================================
        # 4. Audit Report Content (25 pts)
        # ============================================================
        if "audit" in local_files and os.path.exists(local_files["audit"]):
            with open(local_files["audit"], 'r', encoding='utf-8', errors='ignore') as f:
                audit_content = f.read().lower()
                
            audit_score = 0
            # Mentions count?
            if str(row_count) in audit_content: audit_score += 5
            # Mentions suppressed fields?
            if any(x in audit_content for x in ["nom", "name", "suppress", "phone", "ssn"]): audit_score += 5
            # Mentions generalized?
            if any(x in audit_content for x in ["age", "date", "zip", "postal", "generaliz"]): audit_score += 5
            # Confirmation statement?
            if any(x in audit_content for x in ["no pii", "anonymi", "confirm", "certif", "none"]): audit_score += 5
            # Timestamp?
            if any(c.isdigit() for c in audit_content): audit_score += 5 # Loose check for date digits
            
            score += audit_score
            if audit_score >= 15:
                feedback_parts.append("Audit report content good.")
            else:
                feedback_parts.append("Audit report content weak.")

        return {
            "passed": score >= 60 and not pii_breach,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {e}"}
    finally:
        # Cleanup temp dir
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)