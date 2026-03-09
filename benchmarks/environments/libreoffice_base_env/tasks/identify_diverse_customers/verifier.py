#!/usr/bin/env python3
"""
Verifier for Identify Diverse Customers task.
Checks if the agent created a specific SQL query in LibreOffice Base.
"""

import json
import os
import sqlite3
import zipfile
import re
import xml.etree.ElementTree as ET
import logging
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_ground_truth_data(sqlite_path):
    """
    Calculates the expected result using the ground truth SQLite database.
    Returns a list of tuples: (CustomerName, GenreCount)
    """
    if not os.path.exists(sqlite_path):
        logger.error(f"SQLite DB not found at {sqlite_path}")
        return []

    conn = sqlite3.connect(sqlite_path)
    cursor = conn.cursor()
    
    # Logic: Join 5 tables, Count Distinct Genres, Filter >= 5
    query = """
    SELECT 
        c.FirstName || ' ' || c.LastName as CustomerName,
        COUNT(DISTINCT g.GenreId) as GenreCount
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    JOIN InvoiceLine il ON i.InvoiceId = il.InvoiceId
    JOIN Track t ON il.TrackId = t.TrackId
    JOIN Genre g ON t.GenreId = g.GenreId
    GROUP BY c.CustomerId
    HAVING GenreCount >= 5
    ORDER BY GenreCount DESC, CustomerName ASC
    """
    
    try:
        cursor.execute(query)
        results = cursor.fetchall()
        return results
    except Exception as e:
        logger.error(f"Error calculating ground truth: {e}")
        return []
    finally:
        conn.close()

def parse_odb_query(odb_path, query_name):
    """
    Extracts the SQL command for a named query from the ODB file.
    ODB files are ZIPs containing content.xml.
    """
    try:
        with zipfile.ZipFile(odb_path, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
                
                # Namespaces in ODB content.xml
                ns = {
                    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                    'xlink': 'http://www.w3.org/1999/xlink'
                }
                
                # Find the query definition
                # Structure: <db:queries> <db:query db:name="Name" db:command="SQL" ... /> </db:queries>
                for query in root.findall('.//db:query', ns):
                    name = query.get(f"{{{ns['db']}}}name")
                    if name == query_name:
                        command = query.get(f"{{{ns['db']}}}command")
                        return command
        return None
    except Exception as e:
        logger.error(f"Error parsing ODB file: {e}")
        return None

def verify_diverse_customers(traj, env_info, task_info):
    """
    Verifies the task by:
    1. Checking if the 'DiverseCustomerReport' query exists in the ODB file.
    2. Analyzing the SQL structure for required clauses (JOIN, COUNT DISTINCT, HAVING, ||).
    3. (Optional) Comparing the agent's logic against ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup paths
    temp_dir = tempfile.mkdtemp()
    odb_local_path = os.path.join(temp_dir, "submitted.odb")
    json_local_path = os.path.join(temp_dir, "result.json")
    
    # We need the SQLite file for ground truth calculation (it's in the environment image)
    # Since we can't easily copy FROM image TO verifier without it being an artifact,
    # we assume the verifier can run logic based on the ODB. 
    # However, to be robust, we'll rely on structural analysis of the agent's SQL.
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve Result JSON
        copy_from_env("/tmp/task_result.json", json_local_path)
        with open(json_local_path, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get("odb_modified", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Database file was not modified. Did you save your work?"
            }

        # 2. Retrieve ODB File
        copy_from_env("/tmp/submitted_chinook.odb", odb_local_path)
        
        # 3. Extract SQL Query
        target_query_name = task_info['metadata'].get("query_name", "DiverseCustomerReport")
        sql_command = parse_odb_query(odb_local_path, target_query_name)
        
        if not sql_command:
            return {
                "passed": False, 
                "score": 10, 
                "feedback": f"Query '{target_query_name}' not found in database. Did you save it with the exact name?"
            }
            
        score += 20
        feedback_parts.append("Query saved successfully")
        
        # 4. Analyze SQL Structure (Regex)
        # We look for key SQL components required by the task
        sql_upper = sql_command.upper()
        
        # Check for Joins (Customer, Invoice, InvoiceLine, Track, Genre)
        # Simply checking for the table names appearing in the query
        tables_present = 0
        for table in ["CUSTOMER", "INVOICE", "INVOICELINE", "TRACK", "GENRE"]:
            if table in sql_upper:
                tables_present += 1
        
        if tables_present >= 5:
            score += 20
            feedback_parts.append("All 5 required tables referenced")
        else:
            feedback_parts.append(f"Only {tables_present}/5 tables referenced")
            
        # Check for Aggregation: COUNT(DISTINCT ...)
        if "COUNT" in sql_upper and "DISTINCT" in sql_upper:
            score += 20
            feedback_parts.append("Uses COUNT(DISTINCT...)")
        else:
            feedback_parts.append("Missing COUNT or DISTINCT aggregation")

        # Check for Filtering: HAVING ... >= 5
        if "HAVING" in sql_upper and "5" in sql_upper:
            score += 15
            feedback_parts.append("Uses HAVING clause with threshold 5")
        else:
            feedback_parts.append("Missing or incorrect HAVING clause")
            
        # Check for Concatenation: || or CONCAT for the name and "Genres"
        if ("||" in sql_upper or "CONCAT" in sql_upper) and "' '" in sql_upper:
            score += 10
            feedback_parts.append("Name concatenation logic found")
        else:
            feedback_parts.append("Missing name concatenation")

        if "GENRES" in sql_upper:
            score += 5
            feedback_parts.append("Result formatting text found")
            
        # Check for Sorting
        if "ORDER BY" in sql_upper and "DESC" in sql_upper:
            score += 10
            feedback_parts.append("Sorting logic found")
            
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback_parts),
            "details": {"extracted_sql": sql_command}
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)