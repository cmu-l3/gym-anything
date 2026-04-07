#!/usr/bin/env python3
"""Verifier for create_dynamic_invoice_table task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dynamic_table(traj, env_info, task_info):
    """
    Verify the Invoice Dashboard tiddler.
    
    Checks:
    1. Tiddler exists with proper tags
    2. Dynamic generation (anti-hardcoding: raw text lacks actual data)
    3. HTML structure (Rendered output has table and headers)
    4. Data Completeness (Exactly 15 rows)
    5. Field Transclusion ($ sign present, correct mapping)
    6. Sort Ordering (Due dates in descending order)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tags = metadata.get('expected_tags', ['Dashboard', 'Finance'])
    required_headers = metadata.get('required_headers', ['Invoice ID', 'Client', 'Due Date', 'Amount', 'Status'])
    hardcoded_checks = metadata.get('hardcoded_check_strings', ['Altus Health Systems', 'NovaTech Manufacturing'])

    # Copy result from container
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

    # CRITERION 1: Tiddler Setup (10 pts)
    if not result.get('tiddler_found'):
        return {"passed": False, "score": 0, "feedback": "FAIL: 'Invoice Dashboard' tiddler not found"}
    
    score += 5
    tags = result.get('tiddler_tags', '')
    tags_found = sum(1 for tag in expected_tags if tag.lower() in tags.lower())
    if tags_found == len(expected_tags):
        score += 5
        feedback_parts.append(f"Tags OK ({tags_found}/{len(expected_tags)})")
    else:
        feedback_parts.append(f"Tags missing ({tags_found}/{len(expected_tags)} found)")

    # Anti-gaming: Ensure file was created during task session
    if not result.get('file_modified_during_task'):
        feedback_parts.append("WARNING: File not created/modified during task session")

    # CRITERION 2: Dynamic Generation / Anti-Hardcoding (20 pts)
    raw_text = result.get('raw_text', '')
    hardcoded = False
    for s in hardcoded_checks:
        if s.lower() in raw_text.lower():
            hardcoded = True
            break
            
    if hardcoded:
        feedback_parts.append("FAIL: Invoice data appears to be hardcoded in the text instead of dynamically generated")
        # Do not give points for dynamic generation
    else:
        score += 20
        feedback_parts.append("Dynamic generation confirmed (no hardcoded data)")

    # Extract rendered HTML for parsing
    html = result.get('rendered_html', '')
    
    # Simple regex parsing for table rows
    tr_pattern = re.compile(r'<tr.*?>(.*?)</tr>', re.DOTALL | re.IGNORECASE)
    td_pattern = re.compile(r'<t[dh].*?>(.*?)</t[dh]>', re.DOTALL | re.IGNORECASE)
    
    rows = tr_pattern.findall(html)

    # CRITERION 3: HTML Structure (15 pts)
    if not rows:
        feedback_parts.append("FAIL: No <tr> elements found in output")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    header_row = rows[0]
    cells = td_pattern.findall(header_row)
    header_text = ' '.join([re.sub(r'<[^>]+>', '', c).strip() for c in cells])
    
    headers_found = sum(1 for h in required_headers if h.lower() in header_text.lower())
    if headers_found >= len(required_headers):
        score += 15
        feedback_parts.append("Table headers perfect")
    elif headers_found >= 3:
        score += 10
        feedback_parts.append(f"Table headers mostly match ({headers_found}/{len(required_headers)})")
    else:
        feedback_parts.append("Table headers missing or incorrect")

    data_rows = rows[1:] if headers_found > 0 else rows

    # CRITERION 4: Data Completeness (15 pts)
    num_data_rows = len(data_rows)
    if num_data_rows == 15:
        score += 15
        feedback_parts.append("Correct row count (15 invoices)")
    elif num_data_rows > 0:
        score += int(15 * (min(num_data_rows, 15) / 15))
        feedback_parts.append(f"Row count mismatch: found {num_data_rows}, expected 15")
    else:
        feedback_parts.append("FAIL: No data rows found")

    # CRITERION 5 & 6: Field Transclusion (20 pts) & Sort Ordering (20 pts)
    dates = []
    dollar_signs_found = 0
    clients_found = 0
    
    for row in data_rows:
        cells = td_pattern.findall(row)
        if not cells:
            continue
            
        row_text = ' '.join(cells)
        
        # Check for dollar sign prepend
        if '$' in row_text:
            dollar_signs_found += 1
            
        # Check for client names appearing in HTML (proves transclusion worked if raw_text check passed)
        if any(c.lower() in row_text.lower() for c in hardcoded_checks[:2]):
            clients_found += 1
            
        # Extract dates to check ordering. 
        # The agent was asked to put Due Date in Column 3, but let's just find any valid date string to be robust.
        date_match = re.search(r'\d{4}-\d{2}-\d{2}', row_text)
        if date_match:
            dates.append(date_match.group(0))

    # Score Transclusion
    if dollar_signs_found > 0 and clients_found > 0:
        score += 20
        feedback_parts.append("Field transclusion successful (data & formatting present)")
    elif clients_found > 0:
        score += 10
        feedback_parts.append("Field transclusion successful, but missing '$' formatting")

    # Score Sorting
    if len(dates) >= 2:
        is_descending = all(dates[i] >= dates[i+1] for i in range(len(dates)-1))
        if is_descending:
            score += 20
            feedback_parts.append("Sort order is correct (descending)")
        else:
            feedback_parts.append("FAIL: Sort order is incorrect")
    else:
        feedback_parts.append("Could not verify sort order (dates not found)")

    # Final tally
    passed = score >= 75 and hardcoded is False and num_data_rows > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }