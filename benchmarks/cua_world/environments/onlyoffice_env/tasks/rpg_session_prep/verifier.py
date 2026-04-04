#!/usr/bin/env python3
"""
Verifier for RPG Session Prep task (rpg_session_prep@1)
Checks if GM session notes document meets requirements
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_rpg_session_prep(traj, env_info, task_info):
    """
    Verify that the RPG session prep document meets requirements:
    - Title with Heading 1 style (centered) mentioning "Shadowmere" or "Session"
    - Three H2 sections: Active Quests, Key NPCs, Random Encounters
    - At least 2 tables (NPC table with 3+ cols, Encounter table with 2+ cols)
    - Tables have content
    - Reasonable text length
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/TextDocuments/session_notes.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_rpg_')
    
    try:
        # Copy and parse document
        success, doc, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'docx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not load document: {error}"
            }
        
        criteria_passed = 0
        max_criteria = 9
        feedback_parts = []
        
        # Get full text
        full_text = get_document_text(doc)
        
        # Criterion 1: Document has substantial content (>200 chars)
        if len(full_text) > 200:
            criteria_passed += 1
            feedback_parts.append(f"✅ Document has content ({len(full_text)} chars)")
        else:
            feedback_parts.append(f"❌ Document too short ({len(full_text)} chars, need >200)")
        
        # Criterion 2 & 3: Title with Heading 1, centered, mentioning session/Shadowmere
        has_title = False
        title_centered = False
        title_text = ""
        
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'Heading 1' in style_name or style_name == 'Title':
                para_text = para.text.lower()
                if 'shadowmere' in para_text or 'session' in para_text or 'crypts' in para_text:
                    has_title = True
                    title_text = para.text
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Title found with Heading 1: '{para.text[:50]}'")
                    
                    # Check centering (alignment value 1 is CENTER)
                    if para.alignment == 1 or (hasattr(para, 'alignment_val') and para.alignment_val == 1):
                        title_centered = True
                        criteria_passed += 1
                        feedback_parts.append("✅ Title is centered")
                    else:
                        feedback_parts.append(f"❌ Title not centered (alignment: {para.alignment})")
                    break
        
        if not has_title:
            feedback_parts.append("❌ No Heading 1 title found mentioning 'Shadowmere', 'Session', or 'Crypts'")
        
        # Criterion 4: Three section headings (Heading 2)
        required_sections = {
            'active quests': False,
            'key npcs': False,
            'random encounters': False
        }
        
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'Heading 2' in style_name:
                para_text = para.text.lower()
                
                # Check for Active Quests
                if 'active' in para_text and 'quest' in para_text:
                    required_sections['active quests'] = True
                
                # Check for Key NPCs
                if ('key' in para_text or 'important' in para_text) and 'npc' in para_text:
                    required_sections['key npcs'] = True
                
                # Check for Random Encounters
                if ('random' in para_text or 'encounter' in para_text) and ('encounter' in para_text or 'random' in para_text):
                    required_sections['random encounters'] = True
        
        sections_found = sum(required_sections.values())
        if sections_found >= 3:
            criteria_passed += 2
            feedback_parts.append(f"✅ Found all {sections_found} required sections")
        elif sections_found >= 2:
            criteria_passed += 1
            feedback_parts.append(f"⚠️ Found {sections_found}/3 sections: {[k for k, v in required_sections.items() if v]}")
        else:
            missing = [k for k, v in required_sections.items() if not v]
            feedback_parts.append(f"❌ Missing sections: {missing}")
        
        # Criterion 5: Tables present (at least 2)
        num_tables = count_tables(doc)
        
        if num_tables >= 2:
            criteria_passed += 2
            feedback_parts.append(f"✅ Found {num_tables} tables")
        elif num_tables == 1:
            criteria_passed += 1
            feedback_parts.append("⚠️ Only 1 table found, need at least 2")
        else:
            feedback_parts.append("❌ No tables found")
        
        # Criterion 6: Table structure and content
        if num_tables >= 1:
            # Check first table (should ideally be NPC table with 3+ columns)
            table1 = doc.tables[0]
            table1_cols = len(table1.columns)
            table1_rows = len(table1.rows)
            
            # Count non-empty cells
            table1_content_cells = 0
            for row in table1.rows:
                for cell in row.cells:
                    if cell.text.strip() and len(cell.text.strip()) > 1:
                        table1_content_cells += 1
            
            # Check if table has reasonable structure
            has_good_table1 = (table1_cols >= 3 and table1_rows >= 3 and table1_content_cells >= 9)
            
            if num_tables >= 2:
                # Check second table (should be encounter table with 2+ columns)
                table2 = doc.tables[1]
                table2_cols = len(table2.columns)
                table2_rows = len(table2.rows)
                
                table2_content_cells = 0
                for row in table2.rows:
                    for cell in row.cells:
                        if cell.text.strip() and len(cell.text.strip()) > 1:
                            table2_content_cells += 1
                
                has_good_table2 = (table2_cols >= 2 and table2_rows >= 3 and table2_content_cells >= 6)
                
                if has_good_table1 and has_good_table2:
                    criteria_passed += 2
                    feedback_parts.append(f"✅ Tables have proper structure: Table1({table1_cols}x{table1_rows}), Table2({table2_cols}x{table2_rows})")
                elif has_good_table1 or has_good_table2:
                    criteria_passed += 1
                    feedback_parts.append(f"⚠️ One table has good structure: Table1({table1_cols}x{table1_rows}), Table2({table2_cols}x{table2_rows})")
                else:
                    feedback_parts.append(f"❌ Tables lack structure/content: Table1({table1_cols}x{table1_rows}, {table1_content_cells} cells), Table2({table2_cols}x{table2_rows}, {table2_content_cells} cells)")
            elif has_good_table1:
                criteria_passed += 1
                feedback_parts.append(f"⚠️ One table has good structure ({table1_cols}x{table1_rows}), but need 2 tables")
        
        # Calculate final score and pass/fail
        score = int((criteria_passed / max_criteria) * 100)
        passed = criteria_passed >= 7  # Need at least 7/9 criteria
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything framework
