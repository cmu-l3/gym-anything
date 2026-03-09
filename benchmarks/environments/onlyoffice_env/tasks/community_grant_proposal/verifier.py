#!/usr/bin/env python3
"""
Verifier for community_grant_proposal@1

Checks that the agent created a properly structured grant proposal document
with required sections, heading styles, and a budget table.
"""

import sys
import os
import logging
import tempfile
import traceback

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_community_grant_proposal(traj, env_info, task_info):
    """
    Verify the community grant proposal document meets requirements
    
    Checks:
    1. Document exists and is parseable
    2. Contains project title "Community Tool Library Initiative"
    3. Has required sections with proper heading styles (at least 3 of 4)
    4. Contains a budget table with appropriate structure
    5. Budget table has correct dimensions (3+ columns, 5+ rows)
    6. Budget table has total row (contains "TOTAL")
    
    Returns:
        dict: {
            "passed": bool,
            "score": int (0-100),
            "feedback": str
        }
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/CommunityGrant_Proposal.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_grant_')
    
    try:
        # Parse document
        success, doc, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'docx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to parse document: {error}"
            }
        
        feedback_parts = []
        score = 0.0
        max_score = 6.0
        
        # Check 1: Document contains project title (1 point)
        full_text = get_document_text(doc)
        if not full_text.strip():
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Document appears to be empty or contains no text"
            }
        
        full_text_lower = full_text.lower()
        
        # Check for project title (flexible matching)
        title_variants = [
            "community tool library initiative",
            "tool library initiative",
            "community tool library"
        ]
        
        title_found = any(variant in full_text_lower for variant in title_variants)
        
        if title_found:
            score += 1.0
            feedback_parts.append("✅ Project title 'Community Tool Library Initiative' found")
        else:
            feedback_parts.append("❌ Project title not found (expected 'Community Tool Library Initiative')")
        
        # Check 2: Required sections with heading styles (2 points)
        required_sections = [
            "executive summary",
            "problem statement", 
            "proposed solution",
            "budget justification"
        ]
        
        heading_texts = []
        for para in doc.paragraphs:
            # Check if paragraph has a heading style
            # Handle both English and localized style names
            style_name = para.style.name.lower()
            if 'heading' in style_name or 'заголовок' in style_name or 'título' in style_name:
                heading_text = para.text.lower().strip()
                if heading_text:  # Only add non-empty headings
                    heading_texts.append(heading_text)
        
        logger.info(f"Found headings: {heading_texts}")
        
        sections_found = 0
        found_section_names = []
        missing_sections = []
        
        for section in required_sections:
            # Check if any heading contains this section name (allows for variations)
            found = False
            for heading in heading_texts:
                # Flexible matching: section keywords can appear in heading
                section_keywords = section.split()
                if all(keyword in heading for keyword in section_keywords):
                    found = True
                    break
            
            if found:
                sections_found += 1
                found_section_names.append(section.title())
            else:
                missing_sections.append(section.title())
        
        logger.info(f"Sections found: {sections_found}/4")
        
        if sections_found >= 4:
            score += 2.0
            feedback_parts.append(f"✅ All 4 required sections found with heading styles")
        elif sections_found >= 3:
            score += 1.5
            feedback_parts.append(f"✅ Found {sections_found}/4 required sections (acceptable)")
            if missing_sections:
                feedback_parts.append(f"   Missing: {', '.join(missing_sections)}")
        elif sections_found >= 2:
            score += 1.0
            feedback_parts.append(f"⚠️ Only {sections_found}/4 sections found")
            feedback_parts.append(f"   Missing: {', '.join(missing_sections)}")
        else:
            feedback_parts.append(f"❌ Only {sections_found}/4 required sections found")
            feedback_parts.append(f"   Expected sections with Heading 1 style: {', '.join([s.title() for s in required_sections])}")
        
        # Check 3: Document contains a table (1 point)
        num_tables = count_tables(doc)
        logger.info(f"Number of tables found: {num_tables}")
        
        if num_tables >= 1:
            score += 1.0
            feedback_parts.append(f"✅ Budget table present ({num_tables} table(s) found)")
            
            # Analyze table structure
            table = doc.tables[0]
            num_rows = len(table.rows)
            num_cols = len(table.columns)
            
            logger.info(f"Table dimensions: {num_rows} rows x {num_cols} columns")
            
            # Check 4: Table has at least 3 columns (1 point)
            if num_cols >= 3:
                score += 1.0
                feedback_parts.append(f"✅ Table has {num_cols} columns (expected 3+ for Item/Description/Cost)")
            elif num_cols >= 2:
                score += 0.5
                feedback_parts.append(f"⚠️ Table has {num_cols} columns (expected 3)")
            else:
                feedback_parts.append(f"❌ Table has only {num_cols} column(s) (expected 3)")
            
            # Check 5: Table has at least 5 rows - 4 items + 1 total (0.5 points)
            if num_rows >= 5:
                score += 0.5
                feedback_parts.append(f"✅ Table has {num_rows} rows (sufficient for items + total)")
            elif num_rows >= 4:
                score += 0.3
                feedback_parts.append(f"⚠️ Table has {num_rows} rows (expected 5+)")
            elif num_rows >= 2:
                score += 0.1
                feedback_parts.append(f"⚠️ Table has only {num_rows} rows (expected 5+)")
            else:
                feedback_parts.append(f"❌ Table has only {num_rows} row(s) (expected 5+)")
            
            # Check 6: Table contains "TOTAL" indicating total project cost (0.5 points)
            table_text = ""
            try:
                for row in table.rows:
                    for cell in row.cells:
                        cell_text = cell.text.lower()
                        table_text += cell_text + " "
            except Exception as e:
                logger.warning(f"Error reading table cells: {e}")
            
            logger.info(f"Table text (first 200 chars): {table_text[:200]}")
            
            # Check for "total" in table text
            if "total" in table_text:
                score += 0.5
                feedback_parts.append("✅ Budget total row found (contains 'TOTAL')")
            else:
                feedback_parts.append("❌ Budget total row not found (should contain 'TOTAL')")
                
        else:
            feedback_parts.append("❌ No budget table found in document")
            feedback_parts.append("   Expected: A table with 3 columns and at least 5 rows")
        
        # Calculate pass/fail (70% threshold = 4.2/6.0)
        final_score = int((score / max_score) * 100)
        passed = score >= (max_score * 0.70)
        
        # Build feedback string
        feedback = " | ".join(feedback_parts)
        feedback += f" || Final Score: {score:.1f}/{max_score} = {final_score}%"
        
        logger.info(f"Verification complete: passed={passed}, score={final_score}%")
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }
        
    except Exception as e:
        error_msg = f"❌ Verification error: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"{error_msg} | Traceback: {traceback.format_exc()[:200]}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
