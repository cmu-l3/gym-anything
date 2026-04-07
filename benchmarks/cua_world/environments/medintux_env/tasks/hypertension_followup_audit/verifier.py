#!/usr/bin/env python3
"""
Verifier for hypertension_followup_audit task.
"""

import json
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hypertension_audit(traj, env_info, task_info):
    """
    Verify the agent's CSV report against ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth Data
    GT_TARGETS = {
        "DUBOIS Paul": 45.0,
        "ROUX Julie": 10.0
    }
    # Variation in name format is allowed (First Last vs Last First), we will normalize in check
    # But MedinTux usually separates Nom/Prenom. Task asked for "PatientName".
    
    score = 0
    feedback = []
    
    # Load result JSON
    import tempfile
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # Get JSON result
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        # Check basic file existence
        if not result.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Report file not found at /home/ga/Documents/hta_audit_report.csv"}
        
        if not result.get("file_created_during_task"):
            return {"passed": False, "score": 0, "feedback": "Report file was not created during the task window."}
            
        score += 10 # File exists and created newly
        
        # Get CSV content
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
        copy_from_env("/tmp/hta_audit_report_copy.csv", temp_csv.name)
        
        rows = []
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            if header:
                # Normalize header to lowercase for robust checking
                header_lower = [h.strip().lower() for h in header]
                if 'patientname' in header_lower and 'avgdaysbetweenvisits' in header_lower:
                    score += 10
                    feedback.append("CSV headers correct.")
                else:
                    feedback.append(f"CSV headers incorrect. Found: {header}")
                
                # Map columns
                try:
                    name_idx = header_lower.index('patientname')
                    avg_idx = header_lower.index('avgdaysbetweenvisits')
                    visit_idx = header_lower.index('visitcount') if 'visitcount' in header_lower else -1
                except ValueError:
                    name_idx, avg_idx = 0, 2 # Fallback to indices
                
                for row in reader:
                    if len(row) > max(name_idx, avg_idx):
                        rows.append(row)
        
        # Analyze Content
        found_patients = {}
        extra_patients = []
        
        for row in rows:
            try:
                raw_name = row[name_idx].strip()
                # Normalize name (remove spaces, case insensitive) for matching
                norm_name = raw_name.upper().replace(" ", "")
                
                # Try to find in GT
                matched_gt = None
                for gt_name in GT_TARGETS:
                    gt_norm = gt_name.upper().replace(" ", "")
                    # Check both "FirstLast" and "LastFirst"
                    gt_norm_rev = "".join(reversed(gt_name.upper().split(" ")))
                    
                    if norm_name == gt_norm or norm_name == gt_norm_rev:
                        matched_gt = gt_name
                        break
                
                if matched_gt:
                    val = float(row[avg_idx])
                    found_patients[matched_gt] = val
                else:
                    extra_patients.append(raw_name)
                    
            except (ValueError, IndexError):
                continue
                
        # Scoring Logic
        
        # Precision/Recall
        gt_keys = set(GT_TARGETS.keys())
        found_keys = set(found_patients.keys())
        
        missing = gt_keys - found_keys
        
        if not missing:
            score += 30
            feedback.append("All target hypertensive patients found.")
        elif len(found_keys) > 0:
            score += 15
            feedback.append(f"Some target patients found. Missing: {missing}")
        else:
            feedback.append("No target patients found.")
            
        # Check output accuracy
        accuracy_score = 0
        for name, val in found_patients.items():
            expected = GT_TARGETS[name]
            if abs(val - expected) <= 1.0:
                accuracy_score += 15
                feedback.append(f"Correct interval for {name}: {val}")
            else:
                feedback.append(f"Incorrect interval for {name}: Expected {expected}, got {val}")
        
        # Max accuracy score is 30 (15 * 2 patients)
        score += min(accuracy_score, 30)
        
        # Check exclusions
        # "PETIT Sophie", "BLANC Jean", "LEGRAND Marc" should NOT be in the list
        # We checked extra_patients earlier
        exclusions_failed = False
        for extra in extra_patients:
            extra_upper = extra.upper()
            if "PETIT" in extra_upper or "BLANC" in extra_upper or "LEGRAND" in extra_upper:
                exclusions_failed = True
                feedback.append(f"Failed to exclude ineligible patient: {extra}")
        
        if not exclusions_failed and len(extra_patients) == 0:
            score += 20
            feedback.append("Correctly excluded ineligible patients.")
        elif not exclusions_failed:
             # Found unknowns but not the specific distractors
            score += 10
            
    except Exception as e:
        feedback.append(f"Verification error: {str(e)}")
        
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }