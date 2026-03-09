#!/usr/bin/env python3
"""
Verifier for nsf_grant_narrative task.

Verifies:
1. Document creation and properties (existence, size, timestamp)
2. Content structure (headings, TOC, tables)
3. Page layout (margins, page numbers)
4. Key content (names, budget figures)

Uses copy_from_env to retrieve the ODT file and parses it using standard python zipfile.
"""

import json
import os
import tempfile
import logging
import zipfile
import re
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nsf_grant_narrative(traj, env_info, task_info):
    """Verify the NSF grant narrative document."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = os.path.basename(metadata.get('output_file', 'NSF_SES2415837_ProjectDescription.odt'))
    
    # Setup temporary directory
    temp_dir = tempfile.mkdtemp(prefix="nsf_verify_")
    result_json_path = os.path.join(temp_dir, "task_result.json")
    odt_path = os.path.join(temp_dir, expected_filename)
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve metadata JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
            
        # GATE CHECK: File existence
        if not task_result.get("file_exists", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAIL: Output document was not created."
            }
            
        # 2. Retrieve the ODT file
        try:
            copy_from_env("/home/ga/Documents/" + expected_filename, odt_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"FAIL: Could not copy document for analysis: {e}"}
            
        # CRITERION 1: File Validity (5 pts)
        file_size = task_result.get("file_size_bytes", 0)
        if file_size > 5000: # 5KB min for meaningful content
            score += 5
            feedback_parts.append("Document exists and has content (5/5)")
        elif file_size > 0:
            score += 2
            feedback_parts.append("Document exists but is very small (2/5)")
        else:
            feedback_parts.append("Document is empty (0/5)")
            
        # Parse ODT Content
        content_xml = ""
        styles_xml = ""
        try:
            with zipfile.ZipFile(odt_path, 'r') as zf:
                if 'content.xml' in zf.namelist():
                    content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
                if 'styles.xml' in zf.namelist():
                    styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid ODT file: {e}"}
            
        # CRITERION 2: Table of Contents (15 pts)
        if 'text:table-of-content' in content_xml:
            score += 15
            feedback_parts.append("Table of Contents present (15/15)")
        else:
            feedback_parts.append("Table of Contents missing (0/15)")
            
        # CRITERION 3: Headings Structure (25 pts)
        # Check Heading 1
        h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml)
        h1_count = len(h1_matches)
        min_h1 = metadata.get("min_h1_count", 6)
        
        if h1_count >= min_h1:
            score += 15
            feedback_parts.append(f"Heading 1 structure correct ({h1_count} sections) (15/15)")
        elif h1_count > 0:
            score += 5
            feedback_parts.append(f"Heading 1 structure incomplete ({h1_count}/{min_h1}) (5/15)")
        else:
            feedback_parts.append("No Heading 1 styles used (0/15)")
            
        # Check Heading 2
        h2_matches = re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml)
        h2_count = len(h2_matches)
        min_h2 = metadata.get("min_h2_count", 4)
        
        if h2_count >= min_h2:
            score += 10
            feedback_parts.append(f"Heading 2 structure correct ({h2_count} subsections) (10/10)")
        elif h2_count > 0:
            score += 5
            feedback_parts.append(f"Heading 2 structure incomplete ({h2_count}/{min_h2}) (5/10)")
        else:
            feedback_parts.append("No Heading 2 styles used (0/10)")
            
        # CRITERION 4: Budget Table (10 pts)
        # Look for table elements
        if '<table:table' in content_xml:
            score += 10
            feedback_parts.append("Budget/data table present (10/10)")
        else:
            feedback_parts.append("No tables found (0/10)")
            
        # CRITERION 5: Page Numbers (10 pts)
        # Usually in styles.xml (footer style) or content.xml (if manual)
        if 'text:page-number' in styles_xml or 'text:page-number' in content_xml:
            score += 10
            feedback_parts.append("Page numbers detected (10/10)")
        else:
            feedback_parts.append("Page numbers missing (0/10)")
            
        # CRITERION 6: Margins (10 pts)
        # Check page layout properties in styles.xml
        # Look for fo:margin-* attributes. Values can be "1in", "2.54cm", "0.0254m"
        margin_score = 0
        margin_matches = re.findall(r'fo:margin-[a-z]+="([^"]+)"', styles_xml)
        
        # Helper to convert to cm
        def to_cm(val_str):
            val_str = val_str.lower().strip()
            try:
                if 'in' in val_str:
                    return float(val_str.replace('in', '')) * 2.54
                elif 'cm' in val_str:
                    return float(val_str.replace('cm', ''))
                elif 'mm' in val_str:
                    return float(val_str.replace('mm', '')) / 10.0
                elif 'pt' in val_str:
                    return float(val_str.replace('pt', '')) * 0.0352778
            except:
                pass
            return 0.0

        # We need to find the specific layout used. Usually "pm1" or "Mpm1"
        # Simplification: Check if ANY page layout has approx 1 inch margins
        valid_margins_found = False
        target_cm = 2.54
        tolerance = 0.2
        
        # Brute force check all margin declarations
        good_margins = 0
        total_margins_checked = 0
        
        for m in margin_matches:
            cm = to_cm(m)
            if cm > 0:
                total_margins_checked += 1
                if abs(cm - target_cm) <= tolerance:
                    good_margins += 1
        
        if good_margins >= 4: # Top, Bottom, Left, Right
            score += 10
            feedback_parts.append("Page margins set to ~1 inch (10/10)")
        elif good_margins >= 1:
            score += 5
            feedback_parts.append("Some page margins set to ~1 inch (5/10)")
        else:
            feedback_parts.append("Page margins do not appear to be 1 inch (0/10)")
            
        # CRITERION 7: Content Accuracy (15 pts)
        plain_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
        
        req_terms = metadata.get("required_terms", [])
        terms_found = 0
        for term in req_terms:
            if term.lower() in plain_text:
                terms_found += 1
                
        budget_figs = metadata.get("budget_figures", [])
        figs_found = 0
        for fig in budget_figs:
            clean_fig = fig.replace(',', '')
            if fig in plain_text or clean_fig in plain_text:
                figs_found += 1
                
        if terms_found >= 2 and figs_found >= 1:
            score += 15
            feedback_parts.append("Key content and budget figures present (15/15)")
        elif terms_found >= 1:
            score += 7
            feedback_parts.append("Some key content present, missing details (7/15)")
        else:
            feedback_parts.append("Key content missing (0/15)")
            
        # CRITERION 8: Document Length (10 pts)
        # Count paragraphs (rough estimate)
        para_count = len(re.findall(r'<text:p\b', content_xml))
        if para_count >= 25:
            score += 10
            feedback_parts.append(f"Document length adequate ({para_count} paragraphs) (10/10)")
        else:
            score += 5
            feedback_parts.append(f"Document too short ({para_count} paragraphs) (5/10)")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during analysis: {e}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }