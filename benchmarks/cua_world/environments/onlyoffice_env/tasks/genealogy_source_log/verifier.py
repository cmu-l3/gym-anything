#!/usr/bin/env python3
"""
Verifier for Genealogy Source Log task

This verifier checks that a properly formatted genealogy research source log
was created with appropriate citations, table structure, and formatting.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_has_italics(doc):
    """Check if document contains italic text (for publication titles)"""
    for para in doc.paragraphs:
        for run in para.runs:
            if run.italic and len(run.text.strip()) > 3:
                return True
    
    # Also check in tables
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                for para in cell.paragraphs:
                    for run in para.runs:
                        if run.italic and len(run.text.strip()) > 3:
                            return True
    return False


def analyze_table_structure(doc):
    """
    Analyze table structure for genealogy source log.
    
    Returns: (is_valid, num_columns, num_data_rows, feedback)
    """
    if not doc.tables or len(doc.tables) == 0:
        return False, 0, 0, "No table found in document"
    
    table = doc.tables[0]  # Analyze first table
    num_columns = len(table.columns)
    num_rows = len(table.rows)
    
    if num_columns < 4:
        return False, num_columns, 0, f"Table has {num_columns} columns, need at least 4"
    
    if num_rows < 2:  # At least header + 1 data row
        return False, num_columns, 0, "Table has no data rows"
    
    # Check header row for expected column names
    header_row = table.rows[0]
    header_text = ' '.join([cell.text.strip().lower() for cell in header_row.cells])
    
    expected_terms = ['source', 'citation', 'repository', 'notes']
    found_terms = sum(1 for term in expected_terms if term in header_text)
    
    if found_terms < 3:
        return False, num_columns, num_rows - 1, f"Header row missing expected terms (found {found_terms}/4)"
    
    # Count non-empty data rows
    non_empty_rows = 0
    for i in range(1, num_rows):
        row = table.rows[i]
        row_text = ' '.join([cell.text.strip() for cell in row.cells])
        if len(row_text.strip()) > 20:  # Minimum meaningful content
            non_empty_rows += 1
    
    return True, num_columns, non_empty_rows, "Table structure valid"


def check_citation_quality(doc):
    """
    Check quality of citations in the document.
    
    Returns: (score, feedback_list)
    """
    if not doc.tables or len(doc.tables) == 0:
        return 0, ["No table found for citations"]
    
    table = doc.tables[0]
    feedback = []
    quality_score = 0
    
    # Extract all cell content from data rows
    all_text = ""
    for i in range(1, len(table.rows)):  # Skip header
        row = table.rows[i]
        for cell in row.cells:
            all_text += " " + cell.text.lower()
    
    # Check for genealogical markers
    has_dates = bool(re.search(r'\b\d{4}\b|\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b', all_text))
    has_locations = any(term in all_text for term in [
        'county', 'state', 'illinois', 'texas', 'new york', 'california',
        'city', 'township', 'parish', 'district'
    ])
    has_repositories = any(term in all_text for term in [
        'archive', 'library', 'clerk', 'office', 'nara', 'records',
        'familysearch', 'ancestry', 'findagrave', 'national archives'
    ])
    has_names = bool(re.search(r'\b[A-Z][a-z]+ [A-Z][a-z]+\b', ' '.join([
        cell.text for row in table.rows for cell in row.cells
    ])))
    
    # Source type diversity
    source_types_found = []
    if 'census' in all_text or 'enumeration' in all_text:
        source_types_found.append('census')
    if any(term in all_text for term in ['birth', 'death', 'marriage', 'certificate']):
        source_types_found.append('vital_record')
    if any(term in all_text for term in ['ancestry', 'familysearch', 'database']):
        source_types_found.append('online_database')
    if 'newspaper' in all_text or 'obituary' in all_text:
        source_types_found.append('newspaper')
    
    # Scoring
    if has_dates:
        quality_score += 1
        feedback.append("✅ Citations include dates")
    else:
        feedback.append("❌ Citations missing dates")
    
    if has_locations:
        quality_score += 1
        feedback.append("✅ Citations include locations")
    else:
        feedback.append("❌ Citations missing location information")
    
    if has_repositories:
        quality_score += 1
        feedback.append("✅ Repository information provided")
    else:
        feedback.append("❌ Repository information missing")
    
    if len(source_types_found) >= 2:
        quality_score += 1
        feedback.append(f"✅ Multiple source types present: {', '.join(source_types_found)}")
    else:
        feedback.append("❌ Limited source type diversity")
    
    return quality_score, feedback


def check_research_notes_section(doc):
    """Check if document has a research notes section"""
    full_text = get_document_text(doc).lower()
    
    # Look for section indicators
    has_section = any(phrase in full_text for phrase in [
        'research notes', 'next steps', 'research questions',
        'to do', 'future research', 'follow up'
    ])
    
    if not has_section:
        return False, "No research notes section found"
    
    # Check for substantive content after tables (notes should come after)
    paragraphs_after_table = []
    found_table = False
    
    for element in doc.element.body:
        if element.tag.endswith('tbl'):
            found_table = True
        elif found_table and element.tag.endswith('p'):
            para_text = element.text if hasattr(element, 'text') else ''
            if para_text:
                paragraphs_after_table.append(para_text)
    
    # Alternative: check all paragraphs for content after mention of notes
    notes_content_found = False
    for i, para in enumerate(doc.paragraphs):
        if 'notes' in para.text.lower() or 'research' in para.text.lower():
            # Check if there's meaningful content after this paragraph
            remaining_text = ' '.join([p.text for p in doc.paragraphs[i+1:]])
            if len(remaining_text.strip()) > 20:
                notes_content_found = True
                break
    
    if notes_content_found:
        return True, "Research notes section with content found"
    else:
        return False, "Research notes section exists but lacks content"


def verify_genealogy_log(traj, env_info, task_info):
    """
    Verify that genealogy source log was created correctly.
    
    Scoring breakdown (10 criteria, each worth 10 points):
    1. Document exists and is valid DOCX (10 pts)
    2. Title contains "Genealogy" and "Source Log" (10 pts)
    3. Table exists with at least 4 columns (10 pts)
    4. Table has at least 3 data rows (10 pts)
    5. Table headers are appropriate (10 pts)
    6. Citations include dates (10 pts)
    7. Citations include locations (10 pts)
    8. Repository information provided (10 pts)
    9. Italic formatting used for titles (10 pts)
    10. Research notes section exists (10 pts)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/TextDocuments/genealogy_source_log.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_genealogy_')
    
    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}
        
        score = 0
        feedback_parts = []
        
        # Criterion 1: Document exists and is valid (already passed if we got here)
        score += 10
        feedback_parts.append("✅ Document exists and is valid DOCX")
        
        # Criterion 2: Check title
        full_text = get_document_text(doc)
        first_200_chars = full_text[:200].lower()
        
        has_genealogy = 'genealogy' in first_200_chars or 'genealogical' in first_200_chars
        has_source_log = 'source log' in first_200_chars or 'source list' in first_200_chars
        
        if has_genealogy and has_source_log:
            score += 10
            feedback_parts.append("✅ Title contains 'Genealogy' and 'Source Log'")
        elif has_genealogy or has_source_log:
            score += 5
            feedback_parts.append("⚠️ Title partially correct (missing genealogy or source log term)")
        else:
            feedback_parts.append("❌ Title missing required terms")
        
        # Criterion 3-5: Table structure analysis
        table_valid, num_cols, num_data_rows, table_feedback = analyze_table_structure(doc)
        
        if table_valid and num_cols >= 4:
            score += 10
            feedback_parts.append(f"✅ Table has {num_cols} columns (required: 4+)")
        else:
            feedback_parts.append(f"❌ {table_feedback}")
        
        if table_valid and num_data_rows >= 3:
            score += 10
            feedback_parts.append(f"✅ Table has {num_data_rows} source entries (required: 3+)")
        elif table_valid and num_data_rows >= 1:
            score += 5
            feedback_parts.append(f"⚠️ Table has only {num_data_rows} entries (need 3+)")
        else:
            feedback_parts.append("❌ Table has insufficient data rows")
        
        if table_valid:
            score += 10
            feedback_parts.append("✅ Table headers appropriate")
        
        # Criterion 6-8: Citation quality
        citation_score, citation_feedback = check_citation_quality(doc)
        score += citation_score * 10  # 0-3 criteria * 10 points each
        feedback_parts.extend(citation_feedback)
        
        # Criterion 9: Italic formatting
        has_italics = check_has_italics(doc)
        if has_italics:
            score += 10
            feedback_parts.append("✅ Italic formatting applied (for publication titles)")
        else:
            feedback_parts.append("❌ No italic formatting found (publication titles should be italicized)")
        
        # Criterion 10: Research notes section
        has_notes, notes_feedback = check_research_notes_section(doc)
        if has_notes:
            score += 10
            feedback_parts.append(f"✅ {notes_feedback}")
        else:
            feedback_parts.append(f"❌ {notes_feedback}")
        
        # Cap score at 100
        score = min(score, 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: score={score}, passed={passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
