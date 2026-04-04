#!/usr/bin/env python3
"""
Verifier for retrieve_wfs_filtered_features task.

Verifies:
1. GeoJSON file creation, validity, and correct CQL filtering (Europe only).
2. Report file creation and accuracy (Count matches, Names sorted).
3. Anti-gaming via timestamps and PostGIS ground truth cross-reference.
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retrieve_wfs_filtered_features(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load summary result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract Data
    geojson_meta = result_data.get('geojson', {})
    report_meta = result_data.get('report', {})
    ground_truth_count = int(result_data.get('ground_truth_count', 0))

    # =========================================================
    # 1. GeoJSON Verification (60 points total)
    # =========================================================
    
    # Check existence (10 pts)
    if geojson_meta.get('exists'):
        score += 10
        feedback_parts.append("GeoJSON file exists")
    else:
        feedback_parts.append("GeoJSON file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check validity and content (Requires reading the actual file)
    temp_geojson = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/exported_geojson.json", temp_geojson.name)
        with open(temp_geojson.name, 'r') as f:
            geojson_content = json.load(f)
            
        # Structure check (10 pts)
        if geojson_content.get('type') == 'FeatureCollection' and isinstance(geojson_content.get('features'), list):
            score += 10
            feedback_parts.append("Valid GeoJSON structure")
            
            features = geojson_content['features']
            feature_count = len(features)
            
            # Content Logic Check (20 pts)
            # Verify ALL features are actually in Europe
            non_europe_found = False
            names_in_json = []
            
            for feat in features:
                props = feat.get('properties', {})
                continent = props.get('continent', 'Unknown')
                name = props.get('name', 'Unknown')
                names_in_json.append(name)
                
                if continent != 'Europe':
                    non_europe_found = True
            
            if not non_europe_found and feature_count > 0:
                score += 20
                feedback_parts.append("All features are correctly filtered (Europe only)")
            elif feature_count == 0:
                feedback_parts.append("GeoJSON contains no features")
            else:
                feedback_parts.append("GeoJSON contains non-European features (CQL filter failed)")

            # Count vs Ground Truth (10 pts)
            # We allow a tiny tolerance just in case of weird data versions, but generally should be exact
            if abs(feature_count - ground_truth_count) == 0:
                score += 10
                feedback_parts.append(f"Feature count matches ground truth ({feature_count})")
            else:
                feedback_parts.append(f"Feature count mismatch: got {feature_count}, expected {ground_truth_count}")

            # Geometry Check (10 pts)
            # Check if geometries are present (not null)
            has_geometry = all(f.get('geometry') is not None for f in features)
            if has_geometry and feature_count > 0:
                score += 10
                feedback_parts.append("Features contain valid geometries")
            else:
                feedback_parts.append("Features missing geometries")

        else:
            feedback_parts.append("Invalid GeoJSON structure (not a FeatureCollection)")

    except Exception as e:
        feedback_parts.append(f"Failed to parse GeoJSON content: {e}")
    finally:
        if os.path.exists(temp_geojson.name):
            os.unlink(temp_geojson.name)

    # =========================================================
    # 2. Report Verification (30 points total)
    # =========================================================
    
    # Existence (5 pts)
    if report_meta.get('exists'):
        score += 5
        feedback_parts.append("Report file exists")
        
        # Parse Report Content
        try:
            # We decoded base64 in export script or we can read file directly if copy works
            # Let's try reading the copied file for full content
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/exported_report.txt", temp_report.name)
            
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
                
            if len(lines) > 0:
                # Check Count Line (15 pts)
                first_line = lines[0]
                try:
                    reported_count = int(first_line)
                    # Compare reported count to ACTUAL geojson count we calculated above
                    if reported_count == len(names_in_json):
                        score += 15
                        feedback_parts.append(f"Reported count correct ({reported_count})")
                    else:
                        feedback_parts.append(f"Reported count ({reported_count}) does not match GeoJSON count ({len(names_in_json)})")
                except ValueError:
                    feedback_parts.append("First line of report is not an integer count")

                # Check Sorting (10 pts)
                if len(lines) > 1:
                    reported_names = lines[1:]
                    is_sorted = all(reported_names[i] <= reported_names[i+1] for i in range(len(reported_names)-1))
                    
                    # Verify content matches json
                    json_names_set = set(names_in_json)
                    report_names_set = set(reported_names)
                    sets_match = json_names_set == report_names_set

                    if is_sorted and sets_match:
                        score += 10
                        feedback_parts.append("Country names list is correct and sorted")
                    elif not sets_match:
                        feedback_parts.append("Reported names do not match GeoJSON content")
                    elif not is_sorted:
                        feedback_parts.append("Reported names are not sorted alphabetically")
            else:
                feedback_parts.append("Report file is empty")
                
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

        except Exception as e:
            feedback_parts.append(f"Error verification report content: {e}")

    else:
        feedback_parts.append("Report file missing")

    # =========================================================
    # 3. Anti-Gaming / Timestamp (10 points total)
    # =========================================================
    files_new = geojson_meta.get('created_during_task') and report_meta.get('created_during_task')
    if files_new:
        score += 10
        feedback_parts.append("Files created during task session")
    else:
        feedback_parts.append("Files have stale timestamps")

    # Final result construction
    passed = score >= 60 and geojson_meta.get('exists') and report_meta.get('exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }