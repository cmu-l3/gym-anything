#!/usr/bin/env python3
"""
Verifier for implement_blob_storage task.

Verification Logic:
1. Validates ODB file modification.
2. Unzips ODB to inspect internal XML and Script files.
3. Checks for schema change (ProfileImage column).
4. Checks for Form creation (ArtistPhotoManager) with Image Control.
5. Checks for Data insertion (Binary data for ArtistId 2).
"""

import json
import os
import tempfile
import zipfile
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blob_storage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Setup temp files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve JSON result
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json.name)
            with open(temp_result_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {str(e)}"}

        # Check basics
        if result.get("image_downloaded", False):
            score += 5
            feedback_parts.append("Image downloaded")
        else:
            feedback_parts.append("Image NOT downloaded")

        if not result.get("odb_modified", False):
            return {"passed": False, "score": score, "feedback": "Database file was not saved/modified."}
        
        # 2. Retrieve ODB file
        try:
            copy_from_env("/tmp/chinook_submitted.odb", temp_odb.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {str(e)}"}

        if os.path.getsize(temp_odb.name) < 1000:
             return {"passed": False, "score": score, "feedback": "Retrieved ODB file is empty or invalid."}

        # 3. Analyze ODB content
        try:
            with zipfile.ZipFile(temp_odb.name, 'r') as zf:
                file_list = zf.namelist()
                
                # --- CHECK SCHEMA & DATA (database/script) ---
                if 'database/script' in file_list:
                    script_content = zf.read('database/script').decode('utf-8', errors='ignore')
                    
                    # Check for Column Addition
                    # Matches: CREATE TABLE "Artist" (... "ProfileImage" LONGVARBINARY ...)
                    # OR: ALTER TABLE "Artist" ADD COLUMN "ProfileImage" LONGVARBINARY
                    # Note: HSQLDB 1.8 type could be LONGVARBINARY, VARBINARY, or IMAGE, or BLOB
                    
                    col_regex = r'(?i)"ProfileImage"\s+(LONGVARBINARY|VARBINARY|IMAGE|BLOB|OBJECT)'
                    if re.search(col_regex, script_content):
                        score += 20
                        feedback_parts.append("Schema modified correctly (ProfileImage column found)")
                    else:
                        feedback_parts.append("Schema verification failed: 'ProfileImage' column not found in database script")

                    # Check for Data Insertion
                    # Looking for INSERT INTO "Artist" ... VALUES(..., 2, ..., '...hex...')
                    # ArtistId 2 is "Accept". 
                    # The value might be a hex string starting with 'ffd8...' (JPEG header) or just not NULL
                    
                    # Find the INSERT statement for ArtistId 2
                    # Pattern: INSERT INTO "Artist" VALUES(2,'Accept',<binary>)
                    # Note: schema might have changed order, but usually appends columns.
                    # Let's look for the row for 'Accept' (ID 2)
                    
                    # Simple check: Does the INSERT for 'Accept' contain a long hex string?
                    # Typical text insert: INSERT INTO "Artist" VALUES(2,'Accept') -> length ~40 chars
                    # With image: length > 1000 chars
                    
                    artist_inserts = [line for line in script_content.splitlines() 
                                    if 'INSERT INTO' in line and '"Artist"' in line and "'Accept'" in line]
                    
                    data_found = False
                    for line in artist_inserts:
                        if len(line) > 500: # Heuristic: line length significantly increases with blob data
                             data_found = True
                             break
                        # Alternative: Check for Hex JPEG header inside the line
                        if "'ffd8" in line.lower() or "'FFD8" in line:
                             data_found = True
                             break
                    
                    if data_found:
                        score += 40
                        feedback_parts.append("Image data found in Artist record")
                    else:
                        feedback_parts.append("Image data MISSING for Artist 'Accept'")
                        
                else:
                    feedback_parts.append("Invalid ODB: database/script missing")

                # --- CHECK FORM (content.xml) ---
                if 'content.xml' in file_list:
                    content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
                    
                    # Parse XML to find form definition
                    # We are looking for form:form name="ArtistPhotoManager"
                    # And inside it, a control bound to ProfileImage
                    
                    # Simple string search first (more robust against namespace issues in simple verification)
                    if 'form:name="ArtistPhotoManager"' in content_xml:
                        score += 20
                        feedback_parts.append("Form 'ArtistPhotoManager' found")
                        
                        # Check for binding
                        # form:data-field="ProfileImage"
                        if 'form:data-field="ProfileImage"' in content_xml:
                             score += 15
                             feedback_parts.append("Image control bound to 'ProfileImage' found")
                        else:
                             feedback_parts.append("Form exists but binding to 'ProfileImage' not found")
                    else:
                        feedback_parts.append("Form 'ArtistPhotoManager' NOT found")
                else:
                    feedback_parts.append("Invalid ODB: content.xml missing")

        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Submitted file is not a valid ODB (ZIP) archive."}

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        # Cleanup
        if os.path.exists(temp_result_json.name): os.unlink(temp_result_json.name)
        if os.path.exists(temp_odb.name): os.unlink(temp_odb.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }