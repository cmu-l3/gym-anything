#!/usr/bin/env python3
"""
Verifier for LibreOffice Base Bulk Update Task.

Verification Logic:
1. Retrieve the `chinook.odb` file from the environment.
2. Since ODB is a ZIP file, extract `database/script`.
3. Parse the HSQLDB script to verify the specific data changes:
   - Employee Title updates
   - Customer Country updates
   - Track UnitPrice updates for specific Genre
"""

import json
import os
import zipfile
import tempfile
import re
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_sql_values(value_str):
    """
    Rudimentary parser for SQL VALUE string: (1, 'Text', 0.99, NULL)
    Returns list of strings/values.
    Note: This is not a full SQL parser but sufficient for HSQLDB script dump format.
    HSQLDB escapes single quotes as ''.
    """
    values = []
    current = []
    in_quote = False
    i = 0
    # Strip outer parens
    s = value_str.strip()
    if s.startswith('(') and s.endswith(')'):
        s = s[1:-1]
    
    while i < len(s):
        char = s[i]
        if char == "'" and (i + 1 >= len(s) or s[i+1] != "'"):
            in_quote = not in_quote
            current.append(char)
        elif char == "'" and i + 1 < len(s) and s[i+1] == "'":
            # Escaped quote
            current.append("''")
            i += 1
        elif char == ',' and not in_quote:
            # Value separator
            val = "".join(current).strip()
            # Remove quotes from strings
            if val.startswith("'") and val.endswith("'"):
                val = val[1:-1].replace("''", "'")
            values.append(val)
            current = []
        else:
            current.append(char)
        i += 1
    
    # Append last value
    val = "".join(current).strip()
    if val.startswith("'") and val.endswith("'"):
        val = val[1:-1].replace("''", "'")
    values.append(val)
    
    return values

def verify_bulk_update_corrections(traj, env_info, task_info):
    """
    Verify the three bulk update operations by inspecting the HSQLDB script.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    passed = False

    # 1. Get result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('odb_exists', False):
        return {"passed": False, "score": 0, "feedback": "Database file not found."}

    if not result.get('odb_modified', False):
        feedback_parts.append("WARNING: Database file timestamp indicates no changes were saved.")
        # We continue checking, but this is a bad sign.

    # 2. Get the ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    temp_script_dir = tempfile.mkdtemp()
    
    try:
        # Copy ODB
        copy_from_env("/home/ga/chinook.odb", temp_odb.name)
        
        # Open ODB (Zip) and extract database/script
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 0, "feedback": "Chinook.odb is not a valid ODF/Zip file."}

        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            try:
                z.extract("database/script", temp_script_dir)
            except KeyError:
                return {"passed": False, "score": 0, "feedback": "Corrupt ODB: missing database/script file."}

        script_path = os.path.join(temp_script_dir, "database/script")
        
        # 3. Analyze Data
        # We scan the INSERT statements to verify the state of the data.
        
        # State tracking
        emp_old_found = 0
        emp_new_found = 0
        cust_old_found = 0
        cust_new_found = 0
        track_correct = 0
        track_incorrect = 0
        track_total_rock = 0

        # Chinook Schema Indexes (0-based) based on standard creation script
        # Employee: ... Title(3 or 4) ...
        # Customer: ... Country(7 or 8) ...
        # Track: ... GenreId, ..., UnitPrice
        
        with open(script_path, 'r', encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line.startswith("INSERT INTO"):
                    continue

                if 'INSERT INTO "Employee"' in line or "INSERT INTO PUBLIC.\"Employee\"" in line:
                    # Value extraction
                    match = re.search(r'VALUES\s*\((.*)\)', line)
                    if match:
                        vals = parse_sql_values(match.group(1))
                        # Title is usually 4th column (index 3): EmployeeId, LastName, FirstName, Title
                        if len(vals) > 3:
                            title = vals[3]
                            if title == "Sales Support Agent":
                                emp_old_found += 1
                            elif title == "Customer Service Representative":
                                emp_new_found += 1

                elif 'INSERT INTO "Customer"' in line or "INSERT INTO PUBLIC.\"Customer\"" in line:
                    match = re.search(r'VALUES\s*\((.*)\)', line)
                    if match:
                        vals = parse_sql_values(match.group(1))
                        # Country is usually 8th column (index 7): Id, Fn, Ln, Co, Addr, City, State, Country
                        if len(vals) > 7:
                            country = vals[7]
                            if country == "USA":
                                cust_old_found += 1
                            elif country == "United States":
                                cust_new_found += 1

                elif 'INSERT INTO "Track"' in line or "INSERT INTO PUBLIC.\"Track\"" in line:
                    match = re.search(r'VALUES\s*\((.*)\)', line)
                    if match:
                        vals = parse_sql_values(match.group(1))
                        # Track: Id(0), Name(1), AlbumId(2), MediaType(3), GenreId(4), Composer(5), Ms(6), Bytes(7), UnitPrice(8)
                        if len(vals) > 8:
                            try:
                                genre_id = int(vals[4])
                                price = float(vals[8])
                                
                                if genre_id == 1: # Rock
                                    track_total_rock += 1
                                    if abs(price - 1.19) < 0.01:
                                        track_correct += 1
                                    elif abs(price - 0.99) < 0.01:
                                        track_incorrect += 1
                            except ValueError:
                                pass

        # 4. Scoring
        
        # Update 1: Employees
        # Expect 0 "Sales Support Agent" (originally 3 or 4)
        # Expect >= 3 "Customer Service Representative"
        if emp_old_found == 0 and emp_new_found >= 3:
            score += 30
            feedback_parts.append("✅ Employee Titles updated correctly.")
        elif emp_old_found > 0:
            feedback_parts.append(f"❌ Found {emp_old_found} employees still with old title.")
        else:
            feedback_parts.append("❌ Employee update verification failed (counts mismatch).")

        # Update 2: Customers
        # Expect 0 "USA" (originally ~13)
        # Expect >= 13 "United States"
        if cust_old_found == 0 and cust_new_found >= 13:
            score += 30
            feedback_parts.append("✅ Customer Countries updated correctly.")
        elif cust_old_found > 0:
            feedback_parts.append(f"❌ Found {cust_old_found} customers still with 'USA'.")
        else:
            feedback_parts.append("❌ Customer update verification failed.")

        # Update 3: Tracks
        # Expect 0 Rock tracks at 0.99
        # Expect many Rock tracks at 1.19
        if track_incorrect == 0 and track_correct > 0:
            score += 30
            feedback_parts.append("✅ Track Prices updated correctly.")
        elif track_incorrect > 0:
            feedback_parts.append(f"❌ Found {track_incorrect} Rock tracks still at 0.99.")
        else:
            feedback_parts.append("❌ Track update verification failed (no updated tracks found).")

        # Database Modified Bonus
        if result.get('odb_modified', False):
            score += 10
            feedback_parts.append("✅ Database file saved successfully.")
        else:
            feedback_parts.append("⚠️ Database file timestamp not updated (did you Save?).")

        # Final check
        if score >= 60:  # Pass if at least 2/3 major updates + save are done
            passed = True

    except Exception as e:
        logger.exception("Verification failed with exception")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)
        if os.path.exists(temp_script_dir):
            shutil.rmtree(temp_script_dir)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }