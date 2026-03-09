#!/usr/bin/env python3
"""
Verifier for manage_user_permissions task.

Verification Strategy:
1. Verify the ODB file was saved (modified timestamp).
2. Parse the underlying HSQLDB script file (extracted from ODB zip).
3. Check for specific SQL statements:
   - CREATE USER for REFDESK, CATALOGER, LIBADMIN
   - GRANT statements for correct tables and permissions
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_user_permissions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not result.get("odb_exists"):
        return {"passed": False, "score": 0, "feedback": "Database file not found."}
    
    if not result.get("odb_modified"):
        return {"passed": False, "score": 0, "feedback": "Database file was not saved. You must save the file (File > Save) to persist changes."}

    if not result.get("script_extracted"):
        return {"passed": False, "score": 0, "feedback": "Could not verify database content (failed to extract HSQLDB script)."}

    # Load the extracted database script
    db_script_content = ""
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/database_script.txt", temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            db_script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read database script: {e}"}
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # --- Verification Logic ---
    
    score = 0
    feedback = []
    
    # Tables lists
    tables_content = ["Artist", "Album", "Track", "Genre", "MediaType", "Playlist", "PlaylistTrack"]
    tables_admin = ["Customer", "Employee", "Invoice", "InvoiceLine"]
    all_tables = tables_content + tables_admin

    # Helper regex builder
    # HSQLDB 1.8 script format examples:
    # CREATE USER REFDESK PASSWORD "refdesk2024"
    # GRANT SELECT ON "Artist" TO REFDESK
    # GRANT SELECT,INSERT,UPDATE,DELETE ON "Artist" TO CATALOGER
    
    def check_user(username):
        # Case insensitive search for user creation
        pattern = re.compile(f'CREATE USER {username} PASSWORD', re.IGNORECASE)
        return bool(pattern.search(db_script_content))

    def check_grant(username, permission, table):
        # Matches: GRANT ... SELECT ... ON ... "Table" ... TO USER
        # Note: HSQLDB usually quotes table names in script if they were quoted in creation or are mixed case
        # We look for the table name with or without quotes
        # Pattern: GRANT <perms> ON [PUBLIC.]"<Table>" TO <User>
        
        # Construct regex for permissions: e.g. "SELECT" or "SELECT,INSERT,..."
        # We need to ensure the specific permission is present in the list
        
        # Simplified check: Find the line granting ANY perms on TABLE to USER, then check perms
        table_pattern = f'(?:PUBLIC\\.)?"?{table}"?'
        line_pattern = re.compile(f'GRANT (.*?) ON {table_pattern} TO {username}', re.IGNORECASE)
        
        match = line_pattern.search(db_script_content)
        if match:
            granted_perms = match.group(1).upper()
            required_perm = permission.upper()
            return required_perm in granted_perms
        return False

    def check_dba(username):
        pattern = re.compile(f'GRANT DBA TO {username}', re.IGNORECASE)
        return bool(pattern.search(db_script_content))

    # 1. Verify Users (30 pts)
    if check_user("REFDESK"):
        score += 10
        feedback.append("User REFDESK created.")
    else:
        feedback.append("User REFDESK missing.")

    if check_user("CATALOGER"):
        score += 10
        feedback.append("User CATALOGER created.")
    else:
        feedback.append("User CATALOGER missing.")

    if check_user("LIBADMIN"):
        score += 10
        feedback.append("User LIBADMIN created.")
    else:
        feedback.append("User LIBADMIN missing.")

    # 2. Verify REFDESK Permissions (20 pts)
    # Needs SELECT on ALL tables
    refdesk_ok = True
    for t in all_tables:
        if not check_grant("REFDESK", "SELECT", t):
            refdesk_ok = False
            break
    
    if refdesk_ok:
        score += 20
        feedback.append("REFDESK has correct read permissions.")
    else:
        feedback.append("REFDESK missing SELECT permissions on some tables.")

    # 3. Verify CATALOGER Permissions (30 pts)
    # Content tables: SELECT, INSERT, UPDATE, DELETE (20 pts)
    cat_content_ok = True
    for t in tables_content:
        for p in ["SELECT", "INSERT", "UPDATE", "DELETE"]:
            if not check_grant("CATALOGER", p, t):
                cat_content_ok = False
                break
    
    if cat_content_ok:
        score += 20
        feedback.append("CATALOGER has correct content management permissions.")
    else:
        feedback.append("CATALOGER missing full permissions on content tables.")

    # Admin tables: SELECT only (10 pts)
    cat_admin_ok = True
    cat_admin_strict = True
    for t in tables_admin:
        if not check_grant("CATALOGER", "SELECT", t):
            cat_admin_ok = False
        # Check for Forbidden permissions
        for p in ["INSERT", "UPDATE", "DELETE"]:
            if check_grant("CATALOGER", p, t):
                cat_admin_strict = False
    
    if cat_admin_ok:
        if cat_admin_strict:
            score += 10
            feedback.append("CATALOGER has correct read-only access to admin tables.")
        else:
            score += 5
            feedback.append("CATALOGER has read access to admin tables but WRONGLY has write access too.")
    else:
        feedback.append("CATALOGER missing SELECT permissions on admin tables.")

    # 4. Verify LIBADMIN Permissions (10 pts)
    if check_dba("LIBADMIN"):
        score += 10
        feedback.append("LIBADMIN granted DBA role.")
    else:
        feedback.append("LIBADMIN missing DBA role.")
    
    # 5. Save Check (10 pts)
    # If we got this far, the file was modified and script extracted, so give points for saving
    score += 10
    feedback.append("Database saved successfully.")

    passed = score >= 60 and check_user("REFDESK") and check_user("CATALOGER") and check_user("LIBADMIN")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }