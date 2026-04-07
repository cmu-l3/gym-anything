#!/usr/bin/env python3
"""
Verifier for compile_grant_proposal_assembly task.

VERIFICATION STRATEGY:
1. Document Integrity (40 pts):
   - Opens the saved .docx file.
   - Verifies text from all 3 source files is present.
   - Verifies the order is correct (Aims < Strategy < Literature).
   
2. Formatting & Layout (30 pts):
   - Page Breaks: Checks XML or simple heuristic (text length/structure) to ensure sections aren't merged on one page. 
     We verify that "page break" control characters or separate page structures exist.
   - Headers: Parses XML to find the specific header text "PI: Dr. J. Doe".
   
3. Page Numbers (20 pts):
   - Parses XML footer to find page numbering fields.
   
4. File Properties (10 pts):
   - File exists and was created during the task.

Total: 100 points. Pass threshold: 70 points (Must have content + breaks + header).
"""

import json
import logging
import os
import re
import tempfile
import zipfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected strings from the generated source files
MARKER_AIMS = "Aim 1: Determine the mechanism"
MARKER_STRATEGY = "Significance and Innovation"
MARKER_LITERATURE = "Smith, J. et al. (2023)"
EXPECTED_HEADER = "PI: Dr. J. Doe - R01 Application"


def verify_compile_grant_proposal_assembly(traj, env_info, task_info):
    """
    Verifies that the agent assembled the grant proposal correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Result paths in container
    result_json_path = "C:\\Users\\Docker\\compile_grant_proposal_assembly_result.json"
    doc_path = "C:\\Users\\Docker\\Documents\\Final_Grant_Package.docx"

    # Temporary directory for analysis
    temp_dir = tempfile.mkdtemp()
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Check Metadata from export script
        local_json = os.path.join(temp_dir, "result.json")
        try:
            copy_from_env(result_json_path, local_json)
            with open(local_json, 'r') as f:
                metadata = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}

        if not metadata.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Final_Grant_Package.docx not found."}
        
        if not metadata.get("final_is_new"):
            # If file existed before (unlikely given setup) or wasn't modified
            feedback_parts.append("Warning: File timestamp suggests it wasn't modified during task.")
        else:
            score += 10
            feedback_parts.append("File created/modified during task (10/10).")

        # 2. Analyze DOCX Content
        local_docx = os.path.join(temp_dir, "Final_Grant_Package.docx")
        try:
            copy_from_env(doc_path, local_docx)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Could not copy document for analysis: {e}"}

        # Verify it's a valid zip/docx
        if not zipfile.is_zipfile(local_docx):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid DOCX/Zip file."}

        # Extract XML content for deep verification
        with zipfile.ZipFile(local_docx, 'r') as zf:
            # Read Main Document Text
            try:
                doc_xml = zf.read('word/document.xml').decode('utf-8')
            except KeyError:
                return {"passed": False, "score": score, "feedback": "Invalid DOCX: missing word/document.xml"}
            
            # Read Headers
            header_content = ""
            for name in zf.namelist():
                if name.startswith('word/header'):
                    header_content += zf.read(name).decode('utf-8')
            
            # Read Footers
            footer_content = ""
            for name in zf.namelist():
                if name.startswith('word/footer'):
                    footer_content += zf.read(name).decode('utf-8')

        # --- Criterion A: Content Presence & Order (40 pts) ---
        # Normalize XML tags out for text search (rough approximation)
        # Note: In docx XML, text is in <w:t> elements.
        
        # Simple string existence check in the raw XML is usually sufficient for these markers
        pos_aims = doc_xml.find(MARKER_AIMS)
        pos_strat = doc_xml.find(MARKER_STRATEGY)
        pos_lit = doc_xml.find(MARKER_LITERATURE)

        if pos_aims != -1 and pos_strat != -1 and pos_lit != -1:
            score += 20
            feedback_parts.append("All three document sections found (20/20).")
            
            # Check Order
            if pos_aims < pos_strat < pos_lit:
                score += 20
                feedback_parts.append("Sections are in correct order (20/20).")
            else:
                feedback_parts.append("Sections are present but in WRONG order (0/20).")
        else:
            missing = []
            if pos_aims == -1: missing.append("Specific Aims")
            if pos_strat == -1: missing.append("Research Strategy")
            if pos_lit == -1: missing.append("Literature Cited")
            feedback_parts.append(f"Missing content from: {', '.join(missing)} (0/40).")

        # --- Criterion B: Page Breaks (20 pts) ---
        # Look for explicit page breaks <w:br w:type="page"/> or section breaks <w:sectPr>
        # We need breaks BETWEEN the sections.
        
        # We can check if there are at least 2 breaks in the document
        # <w:br w:type="page"/> is standard manual break.
        # <w:sectPr> implies section break (Next Page is common for merging files).
        
        break_count = doc_xml.count('<w:br w:type="page"/>') + doc_xml.count('<w:sectPr>')
        # Note: A standard doc has 1 sectPr at the end. We expect more if files were merged with breaks.
        
        if break_count >= 3: # 1 end + 2 separators
            score += 20
            feedback_parts.append("Page/Section breaks detected (20/20).")
        else:
            # Fallback: check text logic. The text should be separated by formatting.
            feedback_parts.append(f"Warning: Only found {break_count} page/section layout markers. Expected separators between 3 files.")
            if break_count >= 2:
                score += 10 # Partial credit
                feedback_parts.append("Partial credit for breaks.")

        # --- Criterion C: Header (15 pts) ---
        if EXPECTED_HEADER in header_content:
            score += 15
            feedback_parts.append("Header text found correctly (15/15).")
        else:
            feedback_parts.append(f"Header text '{EXPECTED_HEADER}' NOT found in header XML (0/15).")

        # --- Criterion D: Page Numbers (15 pts) ---
        # Look for Page field: <w:fldSimple w:instr=" PAGE "> or complex field
        # Regex for 'PAGE' instruction inside instrText or fldSimple
        page_num_regex = re.compile(r'PAGE', re.IGNORECASE)
        
        if page_num_regex.search(footer_content):
            score += 15
            feedback_parts.append("Page numbering field found in footer (15/15).")
        else:
            feedback_parts.append("Page numbering field NOT found in footer (0/15).")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }