#!/usr/bin/env python3
"""Verifier for the restaurant_menu_formatting task."""

import logging
import os
import re
import sys
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_document_text_odt,
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    check_text_italic_odt,
    get_odt_tables
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restaurant_menu_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/spring_menu_raw.odt")

    # Anti-gaming: Ensure file was modified
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified_during_task = False
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            file_modified_during_task = result.get("file_modified_during_task", False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not file_modified_during_task:
        return {"passed": False, "score": 0, "feedback": "Document was not saved/modified during the task."}

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []
    
    try:
        # Check 1: Content Cleanup (20 pts)
        full_text = get_document_text_odt(content_tree)
        if "[allergens:" not in full_text.lower():
            score += 20
            feedback_parts.append("Allergen tags removed")
            cleanup_passed = True
        else:
            feedback_parts.append("Allergen tags still present in text")
            cleanup_passed = False

        # Check 2: Title & Section Styles (15 pts)
        title_text = "Spring Tasting Menu"
        title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(title_text))
        title_size = check_text_font_size_odt(content_tree, styles_tree, re.escape(title_text), 15.0) 
        title_align, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(title_text), "center")
        
        sections = ["STARTERS", "MAINS", "DESSERTS"]
        sec_h1, _, _ = check_heading_styles_odt(content_tree, styles_tree, sections, 1)
        sec_align_count = sum(1 for sec in sections if check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sec), "center")[0] > 0)
        
        title_sec_score = 0
        if title_bold and title_size and title_align > 0:
            title_sec_score += 8
        if sec_h1 == 3 and sec_align_count == 3:
            title_sec_score += 7
        
        score += title_sec_score
        if title_sec_score == 15:
            feedback_parts.append("Title and Sections formatted correctly")
        else:
            feedback_parts.append(f"Title/Sections partially formatted ({title_sec_score}/15)")

        # Check 3: Dish & Description Styles (15 pts)
        dishes = [
            "Spring Pea Soup", "Crab Cakes", "Burrata & Stone Fruit", 
            "Miso Glazed Black Cod", "Spring Lamb Loin", "Wild Mushroom Risotto", 
            "Pistachio Rosewater Pavlova", "Dark Chocolate Torte", "Lemon Basil Sorbet"
        ]
        dish_h2, _, _ = check_heading_styles_odt(content_tree, styles_tree, dishes, 2)
        
        desc_samples = [
            "Mint, crème fraîche, Meyer lemon oil.",
            "Lump blue crab, remoulade, pickled fennel.",
            "Bok choy, shiitake dashi, scallion.",
            "Meringue, pistachio cream, fresh raspberries."
        ]
        desc_italics = sum(1 for d in desc_samples if check_text_italic_odt(content_tree, styles_tree, re.escape(d)))
        
        dish_desc_score = 0
        if dish_h2 >= 8:
            dish_desc_score += 8
        elif dish_h2 >= 4:
            dish_desc_score += 4
            
        if desc_italics >= 3:
            dish_desc_score += 7
        elif desc_italics >= 1:
            dish_desc_score += 3
            
        score += dish_desc_score
        if dish_desc_score == 15:
            feedback_parts.append("Dishes and Descriptions formatted correctly")
        else:
            feedback_parts.append(f"Dishes/Descriptions partially formatted ({dish_desc_score}/15)")
            
        # Check 4: Table Structure (20 pts)
        tables = get_odt_tables(content_tree)
        table_passed = False
        target_table = None
        col_indices = {}
        
        if tables:
            for t in tables:
                if not t.get('rows'): continue
                headers = [str(h).strip().lower() for h in t['rows'][0]]
                req_cols = ["dish name", "dairy", "gluten", "shellfish", "nuts", "soy", "eggs"]
                found_cols = 0
                temp_indices = {}
                for req in req_cols:
                    for i, h in enumerate(headers):
                        if req in h:
                            found_cols += 1
                            temp_indices[req] = i
                            break
                if found_cols >= 6: # Tolerate at most 1 missing/misspelled column
                    target_table = t
                    col_indices = temp_indices
                    table_passed = True
                    break
                    
        if table_passed:
            score += 20
            feedback_parts.append("Allergen matrix table created correctly")
        else:
            feedback_parts.append("Allergen matrix table missing or incorrect structure")
            
        # Check 5-7: Matrix Accuracy (30 pts)
        matrix_score = 0
        if table_passed:
            # Row 1: Crab Cakes (Shellfish, Gluten, Eggs)
            if _check_matrix_row(target_table, "crab cake", ["shellfish", "gluten", "eggs"], ["dairy", "nuts", "soy"], col_indices):
                matrix_score += 10
                
            # Row 2: Miso Glazed Black Cod (Soy)
            if _check_matrix_row(target_table, "cod", ["soy"], ["dairy", "gluten", "shellfish", "nuts", "eggs"], col_indices):
                matrix_score += 10
                
            # Row 3: Pistachio Rosewater Pavlova (Nuts, Dairy, Eggs)
            if _check_matrix_row(target_table, "pavlova", ["nuts", "dairy", "eggs"], ["gluten", "shellfish", "soy"], col_indices):
                matrix_score += 10
                
        score += matrix_score
        if matrix_score == 30:
            feedback_parts.append("Allergen matrix accurately populated")
        else:
            feedback_parts.append(f"Allergen matrix accuracy partial/failed ({matrix_score}/30)")

        # VLM Verification of visual progress across trajectory
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            query_vlm = env_info.get("query_vlm")
            if query_vlm:
                frames = sample_trajectory_frames(traj, n=3)
                final_frame = get_final_screenshot(traj)
                
                prompt = """Analyze this sequence of screenshots from an agent formatting a restaurant menu.
                1. WORKFLOW: Do the frames show the agent formatting the text (e.g., adding styles, creating a table at the bottom)?
                2. TABLE_CREATED: In the final image, is there a tabular 'Allergen Matrix' visible with multiple rows/columns?
                
                Respond in JSON:
                {"workflow_observed": true/false, "table_visible_in_final": true/false}
                """
                
                vlm_res = query_vlm(prompt=prompt, images=frames + [final_frame])
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("workflow_observed") and parsed.get("table_visible_in_final"):
                        feedback_parts.append("VLM visual verification passed")
                    else:
                        feedback_parts.append("VLM visual verification failed")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")

        passed = score >= 70 and cleanup_passed and table_passed
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": score,
            "feedback": f"Error during verification: {e} | { ' | '.join(feedback_parts) }"
        }

def _check_matrix_row(table, dish_keyword, expected, missing, indices):
    """Helper to check if a specific row in the matrix has correct boolean checkmarks."""
    for row in table['rows'][1:]:
        if len(row) <= indices.get("dish name", 0):
            continue
            
        if dish_keyword.lower() in str(row[indices.get("dish name", 0)]).lower():
            for req in expected:
                idx = indices.get(req)
                if idx is None or idx >= len(row): return False
                val = str(row[idx]).strip().lower()
                # Consider an "X" or common checkmark alternatives valid
                if not any(char in val for char in ['x', 'y', 'v', 't', '1', '✓']):
                    return False
            for mis in missing:
                idx = indices.get(mis)
                if idx is None or idx >= len(row): continue
                val = str(row[idx]).strip().lower()
                if any(char in val for char in ['x', 'y', 'v', 't', '1', '✓']):
                    return False
            return True
    return False