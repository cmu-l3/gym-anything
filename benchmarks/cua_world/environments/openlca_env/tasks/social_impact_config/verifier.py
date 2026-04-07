#!/usr/bin/env python3
"""
Verifier for Social Impact Modeling task.

Requirements:
1. Exported JSON-LD zip file must exist.
2. Inside zip, 'social_indicators' must contain 'Child Labor Risk'.
3. Inside zip, a process must have a 'socialAspects' entry with:
   - value: 1.5
   - comment: "Sector Audit 2025"
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil

logger = logging.getLogger(__name__)

def verify_social_impact_config(traj, env_info, task_info):
    """Verify that social indicators were correctly configured and exported."""
    
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier failed: copy_from_env not available"}

    # 2. Retrieve result metadata
    result_meta_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_meta_path)
        with open(result_meta_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(result_meta_path):
            os.remove(result_meta_path)

    # 3. Initial Scoring based on metadata
    score = 0
    feedback = []
    
    if not result.get("file_found"):
        return {"passed": False, "score": 0, "feedback": "No exported zip file found. Task requires exporting JSON-LD package."}
    
    score += 10
    feedback.append("Export file found.")

    if result.get("created_during_task"):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: File timestamp indicates it might be old.")

    # 4. Deep Inspection of Zip Content
    # We expect the export script to have copied the found file to /tmp/exported_package.zip
    local_zip_path = tempfile.mktemp(suffix='.zip')
    extract_dir = tempfile.mkdtemp()
    
    try:
        # Copy the zip file from container
        copy_from_env("/tmp/exported_package.zip", local_zip_path)
        
        if not zipfile.is_zipfile(local_zip_path):
            return {"passed": False, "score": score, "feedback": "Exported file is not a valid zip archive."}

        with zipfile.ZipFile(local_zip_path, 'r') as z:
            z.extractall(extract_dir)
            
        # Verify Directory Structure (openLCA JSON-LD format)
        # Should contain folders: processes, social_indicators, categories, etc.
        
        # Check Social Indicator
        indicators_dir = os.path.join(extract_dir, "social_indicators")
        indicator_found = False
        indicator_correct_category = False
        
        if os.path.exists(indicators_dir):
            for fname in os.listdir(indicators_dir):
                if fname.endswith(".json"):
                    with open(os.path.join(indicators_dir, fname)) as f:
                        data = json.load(f)
                        if data.get("name") == "Child Labor Risk":
                            indicator_found = True
                            # Check category (might be ID reference or path)
                            # Simple check: does json contain "Human Rights"
                            if "Human Rights" in str(data): 
                                indicator_correct_category = True
                            break
        
        if indicator_found:
            score += 20
            feedback.append("Social Indicator 'Child Labor Risk' found.")
            if indicator_correct_category:
                score += 10
                feedback.append("Indicator is in correct category.")
        else:
            feedback.append("Social Indicator 'Child Labor Risk' NOT found in export.")

        # Check Process Social Aspect
        processes_dir = os.path.join(extract_dir, "processes")
        aspect_found = False
        value_correct = False
        comment_correct = False
        
        if os.path.exists(processes_dir):
            for fname in os.listdir(processes_dir):
                if fname.endswith(".json"):
                    with open(os.path.join(processes_dir, fname)) as f:
                        data = json.load(f)
                        # Look for socialAspects list
                        social_aspects = data.get("socialAspects", [])
                        for aspect in social_aspects:
                            # The aspect might reference the indicator by ID, but the export usually includes the name 
                            # or we can assume if there's only one aspect it's the one.
                            # Better: check value and comment which are unique enough here.
                            
                            # Check values (handle string/float)
                            raw_amount = aspect.get("rawAmount") or aspect.get("value")
                            comment = aspect.get("comment") or aspect.get("description")
                            
                            if str(raw_amount) == "1.5":
                                aspect_found = True
                                value_correct = True
                                if comment and "Sector Audit 2025" in comment:
                                    comment_correct = True
                                break
                        if aspect_found:
                            break
                            
        if aspect_found:
            score += 20
            feedback.append("Social aspect linked to process.")
        else:
            feedback.append("No process with a social aspect value of 1.5 found.")
            
        if value_correct:
            score += 15 # Redundant with aspect_found logic but good for explicit scoring breakdown
        
        if comment_correct:
            score += 15
            feedback.append("Social aspect comment matches.")
        else:
            if aspect_found:
                feedback.append("Social aspect comment incorrect.")

    except Exception as e:
        feedback.append(f"Error inspecting zip content: {e}")
    finally:
        if os.path.exists(local_zip_path):
            os.remove(local_zip_path)
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }