#!/usr/bin/env python3
"""
Verifier for steganography_eof_triage task.
Reads the post-task JSON payload via copy_from_env and scores against criteria.
"""

import json
import tempfile
import os

def verify_steganography_eof_triage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Attempt to copy the JSON result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/steg_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Case Creation & Data Source (15 pts)
    if result.get("case_db_found") and result.get("data_source_added"):
        score += 15
        feedback_parts.append("[+] Case DB and Data Source configured correctly (+15)")
    else:
        feedback_parts.append("[-] Case DB or Data Source missing")

    # Criterion 2: Ingest Configuration (15 pts)
    if result.get("ingest_completed"):
        score += 15
        feedback_parts.append("[+] Ingest completed (JPEGs identified) (+15)")
    else:
        feedback_parts.append("[-] Ingest modules missing or did not complete")

    # Criterion 3: Artifact Extraction (20 pts)
    ext_count = result.get("extracted_count", 0)
    if ext_count >= 10:
        score += 20
        feedback_parts.append(f"[+] Extraction excellent ({ext_count} files) (+20)")
    elif ext_count >= 5:
        score += 10
        feedback_parts.append(f"[~] Extraction partial ({ext_count} files) (+10)")
    else:
        feedback_parts.append(f"[-] Extraction poor or missing ({ext_count} files)")

    # Criterion 4: CSV Report Structure (10 pts)
    agent_csv = result.get("agent_csv", {})
    if result.get("csv_exists") and len(agent_csv) > 0:
        score += 10
        feedback_parts.append("[+] CSV report exists with proper header (+10)")
    else:
        feedback_parts.append("[-] CSV report missing or malformed")

    # Criterion 5: Heuristic Analysis Accuracy (25 pts)
    # Compares the agent's math against the actual files they extracted
    gt_files = result.get("gt_files", {})
    correct_calcs = 0
    total_eval = len(agent_csv)
    
    if total_eval > 0:
        for fname, agent_data in agent_csv.items():
            if fname in gt_files:
                gt_data = gt_files[fname]
                if (agent_data["size"] == gt_data["size"] and
                    agent_data["last_eoi_offset"] == gt_data["last_eoi_offset"] and
                    agent_data["extraneous_bytes"] == gt_data["extraneous_bytes"]):
                    correct_calcs += 1
        
        accuracy = correct_calcs / total_eval
        if accuracy >= 0.9:
            score += 25
            feedback_parts.append(f"[+] Heuristic math highly accurate ({correct_calcs}/{total_eval}) (+25)")
        elif accuracy > 0:
            pts = int(25 * accuracy)
            score += pts
            feedback_parts.append(f"[~] Heuristic math partially accurate ({correct_calcs}/{total_eval}) (+{pts})")
        else:
            feedback_parts.append("[-] Heuristic math incorrect for all records")
    else:
        feedback_parts.append("[-] No math records to evaluate")

    # Criterion 6: Summary Report Integrity (15 pts)
    summary_content = result.get("summary_content", "").upper()
    if result.get("summary_exists"):
        has_total = "TOTAL_JPEGS" in summary_content
        has_appended = "APPENDED_DATA" in summary_content
        has_suspicious = "SUSPICIOUS_FILES" in summary_content
        
        if has_total and has_appended and has_suspicious:
            score += 15
            feedback_parts.append("[+] Summary report format correct (+15)")
        elif has_total or has_appended or has_suspicious:
            score += 7
            feedback_parts.append("[~] Summary report partially correct (+7)")
        else:
            feedback_parts.append("[-] Summary report missing required sections")
    else:
        feedback_parts.append("[-] Summary report missing")

    # Pass threshold logic
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }