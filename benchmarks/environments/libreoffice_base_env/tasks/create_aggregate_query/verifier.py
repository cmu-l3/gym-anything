#!/usr/bin/env python3
"""
Verifier for create_aggregate_query task.

Verification Logic:
1. File Integrity: Checks if ODB file exists and was modified.
2. Query Structure (Static Analysis): Extracts 'content.xml' from ODB (ZIP)
   and parses the 'RevenueByGenre' query for required SQL keywords (JOIN, SUM, GROUP BY).
3. Query Correctness (Dynamic Verification): Adapts the extracted SQL to SQLite format
   and runs it against the reference Chinook_Sqlite.sqlite database.
   Verifies that:
     - The query runs without error.
     - "Rock" is the top genre.
     - Revenue matches expected ground truth (within tolerance).
"""

import json
import os
import zipfile
import sqlite3
import re
import tempfile
import logging
import shutil
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aggregate_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_top_genre = metadata.get('expected_top_genre', 'Rock')
    revenue_tolerance = metadata.get('revenue_tolerance', 5.0)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Setup temporary directory for files
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch Task Result JSON
        result_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            with open(result_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check ODB modification
        if not task_result.get("odb_exists"):
            return {"passed": False, "score": 0, "feedback": "Database file (chinook.odb) missing."}
        
        if task_result.get("odb_modified"):
            score += 5
            feedback_parts.append("Database file saved successfully")
        else:
            feedback_parts.append("Warning: Database file timestamp not updated (did you save?)")

        # 2. Fetch ODB File and Ground Truth
        odb_path = os.path.join(temp_dir, "chinook.odb")
        gt_path = os.path.join(temp_dir, "ground_truth.json")
        sqlite_path = os.path.join(temp_dir, "Chinook.sqlite")
        
        try:
            copy_from_env("/home/ga/chinook.odb", odb_path)
        except Exception:
            return {"passed": False, "score": score, "feedback": "Could not copy chinook.odb from container"}

        try:
            copy_from_env("/tmp/ground_truth.json", gt_path)
            with open(gt_path, 'r') as f:
                ground_truth = json.load(f)
        except Exception:
            # Fallback ground truth if file missing
            ground_truth = {"top_revenue": 826.65, "top_genre": "Rock"}

        try:
            # We need the SQLite DB to run the user's query against
            copy_from_env("/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite", sqlite_path)
        except Exception:
            logger.warning("Could not copy SQLite DB - will skip dynamic execution")
            sqlite_path = None

        # 3. Extract and Parse ODB (it's a ZIP file)
        query_name = "RevenueByGenre"
        user_sql = None
        
        try:
            with zipfile.ZipFile(odb_path, 'r') as zf:
                if 'content.xml' in zf.namelist():
                    content_xml = zf.read('content.xml').decode('utf-8')
                    
                    # Namespace handling can be tricky, try naive search first
                    # Look for db:query or similar tags
                    root = ET.fromstring(content_xml)
                    
                    # Finding the query by name attribute
                    # Namespaces usually: xmlns:db="urn:oasis:names:tc:opendocument:xmlns:database:1.0"
                    ns = {'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0'}
                    
                    for query_elem in root.findall(".//db:query", ns):
                        name = query_elem.get(f"{{{ns['db']}}}name")
                        if name == query_name:
                            user_sql = query_elem.get(f"{{{ns['db']}}}command")
                            break
                            
                    # Fallback regex if XML parsing fails due to complex namespaces
                    if not user_sql:
                        pattern = r'db:name="RevenueByGenre"[^>]*db:command="([^"]*)"'
                        match = re.search(pattern, content_xml)
                        if match:
                            user_sql = match.group(1).replace('&quot;', '"').replace('&gt;', '>').replace('&lt;', '<')

        except Exception as e:
            feedback_parts.append(f"Error parsing ODB file: {str(e)}")

        if not user_sql:
            return {
                "passed": False, 
                "score": score, 
                "feedback": " | ".join(feedback_parts) + f" | Query '{query_name}' not found in database."
            }
        
        score += 20
        feedback_parts.append(f"Query '{query_name}' found")
        
        # 4. Static SQL Analysis (30 pts)
        upper_sql = user_sql.upper()
        
        # Check for Joins
        if "JOIN" in upper_sql and "INVOICELINE" in upper_sql and "TRACK" in upper_sql and "GENRE" in upper_sql:
            score += 15
            feedback_parts.append("Joins correct")
        elif "JOIN" in upper_sql:
            score += 5
            feedback_parts.append("Partial joins found")
        else:
            feedback_parts.append("Missing required JOINs")
            
        # Check for Aggregation
        if "SUM" in upper_sql and "UNITPRICE" in upper_sql and "QUANTITY" in upper_sql:
            score += 10
            feedback_parts.append("Aggregation (SUM) found")
        else:
            feedback_parts.append("Missing correct SUM aggregation")
            
        # Check Group By / Order By
        if "GROUP BY" in upper_sql:
            score += 5
        if "ORDER BY" in upper_sql and "DESC" in upper_sql:
            score += 5
            
        # 5. Dynamic Execution Verification (40 pts)
        if sqlite_path:
            try:
                # Adapt HSQLDB SQL to SQLite
                # 1. Remove PUBLIC. schema
                # 2. Remove double quotes around identifiers (SQLite tolerates them, but safer to strip if they cause issues)
                #    Actually, standard SQLite handles "Table"."Col" fine.
                #    We mostly need to strip "PUBLIC."
                adapted_sql = user_sql.replace("PUBLIC.", "")
                
                conn = sqlite3.connect(sqlite_path)
                cursor = conn.cursor()
                cursor.execute(adapted_sql)
                rows = cursor.fetchall()
                conn.close()
                
                if not rows:
                    feedback_parts.append("Query returned no results")
                else:
                    # Check first row
                    top_row_genre = rows[0][0]
                    top_row_revenue = rows[0][1]
                    
                    expected_genre = ground_truth.get("top_genre", "Rock")
                    expected_revenue = ground_truth.get("top_revenue", 826.65)
                    
                    # Verify top genre
                    if str(top_row_genre).lower() == str(expected_genre).lower():
                        score += 20
                        feedback_parts.append(f"Top genre '{top_row_genre}' correct")
                    else:
                        feedback_parts.append(f"Top genre incorrect (expected {expected_genre}, got {top_row_genre})")
                        
                    # Verify revenue
                    try:
                        revenue_val = float(top_row_revenue)
                        if abs(revenue_val - expected_revenue) <= revenue_tolerance:
                            score += 20
                            feedback_parts.append(f"Revenue calculation correct (${revenue_val:.2f})")
                        else:
                            feedback_parts.append(f"Revenue value mismatch (expected ~{expected_revenue}, got {revenue_val})")
                    except ValueError:
                        feedback_parts.append("Revenue column is not a valid number")
                        
            except sqlite3.Error as e:
                # If the SQL is valid HSQLDB but invalid SQLite (syntax differences), we might fail here.
                # But for this specific task (standard JOIN/GROUP/SUM), syntax is very compatible.
                feedback_parts.append(f"SQL Execution failed: {e}")
        else:
            feedback_parts.append("Skipped execution verification (DB missing)")
            # Award partial points if structure looks perfect
            if score >= 55:  # If all static checks passed
                score += 20
                feedback_parts.append("Bonus: Structure looks valid")

    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }