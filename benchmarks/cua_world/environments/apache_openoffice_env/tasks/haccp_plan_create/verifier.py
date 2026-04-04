#!/usr/bin/env python3
"""
Verifier for haccp_plan_create task.
Verifies that the agent created a properly formatted HACCP plan ODT file.
"""

import json
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_haccp_plan(traj, env_info, task_info):
    """
    Verify the HACCP plan document.
    
    Criteria:
    1. File exists and is > 6KB (substantial content)
    2. Auto-generated TOC exists (text:table-of-content)
    3. >= 7 Heading 1 sections
    4. >= 8 Heading 2 subsections
    5. >= 3 Tables
    6. Page numbers in footer
    7. Content check (Company name, HACCP terms, temperatures)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('output_file', '/home/ga/Documents/Harborview_HACCP_Plan_2024.odt')
    
    # Retrieve result JSON from export script
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # GATE: Check file existence
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result_data.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "File was not modified during task session."}

    file_size = result_data.get('output_size_bytes', 0)
    if file_size < metadata.get('min_file_size_bytes', 6000):
        return {"passed": False, "score": 0, "feedback": f"File too small ({file_size} bytes). Expected substantial document."}

    # Retrieve and parse the ODT file
    try:
        temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
        copy_from_env(expected_filename, temp_odt.name)
        
        with zipfile.ZipFile(temp_odt.name, 'r') as zf:
            content_xml = zf.read('content.xml').decode('utf-8')
            try:
                styles_xml = zf.read('styles.xml').decode('utf-8')
            except KeyError:
                styles_xml = ""
        
        os.unlink(temp_odt.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse ODT file: {e}"}

    # === Scoring ===
    score = 0
    feedback = []
    
    # 1. Table of Contents (15 pts)
    if 'text:table-of-content' in content_xml:
        score += 15
        feedback.append("TOC found (+15)")
    else:
        feedback.append("TOC missing")

    # 2. Heading 1 Sections (20 pts)
    # Regex for <text:h ... text:outline-level="1">
    h1_count = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml))
    min_h1 = metadata.get('min_h1_count', 7)
    if h1_count >= min_h1:
        score += 20
        feedback.append(f"Heading 1 count: {h1_count} (+20)")
    elif h1_count >= 4:
        score += 10
        feedback.append(f"Heading 1 partial: {h1_count} (+10)")
    else:
        feedback.append(f"Heading 1 insufficient: {h1_count} (need {min_h1})")

    # 3. Heading 2 Subsections (15 pts)
    h2_count = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml))
    min_h2 = metadata.get('min_h2_count', 8)
    if h2_count >= min_h2:
        score += 15
        feedback.append(f"Heading 2 count: {h2_count} (+15)")
    elif h2_count >= 4:
        score += 7
        feedback.append(f"Heading 2 partial: {h2_count} (+7)")
    else:
        feedback.append(f"Heading 2 insufficient: {h2_count} (need {min_h2})")

    # 4. Tables (20 pts)
    table_count = len(re.findall(r'<table:table\b', content_xml))
    min_tables = metadata.get('min_table_count', 3)
    if table_count >= min_tables:
        score += 20
        feedback.append(f"Tables count: {table_count} (+20)")
    elif table_count >= 1:
        score += 10
        feedback.append(f"Tables partial: {table_count} (+10)")
    else:
        feedback.append(f"Tables missing (need {min_tables})")

    # 5. Page Numbers (10 pts)
    # Check both content.xml and styles.xml
    if 'text:page-number' in content_xml or 'text:page-number' in styles_xml:
        score += 10
        feedback.append("Page numbers found (+10)")
    else:
        feedback.append("Page numbers missing")

    # 6. Document Length (5 pts)
    para_count = len(re.findall(r'<text:p\b', content_xml))
    min_paras = metadata.get('min_paragraph_count', 30)
    if para_count >= min_paras:
        score += 5
        feedback.append(f"Paragraph count: {para_count} (+5)")
    else:
        feedback.append(f"Document too short: {para_count} paras")

    # 7. Content Check (15 pts)
    # Extract plain text
    plain_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
    
    required_terms = [
        "harborview",
        "haccp",
        "ccp", # critical control point
        "165", # cooking temp
        "135", # hot holding
        "41"   # cold holding
    ]
    
    found_terms = [t for t in required_terms if t in plain_text]
    content_score = int((len(found_terms) / len(required_terms)) * 15)
    score += content_score
    feedback.append(f"Content terms found: {len(found_terms)}/{len(required_terms)} (+{content_score})")

    # Base file existence points (if we got this far)
    if score == 0:
        score = 5 # Small credit for creating a valid file even if empty
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }