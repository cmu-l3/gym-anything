#!/usr/bin/env python3
"""
Verifier for externalize_config_values task.
Checks if hardcoded values were moved to config.properties and code updated.
"""

import json
import tempfile
import os
import re
import logging
import configparser
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_externalize_config_values(traj, env_info, task_info):
    """
    Verify the externalization of configuration values.
    
    Criteria:
    1. config.properties created with correct values (40 pts)
    2. Hardcoded values removed from source code (40 pts)
    3. Project builds successfully (10 pts)
    4. Loading mechanism evidence (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    hardcoded = metadata.get('hardcoded_values', {})
    
    # Define the exact hardcoded strings to look for (failure if found)
    forbidden_strings = {
        "DatabaseService.java": [
            hardcoded.get("db_url", "jdbc:postgresql://prod-db.internal:5432/appworks"),
            hardcoded.get("db_user", "app_user"),
            hardcoded.get("db_pass", "s3cureP@ss!"),
            # int values as strings
            hardcoded.get("db_pool", "10") 
        ],
        "ApiClient.java": [
            hardcoded.get("api_url", "https://api.external-service.com/v2"),
            hardcoded.get("api_key", "ak_live_7f8g9h0j1k2l3m4n"),
            hardcoded.get("api_timeout", "5000")
        ],
        "FileProcessor.java": [
            hardcoded.get("file_in", "/data/incoming"),
            hardcoded.get("file_out", "/data/processed"),
            hardcoded.get("file_size", "50")
        ]
    }

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # === Criterion 1: Properties File (40 pts) ===
    props_exists = result.get("properties_exists", False)
    props_created = result.get("properties_created_during_task", False)
    props_content = result.get("properties_content", "")
    
    if props_exists and props_created:
        # Parse properties (Java properties files are similar to INI but without sections)
        # We'll use a dummy section to parse with ConfigParser
        try:
            # Handle potential java properties escaping
            dummy_content = "[DUMMY]\n" + props_content
            parser = configparser.ConfigParser()
            parser.read_string(dummy_content)
            props = dict(parser.items("DUMMY"))
            
            # Check for values (keys might differ, so we check if values are present)
            found_values = 0
            required_values = [v.lower() for v in hardcoded.values()]
            
            # Helper to check if a required value is in the properties values
            # We relax exact match for integers (50 vs 50.0) but these are strings
            props_values_str = [str(v).lower() for v in props.values()]
            
            matches = 0
            for req in required_values:
                # Simple check: is the required value present in any property value?
                # This handles keys being named differently than expected
                if any(req == pv or req in pv for pv in props_values_str):
                    matches += 1
            
            if matches >= 10:
                score += 40
                feedback_parts.append("All configuration values found in properties file")
            elif matches >= 5:
                score += 20
                feedback_parts.append(f"Some configuration values found ({matches}/10)")
            else:
                score += 5
                feedback_parts.append(f"Properties file exists but few correct values found ({matches}/10)")
                
        except Exception as e:
            score += 10
            feedback_parts.append(f"Properties file exists but failed to parse: {e}")
    else:
        feedback_parts.append("config.properties not created")

    # === Criterion 2: Hardcoded Values Removed (40 pts) ===
    files_checked = 0
    clean_files = 0
    
    # Check DatabaseService
    db_content = result.get("db_service_content", "")
    if db_content:
        files_checked += 1
        found_forbidden = [s for s in forbidden_strings["DatabaseService.java"] if s in db_content]
        if not found_forbidden:
            clean_files += 1
        else:
            feedback_parts.append(f"DatabaseService still contains: {found_forbidden[0]}...")

    # Check ApiClient
    api_content = result.get("api_client_content", "")
    if api_content:
        files_checked += 1
        found_forbidden = [s for s in forbidden_strings["ApiClient.java"] if s in api_content]
        if not found_forbidden:
            clean_files += 1
        else:
            feedback_parts.append(f"ApiClient still contains: {found_forbidden[0]}...")

    # Check FileProcessor
    fp_content = result.get("file_processor_content", "")
    if fp_content:
        files_checked += 1
        found_forbidden = [s for s in forbidden_strings["FileProcessor.java"] if s in fp_content]
        if not found_forbidden:
            clean_files += 1
        else:
            feedback_parts.append(f"FileProcessor still contains: {found_forbidden[0]}...")

    if files_checked == 3:
        if clean_files == 3:
            score += 40
            feedback_parts.append("All hardcoded values removed from source")
        elif clean_files > 0:
            partial = int(40 * (clean_files / 3))
            score += partial
            feedback_parts.append(f"{clean_files}/3 files cleaned of hardcoded values")
        else:
            feedback_parts.append("Hardcoded values still present in all files")
    else:
        feedback_parts.append("Could not verify source files (files missing)")

    # === Criterion 3: Build Success (10 pts) ===
    if result.get("build_success", False):
        score += 10
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Build failed")

    # === Criterion 4: Loader Mechanism (10 pts) ===
    if result.get("loader_mechanism_found", False):
        score += 10
        feedback_parts.append("Properties loading mechanism detected")
    else:
        feedback_parts.append("No properties loading code detected")

    passed = score >= 60 and result.get("build_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }