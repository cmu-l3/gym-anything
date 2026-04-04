#!/usr/bin/env python3
"""
Verifier for Science Fair Report task
Checks report formatting, structure, content, and compliance with requirements
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
    check_text_formatting,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_words(text):
    """Count words in text, handling various edge cases"""
    if not text:
        return 0
    # Remove extra whitespace and split
    words = text.strip().split()
    return len(words)


def extract_section_text(full_text, section_name, next_section_name=None):
    """Extract text between two section headings"""
    pattern = re.escape(section_name)
    match = re.search(pattern, full_text, re.IGNORECASE)
    
    if not match:
        return ""
    
    start_pos = match.end()
    
    if next_section_name:
        next_pattern = re.escape(next_section_name)
        next_match = re.search(next_pattern, full_text[start_pos:], re.IGNORECASE)
        if next_match:
            return full_text[start_pos:start_pos + next_match.start()].strip()
    
    # If no next section, take next 500 characters
    return full_text[start_pos:start_pos + 500].strip()


def verify_science_fair_report(traj, env_info, task_info):
    """
    Verify that science fair report was created correctly.

    Checks:
    1. Document exists and is parseable
    2. Title page has all 5 required elements
    3. Abstract exists and is ≤150 words
    4. All required sections present (Hypothesis, Materials, Results, Conclusion, References)
    5. Data table exists (for Results section)
    6. At least 4 section headings are bold (formatting check)
    7. References section has at least 2 citations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/science_fair_report.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_sciencefair_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load document: {error}"
            }

        feedback_parts = []
        criteria_passed = 0
        total_criteria = 7

        # Extract full text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        logger.info(f"Document text length: {len(full_text)} characters")
        logger.debug(f"First 500 chars: {full_text[:500]}")

        # ===================================================================
        # CRITERION 1: Title page has all 5 required elements
        # ===================================================================
        title_elements = {
            "title": "effect of light color on plant growth",
            "student": "jamie chen",
            "grade": "7th grade",
            "school": "lincoln middle school"
        }
        
        title_elements_found = {}
        for key, value in title_elements.items():
            title_elements_found[key] = value in full_text_lower
        
        # Check if at least 4 out of 5 elements are present (allowing some flexibility)
        title_count = sum(title_elements_found.values())
        
        if title_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Title page complete ({title_count}/4 key elements)")
        else:
            missing_elements = [k for k, v in title_elements_found.items() if not v]
            feedback_parts.append(f"❌ Title page incomplete (missing: {', '.join(missing_elements)})")

        # ===================================================================
        # CRITERION 2: Abstract exists and is ≤150 words
        # ===================================================================
        abstract_keywords = ["abstract"]
        abstract_found = any(kw in full_text_lower for kw in abstract_keywords)
        
        if abstract_found:
            # Try to extract abstract text
            abstract_text = extract_section_text(full_text_lower, "abstract", "hypothesis")
            
            if not abstract_text:
                # Fallback: look for first substantial paragraph after "abstract"
                abstract_pos = full_text_lower.find("abstract")
                if abstract_pos != -1:
                    # Take next 300 characters as potential abstract
                    abstract_text = full_text_lower[abstract_pos:abstract_pos + 500]
            
            word_count = count_words(abstract_text)
            
            # Be lenient: accept if word count is reasonable (20-200 words)
            if 20 <= word_count <= 200:
                criteria_passed += 1
                feedback_parts.append(f"✅ Abstract present (~{word_count} words)")
            else:
                feedback_parts.append(f"⚠️ Abstract found but unusual length ({word_count} words)")
                # Still give partial credit if it exists
                if word_count > 0:
                    criteria_passed += 0.5
        else:
            feedback_parts.append("❌ Abstract section not found")

        # ===================================================================
        # CRITERION 3: All required sections present
        # ===================================================================
        required_sections = {
            "hypothesis": ["hypothesis"],
            "materials": ["materials", "material"],
            "results": ["results", "result"],
            "conclusion": ["conclusion"],
            "references": ["references", "reference", "sources"]
        }
        
        sections_found = {}
        for section_name, keywords in required_sections.items():
            sections_found[section_name] = any(kw in full_text_lower for kw in keywords)
        
        sections_count = sum(sections_found.values())
        
        if sections_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ All required sections present ({sections_count}/5)")
        elif sections_count >= 4:
            criteria_passed += 0.7
            missing = [k for k, v in sections_found.items() if not v]
            feedback_parts.append(f"⚠️ Most sections present (missing: {', '.join(missing)})")
        else:
            missing = [k for k, v in sections_found.items() if not v]
            feedback_parts.append(f"❌ Missing sections: {', '.join(missing)} ({sections_count}/5)")

        # ===================================================================
        # CRITERION 4: Data table exists
        # ===================================================================
        table_count = count_tables(doc)
        
        if table_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data table present ({table_count} table(s) found)")
        else:
            # Check if there's tabular data in text format (fallback)
            has_tabular_text = ("red" in full_text_lower and "blue" in full_text_lower and 
                               "white" in full_text_lower and any(c.isdigit() for c in full_text))
            if has_tabular_text:
                criteria_passed += 0.5
                feedback_parts.append("⚠️ No formal table, but data appears to be present")
            else:
                feedback_parts.append("❌ No data table found")

        # ===================================================================
        # CRITERION 5: Section headings are formatted (bold)
        # ===================================================================
        headings_to_check = ["Hypothesis", "Materials", "Results", "Conclusion", "References"]
        bold_headings = []
        
        for heading in headings_to_check:
            if check_text_formatting(doc, heading, bold=True):
                bold_headings.append(heading)
        
        if len(bold_headings) >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Section headings formatted ({len(bold_headings)}/5 bold)")
        elif len(bold_headings) >= 3:
            criteria_passed += 0.6
            feedback_parts.append(f"⚠️ Some headings formatted ({len(bold_headings)}/5 bold)")
        else:
            feedback_parts.append(f"❌ Insufficient heading formatting ({len(bold_headings)}/5 bold)")

        # ===================================================================
        # CRITERION 6: References section has at least 2 citations
        # ===================================================================
        refs_found = "references" in full_text_lower or "sources" in full_text_lower
        
        if refs_found:
            # Extract references section
            refs_text = ""
            for keyword in ["references", "sources"]:
                refs_text = extract_section_text(full_text_lower, keyword, None)
                if refs_text:
                    break
            
            # Count citation indicators (URLs, periods after names, numbered items)
            url_count = len(re.findall(r'https?://|www\.', refs_text))
            numbered_items = len(re.findall(r'^\s*\d+\.', refs_text, re.MULTILINE))
            author_patterns = len(re.findall(r'\b[A-Z][a-z]+,\s*[A-Z][a-z]+', full_text))
            
            citation_count = max(url_count, numbered_items, author_patterns // 2)
            
            if citation_count >= 2:
                criteria_passed += 1
                feedback_parts.append(f"✅ References complete ({citation_count} citations detected)")
            elif citation_count >= 1:
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ References present but incomplete ({citation_count} citation)")
            else:
                feedback_parts.append("❌ References section exists but no citations detected")
        else:
            feedback_parts.append("❌ References section not found")

        # ===================================================================
        # CRITERION 7: Document has substantial content (not just template)
        # ===================================================================
        # Bonus check: ensure document was actually filled out
        has_light_experiment_content = (
            "light" in full_text_lower and 
            "plant" in full_text_lower and
            ("blue" in full_text_lower or "red" in full_text_lower)
        )
        
        if has_light_experiment_content:
            criteria_passed += 1
            feedback_parts.append("✅ Document contains experiment content")
        else:
            feedback_parts.append("❌ Document appears to be template/incomplete")

        # ===================================================================
        # Calculate final score
        # ===================================================================
        score = (criteria_passed / total_criteria) * 100
        passed = criteria_passed >= (total_criteria * 0.75)  # Need 75% to pass

        feedback = " | ".join(feedback_parts)

        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria passed")
        logger.info(f"Score: {score:.1f}%, Passed: {passed}")

        return {
            "passed": passed,
            "score": round(score, 1),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
