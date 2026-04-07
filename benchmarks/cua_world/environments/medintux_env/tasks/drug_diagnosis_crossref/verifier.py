#!/usr/bin/env python3
"""
Verifier for drug_diagnosis_crossref task.

Checks:
1. Report file existence and creation time.
2. Report content analysis:
   - Coverage of ATC codes (A-Z)
   - Mapping structure (ATC <-> CIM10)
   - Numerical accuracy (compared against ground truth queries)
   - Gap analysis identification
3. Process evidence (did they actually use the DB?)
"""

import json
import base64
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_drug_diagnosis_crossref(traj, env_info, task_info):
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
            
    score = 0
    feedback = []
    
    # 1. Basic File Checks (15 pts)
    if not result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found"}
        
    score += 10
    feedback.append("Report file created")
    
    if result.get('file_created_during_task', False):
        score += 5
        feedback.append("File created during task window")
    else:
        feedback.append("WARNING: File timestamp predates task (anti-gaming)")
        
    # 2. Content Analysis (Decode output)
    content_b64 = result.get('report_content_b64', "")
    try:
        report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        report_text = ""
        
    if len(report_text) < 100:
        return {"passed": False, "score": score, "feedback": "Report content too short or empty"}

    # 3. Check for ATC Code Coverage (15 pts)
    # Looking for lines starting with single letters A, B, C etc followed by text or numbers
    # Or just mentions of ATC codes.
    atc_matches = re.findall(r'\b([A-Z])\s*[|:-]\s*', report_text)
    atc_codes_found = set([m for m in atc_matches if m in "ABCDGHJLMNPRSV"])
    
    if len(atc_codes_found) >= 8:
        score += 15
        feedback.append(f"Good ATC coverage ({len(atc_codes_found)} categories)")
    elif len(atc_codes_found) >= 4:
        score += 7
        feedback.append(f"Partial ATC coverage ({len(atc_codes_found)} categories)")
    else:
        feedback.append("Insufficient ATC categories mapped")

    # 4. Check for CIM10/ICD10 References (15 pts)
    # Look for keywords like "Chapter", "Chapitre", or ranges like "A00-B99"
    cim_matches = re.findall(r'(Chapter|Chapitre|I[V|X]|V|X|A00|K00|C00)', report_text, re.IGNORECASE)
    if len(cim_matches) >= 5:
        score += 15
        feedback.append("CIM10/ICD10 chapters referenced")
    else:
        score += 5
        feedback.append("Weak CIM10 references")

    # 5. Data Accuracy Check (25 pts)
    # Compare numbers in text against ground truth
    gt = result.get('ground_truth', {})
    gt_atc = gt.get('atc_counts', [])
    
    # Create a map of GT counts
    gt_map = {item['code']: item['count'] for item in gt_atc}
    
    # Try to extract numbers associated with ATC codes in the report
    # Simple heuristic: Look for lines with an ATC code letter and a number
    accurate_counts = 0
    detected_counts = 0
    
    for code, true_count in gt_map.items():
        if code not in "ABCDGHJLMNPRSV": continue # Skip non-major codes
        
        # Regex: Code followed by... number ... 
        # e.g., "A | 150" or "A: 150"
        pattern = re.compile(rf"\b{code}\b.*?(\d+)", re.IGNORECASE)
        match = pattern.search(report_text)
        if match:
            try:
                val = int(match.group(1))
                detected_counts += 1
                # 25% tolerance
                if abs(val - true_count) / (true_count + 1) < 0.25:
                    accurate_counts += 1
            except:
                pass
                
    if detected_counts > 0:
        accuracy_score = min(25, (accurate_counts / detected_counts) * 25)
        # Bonus if they found at least some
        if accurate_counts >= 3: 
            score += 25
            feedback.append(f"Data accuracy verified ({accurate_counts}/{detected_counts} matches)")
        elif detected_counts >= 3:
            score += 10
            feedback.append("Counts present but diverge from ground truth (different grouping?)")
    else:
        feedback.append("No numeric data associated with ATC codes found")

    # 6. Gap Analysis (10 pts)
    if re.search(r'(gap|missing|manque|vide|none|aucun|zero|0)', report_text, re.IGNORECASE):
        score += 10
        feedback.append("Gap analysis section detected")
        
    # 7. Database mentions (5 pts)
    if "MedicaTux" in report_text or "CIM10" in report_text:
        score += 5
        feedback.append("Database sources cited")
        
    # 8. Structure (10 pts)
    # Check for tabular structure (lines with | or multiple tabs)
    if "|" in report_text or report_text.count("\t") > 10:
        score += 10
        feedback.append("Report is structured/tabular")

    # 9. Process Evidence (5 pts)
    if result.get('process_evidence', False):
        score += 5
        feedback.append("Process evidence found (MySQL usage)")
        
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }