#!/usr/bin/env python3
"""
Verifier for add_content_provider task.

Scoring Breakdown (100 points total):
1. NoteContract.kt (20 pts)
   - Exists (5)
   - Authority constant correct (5)
   - Content URI definition (5)
   - Column constants present (5)

2. NoteContentProvider.kt (45 pts)
   - Exists (5)
   - Extends ContentProvider (5)
   - UriMatcher implemented (5)
   - Implements required methods (15)
     (onCreate, query, insert, update, delete, getType)
   - References Room Database/DAO (15)

3. AndroidManifest.xml (20 pts)
   - Provider tag present (5)
   - Correct authority attribute (5)
   - Exported=true (5)
   - Correct name attribute (5)

4. Build Status (15 pts)
   - Gradle build success (15)
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_content_provider(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    contract_content = result.get('contract_content', '')
    provider_content = result.get('provider_content', '')
    manifest_content = result.get('manifest_content', '')
    build_success = result.get('build_success', False)
    
    score = 0
    feedback = []

    # --- 1. Verify NoteContract.kt (20 pts) ---
    if result.get('contract_exists', False):
        score += 5
        feedback.append("NoteContract.kt exists (+5)")
        
        # Check Authority
        if 'com.example.notesapp.provider' in contract_content:
            score += 5
            feedback.append("Authority constant correct (+5)")
        else:
            feedback.append("Authority constant missing or incorrect")

        # Check Content URI
        if 'Uri.parse' in contract_content or 'content://' in contract_content:
            score += 5
            feedback.append("Content URI defined (+5)")
        
        # Check Columns
        cols = ['COLUMN_ID', 'COLUMN_TITLE', 'COLUMN_CONTENT', 'COLUMN_TIMESTAMP']
        found_cols = [c for c in cols if c in contract_content]
        if len(found_cols) == 4:
            score += 5
            feedback.append("All column constants present (+5)")
        else:
            feedback.append(f"Missing column constants: {set(cols) - set(found_cols)}")
    else:
        feedback.append("NoteContract.kt missing")

    # --- 2. Verify NoteContentProvider.kt (45 pts) ---
    if result.get('provider_exists', False):
        score += 5
        feedback.append("NoteContentProvider.kt exists (+5)")
        
        # Inheritance
        if ': ContentProvider' in provider_content or 'extends ContentProvider' in provider_content:
            score += 5
            feedback.append("Extends ContentProvider (+5)")
        
        # UriMatcher
        if 'UriMatcher' in provider_content:
            score += 5
            feedback.append("UriMatcher implemented (+5)")
        
        # Methods
        methods = ['onCreate', 'query', 'insert', 'update', 'delete', 'getType']
        found_methods = [m for m in methods if f"fun {m}" in provider_content]
        if len(found_methods) == 6:
            score += 15
            feedback.append("All required methods implemented (+15)")
        else:
            score += int(15 * (len(found_methods) / 6))
            feedback.append(f"Implemented {len(found_methods)}/6 required methods")
            
        # Database Integration
        if 'NoteDatabase' in provider_content or 'NoteDao' in provider_content:
            score += 15
            feedback.append("Connected to Room Database (+15)")
        else:
            feedback.append("No reference to NoteDatabase or NoteDao found")
    else:
        feedback.append("NoteContentProvider.kt missing")

    # --- 3. Verify AndroidManifest.xml (20 pts) ---
    # We use regex to parse the provider tag
    provider_regex = re.compile(r'<provider[^>]*>', re.DOTALL)
    provider_tags = provider_regex.findall(manifest_content)
    
    provider_valid = False
    for tag in provider_tags:
        if 'com.example.notesapp.provider' in tag:
            score += 5 # Authority match
            provider_valid = True
            
            if 'android:name' in tag and 'NoteContentProvider' in tag:
                score += 5
                feedback.append("Manifest: Provider name correct (+5)")
            
            if 'android:exported="true"' in tag:
                score += 5
                feedback.append("Manifest: Provider exported (+5)")
            else:
                feedback.append("Manifest: Provider NOT exported")
                
            break
    
    if provider_valid:
        score += 5 # Tag present
        feedback.append("Manifest: Provider tag present (+5)")
    else:
        feedback.append("Manifest: Provider tag missing or incorrect authority")

    # --- 4. Verify Build (15 pts) ---
    if build_success:
        score += 15
        feedback.append("Build Successful (+15)")
    else:
        feedback.append("Build Failed")

    return {
        "passed": score >= 60 and build_success,
        "score": score,
        "feedback": "\n".join(feedback)
    }