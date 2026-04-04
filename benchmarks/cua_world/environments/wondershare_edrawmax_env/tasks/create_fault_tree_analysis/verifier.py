#!/usr/bin/env python3
"""
Verifier for create_fault_tree_analysis task.

Checks:
1. .eddx file creation and validity (ZIP archive).
2. .png file creation and validity.
3. Content analysis of .eddx to ensure specific FTA labels are present.
4. Timestamps to ensure files were created during the task.
"""

import os
import json
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_fault_tree_analysis(traj, env_info, task_info):
    """
    Verify the Fault Tree Analysis diagram creation.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result metadata from export_result.sh
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Required text labels from task description
    required_labels = [
        "Database Connection Failure",
        "Network Timeout",
        "Authentication Failure",
        "Firewall Misconfiguration",
        "Expired Service Account"
    ]

    # --- Criterion 1: EDDX File Existence & Validity (20 pts) ---
    eddx_exists = task_result.get("eddx_exists", False)
    eddx_created = task_result.get("eddx_created_during_task", False)
    eddx_size = task_result.get("eddx_size_bytes", 0)
    
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix=".eddx")
    eddx_valid_zip = False
    eddx_content_text = ""

    if eddx_exists and eddx_size > 1000: # Minimal valid file size check
        try:
            copy_from_env("/home/ga/Documents/fta_db_failure.eddx", temp_eddx.name)
            
            # EdrawMax .eddx files are ZIP archives containing XML
            try:
                with zipfile.ZipFile(temp_eddx.name, "r") as zf:
                    names = zf.namelist()
                    if names:
                        eddx_valid_zip = True
                        # Aggregate all text content from XML files in the archive
                        for name in names:
                            if name.endswith(".xml"):
                                try:
                                    eddx_content_text += zf.read(name).decode("utf-8", errors="ignore")
                                except:
                                    pass
            except zipfile.BadZipFile:
                feedback_parts.append("EDDX file is not a valid ZIP archive.")
        except Exception as e:
            feedback_parts.append(f"Failed to copy EDDX file: {e}")
    
    if eddx_exists and eddx_valid_zip:
        if eddx_created:
            score += 20
            feedback_parts.append("Valid .eddx file created.")
        else:
            score += 10 # Partial credit if it exists but timestamp is weird (unlikely with clean start)
            feedback_parts.append("Valid .eddx file exists but timestamp check failed.")
    else:
        feedback_parts.append("No valid .eddx file found.")

    # --- Criterion 2: PNG Export Existence (20 pts) ---
    png_exists = task_result.get("png_exists", False)
    png_created = task_result.get("png_created_during_task", False)
    png_size = task_result.get("png_size_bytes", 0)

    if png_exists and png_size > 1000:
        if png_created:
            score += 20
            feedback_parts.append("Valid .png export created.")
        else:
            score += 10
            feedback_parts.append(".png export exists but timestamp check failed.")
    else:
        feedback_parts.append("No valid .png export found.")

    # --- Criterion 3: Content Verification (60 pts) ---
    # We check if the required text labels exist in the EDDX XML content
    if eddx_valid_zip and eddx_content_text:
        found_labels = 0
        missing_labels = []
        
        for label in required_labels:
            # Simple case-insensitive check, though Edraw usually stores exact text
            if label in eddx_content_text:
                found_labels += 1
            else:
                missing_labels.append(label)
        
        # Calculate score based on found labels
        # 5 labels total, allocate 60 points (12 points per label)
        label_score = found_labels * 12
        score += label_score
        
        if found_labels == len(required_labels):
            feedback_parts.append("All required diagrams labels found.")
        else:
            feedback_parts.append(f"Found {found_labels}/{len(required_labels)} labels. Missing: {', '.join(missing_labels)}")
            
    elif eddx_exists:
        feedback_parts.append("Could not read text content from EDDX file.")

    # Cleanup
    if os.path.exists(temp_eddx.name):
        os.unlink(temp_eddx.name)

    # Final logic
    # Pass threshold: 60 points (Must have file + most labels, or files + partial labels)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }