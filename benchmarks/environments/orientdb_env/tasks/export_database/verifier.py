#!/usr/bin/env python3
"""
Verifier for export_database task.

Checks:
1. File existence and size
2. Valid GZIP format
3. Valid JSON structure (OrientDB export format)
4. Presence of specific schema classes
5. Presence of real data records
6. Creation timestamp validity (anti-gaming)
"""

import json
import os
import gzip
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_database(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_classes = metadata.get('expected_classes', ["Hotels", "Profiles", "Restaurants", "Countries"])
    expected_markers = metadata.get('expected_data_markers', ["Hotel Artemide", "Italy"])

    score = 0
    feedback_parts = []
    
    # 1. Read metadata result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic criteria checks from metadata
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "No export file found in /home/ga/exports/"}
    
    score += 15
    feedback_parts.append("Export file found")

    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("WARN: File timestamp predates task start (potential gaming)")

    # 2. Inspect the actual export file
    # We copy the file out of the container to analyze it safely on the host
    temp_export = tempfile.NamedTemporaryFile(delete=False, suffix='.gz')
    export_content = ""
    is_valid_gzip = False
    is_valid_json = False
    
    try:
        # The export script copied the found file to /tmp/submission_export.file
        copy_from_env("/tmp/submission_export.file", temp_export.name)
        
        # Check GZIP validity
        try:
            with gzip.open(temp_export.name, 'rt', encoding='utf-8') as f:
                export_content = f.read()
            is_valid_gzip = True
            score += 15
            feedback_parts.append("Valid GZIP archive")
        except (OSError, gzip.BadGzipFile):
            # Fallback: maybe it's plain JSON (user forgot to gzip)
            feedback_parts.append("Not a valid GZIP file")
            try:
                with open(temp_export.name, 'r', encoding='utf-8') as f:
                    export_content = f.read()
                if len(export_content) > 0:
                    feedback_parts.append("Read as plain text/JSON")
            except Exception:
                feedback_parts.append("Could not read file content")

        # Check JSON validity / Export format
        if export_content:
            try:
                data = json.loads(export_content)
                is_valid_json = True
                
                # OrientDB exports usually have 'info', 'clusters', 'schema', 'records' keys
                # or sometimes they are a list of objects if exported differently.
                # We accept standard JSON structure.
                keys = set(data.keys()) if isinstance(data, dict) else set()
                orient_keys = {"info", "classes", "records", "schema", "clusters"}
                
                if keys & orient_keys:
                    score += 15
                    feedback_parts.append("Valid OrientDB export structure")
                else:
                    score += 10 # Partial for valid JSON but unsure structure
                    feedback_parts.append("Valid JSON")
            except json.JSONDecodeError:
                # OrientDB sometimes produces "JSON-like" exports that are not strict JSON
                # (e.g. concatenated objects). We'll fallback to text search.
                feedback_parts.append("Content is text but not strict JSON")
    
    except Exception as e:
        feedback_parts.append(f"Error analyzing file: {str(e)}")
    finally:
        if os.path.exists(temp_export.name):
            os.unlink(temp_export.name)

    # 3. Content Verification (Text Search)
    # Even if JSON parsing fails, we search for strings in the content
    if export_content:
        # Check Schema Classes
        classes_found = 0
        for cls in expected_classes:
            # Look for class definition or usage
            if f'"{cls}"' in export_content or f"'{cls}'" in export_content:
                classes_found += 1
        
        if classes_found >= 3:
            score += 20
            feedback_parts.append(f"Schema classes found ({classes_found}/{len(expected_classes)})")
        elif classes_found > 0:
            score += 10
            feedback_parts.append(f"Some schema classes found ({classes_found})")
        else:
            feedback_parts.append("No expected schema classes found")

        # Check Data Markers (Anti-gaming / Real Data check)
        markers_found = 0
        for marker in expected_markers:
            if marker in export_content:
                markers_found += 1
        
        if markers_found >= 3:
            score += 25
            feedback_parts.append(f"Real data records found ({markers_found}/{len(expected_markers)})")
        elif markers_found > 0:
            score += 10
            feedback_parts.append(f"Some data records found ({markers_found})")
        else:
            feedback_parts.append("No expected data records found")

    # Final logic
    passed = score >= 70 and result.get('file_exists') and (is_valid_gzip or is_valid_json)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }