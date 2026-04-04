#!/usr/bin/env python3
"""
Verifier for edit_attribute_values task.

Checks:
1. DBF file was modified (timestamp check)
2. Specific countries have updated POP_EST values
3. Total population sum is reasonable (sanity check against data corruption)
4. Editing session was closed (no lock)
"""

import json
import os
import sys
import tempfile
import logging
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def install_dbfread():
    """Ensure dbfread is installed."""
    try:
        import dbfread
        return True
    except ImportError:
        logger.info("Installing dbfread...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "dbfread"])
            return True
        except Exception as e:
            logger.error(f"Failed to install dbfread: {e}")
            return False

def verify_edit_attribute_values(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Install dependency
    if not install_dbfread():
        return {"passed": False, "score": 0, "feedback": "Verifier failed to install dependencies"}
    
    import dbfread

    # Get targets from metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {
        "United States of America": 334233854,
        "Brazil": 216422446,
        "Japan": 123294513,
        "Germany": 84482267,
        "Australia": 26638544
    })
    key_field = metadata.get('key_field', 'NAME')
    value_field = metadata.get('value_field', 'POP_EST')
    tolerance = metadata.get('tolerance', 1)

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Modification (Anti-Gaming)
    if result.get('dbf_modified', False):
        score += 5
        feedback_parts.append("File modified timestamp updated")
    else:
        feedback_parts.append("File timestamp NOT updated (Did you save edits?)")
        # If file wasn't modified, values definitely won't match, but we continue to verify content just in case
        # timestamp logic failed (e.g. fast execution)

    # 3. Analyze DBF Content
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    try:
        copy_from_env(result.get('dbf_path', '/tmp/result_countries.dbf'), temp_dbf.name)
        
        table = dbfread.DBF(temp_dbf.name, encoding='utf-8')
        records = list(table)
        
        # Check Total Count (Sanity Check)
        initial_count = 177 # Natural Earth admin 0
        if abs(len(records) - initial_count) > 5:
            feedback_parts.append(f"Row count changed significantly ({len(records)} vs {initial_count})")
        else:
            score += 5 # Preserved data integrity
            
        # Verify Specific Targets
        matches = 0
        total_targets = len(targets)
        
        # Build lookup for efficiency
        # Handle potential encoding issues or field name case sensitivity
        # dbfread is usually case insensitive for field access but let's be safe
        
        # Normalize field names in records
        normalized_records = []
        for r in records:
            norm_r = {k.upper(): v for k, v in r.items()}
            normalized_records.append(norm_r)
            
        key_field_upper = key_field.upper()
        value_field_upper = value_field.upper()

        updated_countries = []
        
        for target_name, target_val in targets.items():
            # Find record
            found_rec = next((r for r in normalized_records if r.get(key_field_upper) == target_name), None)
            
            if found_rec:
                actual_val = found_rec.get(value_field_upper, -1)
                try:
                    actual_val = float(actual_val)
                    target_val = float(target_val)
                    
                    if abs(actual_val - target_val) <= tolerance:
                        matches += 1
                        updated_countries.append(target_name)
                        score += 15 # 15 points per country (5 * 15 = 75)
                    else:
                        feedback_parts.append(f"{target_name}: Expected {target_val}, got {actual_val}")
                except (ValueError, TypeError):
                    feedback_parts.append(f"{target_name}: Invalid value format")
            else:
                feedback_parts.append(f"{target_name}: Country not found in table")

        if matches == total_targets:
            feedback_parts.append("All target populations updated correctly")
        elif matches > 0:
            feedback_parts.append(f"Updated {matches}/{total_targets} countries correctly")

    except Exception as e:
        feedback_parts.append(f"Failed to analyze DBF file: {str(e)}")
    finally:
        if os.path.exists(temp_dbf.name):
            os.unlink(temp_dbf.name)

    # 4. Check Editing Session Status
    if not result.get('is_locked', False):
        score += 15
        feedback_parts.append("Editing session closed properly")
    else:
        feedback_parts.append("Editing session appears active (lock file exists)")

    # Final Score Calculation
    # Max Score: 5 (mod) + 5 (integrity) + 75 (values) + 15 (closed) = 100
    
    passed = score >= 60 and matches >= 3 # Pass if at least 3 countries correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }