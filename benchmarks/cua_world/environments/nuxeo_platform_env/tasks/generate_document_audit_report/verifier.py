#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_document_audit_report(traj, env_info, task_info):
    """
    Verifies the Document Audit Report task.
    Criteria:
    1. File exists and is valid JSON.
    2. File was created during the task (anti-gaming).
    3. JSON structure matches the specification.
    4. Content accuracy: Entries match real Nuxeo audit logs (Cross-validated with Ground Truth).
    5. Coverage: Includes entries for at least 2 distinct documents.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Temp files for artifacts
    result_meta_path = tempfile.mktemp()
    agent_output_path = tempfile.mktemp()
    ground_truth_path = tempfile.mktemp()

    try:
        # 1. Fetch artifacts
        copy_from_env("/tmp/task_result.json", result_meta_path)
        
        # Check if output exists before trying to copy it
        with open(result_meta_path, 'r') as f:
            meta = json.load(f)
        
        if not meta.get("output_exists"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file /home/ga/audit_report.json was not created."
            }

        copy_from_env("/home/ga/audit_report.json", agent_output_path)
        copy_from_env("/tmp/ground_truth_audit.json", ground_truth_path)

        # 2. Parse Files
        try:
            with open(agent_output_path, 'r') as f:
                agent_data = json.load(f)
        except json.JSONDecodeError:
            return {
                "passed": False, 
                "score": 10, 
                "feedback": "Output file exists but is not valid JSON."
            }
            
        with open(ground_truth_path, 'r') as f:
            gt_data = json.load(f)

        score = 0
        feedback = []

        # Criterion: File created during task (Anti-gaming)
        if meta.get("file_created_during_task"):
            score += 10
            feedback.append("File created during task (+10).")
        else:
            feedback.append("WARNING: File timestamp predates task start.")

        # Criterion: JSON Structure (Top Level)
        required_keys = ["report_title", "generated_at", "workspace_path", "total_entries", "entries"]
        missing_keys = [k for k in required_keys if k not in agent_data]
        
        if not missing_keys:
            score += 10
            feedback.append("JSON structure correct (+10).")
        else:
            feedback.append(f"Missing JSON keys: {missing_keys}")

        # Criterion: Workspace Path Accuracy
        if agent_data.get("workspace_path") == "/default-domain/workspaces/Projects":
            score += 5
            feedback.append("Workspace path correct (+5).")
        else:
            feedback.append("Incorrect workspace path in report.")

        # Criterion: Entries Analysis
        entries = agent_data.get("entries", [])
        if not isinstance(entries, list):
            entries = []
            feedback.append("Entries is not a list.")
        
        if len(entries) > 0:
            score += 10
            feedback.append(f"Report contains {len(entries)} entries (+10).")
        else:
            return {"passed": False, "score": score, "feedback": "Report contains no entries."}

        # Check fields in entries
        entry_req_fields = ["document_title", "document_path", "event_id", "event_date", "principal", "category"]
        valid_entries = 0
        distinct_docs = set()
        
        for entry in entries:
            if all(k in entry for k in entry_req_fields):
                valid_entries += 1
                distinct_docs.add(entry.get("document_path"))
        
        if valid_entries == len(entries):
            score += 10
            feedback.append("All entries have required fields (+10).")
        elif valid_entries > 0:
            score += 5
            feedback.append("Some entries missing fields (+5).")

        # Criterion: Distinct Documents Coverage
        if len(distinct_docs) >= 2:
            score += 15
            feedback.append(f"Covered {len(distinct_docs)} distinct documents (+15).")
        else:
            feedback.append(f"Only covered {len(distinct_docs)} document(s) (expected >= 2).")

        # Criterion: Accuracy Check against Ground Truth
        # We check if a sample of agent entries corresponds to real events
        gt_entries = gt_data.get("audit_entries", [])
        matches = 0
        
        # Create a lookup set for GT events (path + event_id + category)
        # Note: dates might differ slightly in format, so we exclude them from strict lookup key
        gt_lookup = set()
        for g in gt_entries:
            key = (g.get("doc_path"), g.get("event_id"), g.get("principal"))
            gt_lookup.add(key)
            
        for a in entries:
            key = (a.get("document_path"), a.get("event_id"), a.get("principal"))
            if key in gt_lookup:
                matches += 1
        
        accuracy_ratio = matches / len(entries) if len(entries) > 0 else 0
        
        if accuracy_ratio > 0.8:
            score += 40
            feedback.append("High data accuracy (>80% match with system audit log) (+40).")
        elif accuracy_ratio > 0.4:
            score += 20
            feedback.append("Moderate data accuracy (>40% match) (+20).")
        else:
            feedback.append("Low data accuracy - entries do not match system audit log.")

        # Final score calculation
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        # Cleanup
        for p in [result_meta_path, agent_output_path, ground_truth_path]:
            if os.path.exists(p):
                os.unlink(p)