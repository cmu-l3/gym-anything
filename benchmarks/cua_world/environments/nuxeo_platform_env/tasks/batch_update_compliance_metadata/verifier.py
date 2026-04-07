#!/usr/bin/env python3
"""
Verifier for batch_update_compliance_metadata task.

Checks:
1. Three specific documents have correct dc:source, dc:rights, dc:coverage.
2. Annual Report 2023 additionally has correct dc:format.
3. Modification timestamps are after task start (anti-gaming).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_common = metadata.get('expected_values', {
        "dc:source": "Regulatory Compliance Division",
        "dc:rights": "RESTRICTED - Internal Use Only - SOX Compliant",
        "dc:coverage": "United States - Financial Operations"
    })
    
    # Specific requirements
    annual_report_reqs = metadata.get('special_requirements', {}).get(
        "/default-domain/workspaces/Projects/Annual-Report-2023", 
        {"dc:format": "PDF/A-1b"}
    )

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result_data.get('task_start', 0)
    documents = result_data.get('documents', [])
    
    if not documents:
        return {"passed": False, "score": 0, "feedback": "No document data found in export"}

    score = 0
    max_score = 100
    feedback = []
    
    # Define scoring weights
    # Total points per doc for common fields: 8+8+8 = 24
    # 3 docs * 24 = 72 points
    # Annual report extra field: 10 points
    # Timestamps: 18 points (6 per doc)
    # Total: 100
    
    docs_fully_correct = 0

    for doc in documents:
        path = doc.get('path', '')
        props = doc.get('properties', {})
        doc_name = path.split('/')[-1]
        
        doc_score = 0
        doc_feedback = []
        is_fully_correct = True
        
        # Check common fields
        for field, expected in expected_common.items():
            actual = props.get(field)
            if actual == expected:
                doc_score += 8
            else:
                is_fully_correct = False
                doc_feedback.append(f"Wrong {field} (got '{actual}')")
        
        # Check specific fields for Annual Report
        if "Annual-Report-2023" in path:
            fmt_expected = annual_report_reqs.get("dc:format")
            actual_fmt = props.get("dc:format")
            if actual_fmt == fmt_expected:
                doc_score += 10
            else:
                is_fully_correct = False
                doc_feedback.append(f"Wrong dc:format (got '{actual_fmt}')")
        
        # Check timestamp (anti-gaming)
        # Nuxeo time format: 2023-10-27T10:00:00.00Z
        mod_time_str = props.get('dc:modified', '')
        timestamp_valid = False
        if mod_time_str:
            try:
                # Handle Z or timezone offsets roughly
                mod_time_str = mod_time_str.replace('Z', '+00:00')
                dt = datetime.fromisoformat(mod_time_str)
                ts = dt.timestamp()
                if ts > task_start:
                    timestamp_valid = True
                    doc_score += 6
                else:
                    doc_feedback.append("Not modified during task")
            except Exception:
                doc_feedback.append("Invalid timestamp")
        else:
            doc_feedback.append("No modification time")

        score += doc_score
        
        if is_fully_correct and timestamp_valid:
            docs_fully_correct += 1
            feedback.append(f"✅ {doc_name}: Perfect")
        elif doc_score > 0:
            feedback.append(f"⚠️ {doc_name}: Partial ({', '.join(doc_feedback)})")
        else:
            feedback.append(f"❌ {doc_name}: No valid updates")

    # Pass logic
    # Must have at least 2 fully correct documents to pass
    passed = docs_fully_correct >= 2
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }