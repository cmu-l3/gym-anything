#!/usr/bin/env python3
"""
Verifier for construct_sales_dashboard task.

Verification Strategy:
1. File Analysis: Unzip the ODB file.
2. Query Verification: Parse content.xml to check if 'VIP_Customers' and 'Top_Artists' exist and contain correct SQL logic (SUM, COUNT, GROUP BY, Thresholds).
3. Form Verification: Check content.xml for 'ManagerDashboard' form registration.
4. Form Content: Attempt to parse the form's internal XML to verify it contains TableControls.
5. VLM: Visual confirmation of the dashboard state (optional/secondary).
"""

import json
import os
import zipfile
import re
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces for ODB XML parsing
NS = {
    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
}

def verify_construct_sales_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Weights
    SCORE_QUERY_1 = 30
    SCORE_QUERY_2 = 30
    SCORE_FORM_EXISTS = 10
    SCORE_FORM_CONTENT = 30
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
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

    if not result.get('odb_exists') or not result.get('odb_modified'):
        return {"passed": False, "score": 0, "feedback": "Database file not modified or missing. Did you save?"}

    # 2. Get ODB File
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    try:
        copy_from_env("/tmp/verification_chinook.odb", temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 0, "feedback": "Database file is corrupted or not a valid ODB archive."}

        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            # --- Verify Queries (content.xml) ---
            try:
                content_xml = z.read('content.xml')
                root = ET.fromstring(content_xml)
                
                # Find Queries
                queries = root.findall('.//db:query', NS)
                query_map = {q.get(f'{{{NS["db"]}}}name'): q.get(f'{{{NS["db"]}}}command') for q in queries}
                
                # Check VIP_Customers
                vip_sql = query_map.get('VIP_Customers', '')
                if vip_sql:
                    feedback_parts.append("Query 'VIP_Customers' found.")
                    # Check Logic: SUM, GROUP BY, > 40
                    # SQL in ODB is often stored cleaned, but let's check keywords case-insensitive
                    sql_upper = vip_sql.upper()
                    criteria_met = 0
                    if 'SUM(' in sql_upper: criteria_met += 1
                    if 'GROUP BY' in sql_upper: criteria_met += 1
                    if '40' in sql_upper: criteria_met += 1
                    
                    if criteria_met == 3:
                        score += SCORE_QUERY_1
                        feedback_parts.append("VIP_Customers logic correct.")
                    else:
                        score += 15 # Partial credit for existence
                        feedback_parts.append(f"VIP_Customers missing logic (SUM/GROUP BY/>40). Found: {vip_sql[:50]}...")
                else:
                    feedback_parts.append("Query 'VIP_Customers' NOT found.")

                # Check Top_Artists
                artist_sql = query_map.get('Top_Artists', '')
                if artist_sql:
                    feedback_parts.append("Query 'Top_Artists' found.")
                    # Check Logic: COUNT, GROUP BY, > 50
                    sql_upper = artist_sql.upper()
                    criteria_met = 0
                    if 'COUNT(' in sql_upper: criteria_met += 1
                    if 'GROUP BY' in sql_upper: criteria_met += 1
                    if '50' in sql_upper: criteria_met += 1
                    
                    if criteria_met == 3:
                        score += SCORE_QUERY_2
                        feedback_parts.append("Top_Artists logic correct.")
                    else:
                        score += 15 # Partial credit
                        feedback_parts.append(f"Top_Artists missing logic (COUNT/GROUP BY/>50). Found: {artist_sql[:50]}...")
                else:
                    feedback_parts.append("Query 'Top_Artists' NOT found.")

                # --- Verify Form Existence (content.xml) ---
                # Forms are listed under <db:forms><db:component .../></db:forms>
                # Note: They might be nested in folders, but typically simple save puts them at root of forms
                form_comps = root.findall('.//db:component', NS)
                target_form = None
                for comp in form_comps:
                    name = comp.get(f'{{{NS["db"]}}}name')
                    if name == 'ManagerDashboard':
                        target_form = comp
                        break
                
                if target_form is not None:
                    score += SCORE_FORM_EXISTS
                    feedback_parts.append("Form 'ManagerDashboard' found.")
                    
                    # --- Verify Form Content (Internal Form XML) ---
                    # Get the internal path, e.g., "forms/Obj11"
                    href = target_form.get(f'{{{NS["xlink"]}}}href')
                    if href:
                        # The content of the form is in [href]/content.xml inside the zip
                        form_content_path = f"{href}/content.xml"
                        try:
                            form_xml = z.read(form_content_path)
                            f_root = ET.fromstring(form_xml)
                            
                            # Look for Table Controls (Grid)
                            # Tag: <form:table-control>
                            table_controls = f_root.findall('.//form:table-control', NS)
                            count = len(table_controls)
                            
                            if count >= 2:
                                score += SCORE_FORM_CONTENT
                                feedback_parts.append(f"Form contains {count} table controls.")
                            elif count == 1:
                                score += SCORE_FORM_CONTENT // 2
                                feedback_parts.append("Form contains only 1 table control (expected 2).")
                            else:
                                feedback_parts.append("Form exists but no table controls found.")
                                
                        except KeyError:
                            feedback_parts.append(f"Could not read form content at {form_content_path}.")
                else:
                    feedback_parts.append("Form 'ManagerDashboard' NOT found.")

            except Exception as e:
                feedback_parts.append(f"Error parsing ODB XML: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error verifying ODB file: {e}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }