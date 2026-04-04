#!/usr/bin/env python3
"""
Verifier for artifact_catalog_completion@1
Checks that archaeological catalog is properly completed from field notes
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_artifact_catalog(traj, env_info, task_info):
    """
    Verify that the artifact catalog spreadsheet is properly completed.
    
    Expected completion:
    - All 14 artifacts cataloged (excluding modern glass NE-004)
    - Proper Catalog ID format: CA-YOL-42-[GRID]-[###]
    - Standardized categories: Ceramic, Lithic, Faunal, Shell, Charcoal
    - All required columns filled
    - Correct grid square assignments
    - Sequential numbering within grids (NE: 1,2,3,5; SW: 1,2,3; NW: 1-6)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/archaeology_survey/artifact_catalog.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_archaeology_')
    
    try:
        # Copy and parse the spreadsheet
        success, workbook, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            file_format='xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse catalog: {error}"
            }
        
        # Get the sheet data
        sheet_data = get_sheet_data(workbook, "Artifact Catalog", max_rows=30, max_cols=10)
        
        if not sheet_data or len(sheet_data) < 2:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Catalog appears empty or missing headers"
            }
        
        feedback_parts = []
        score = 0.0
        max_score = 100.0
        
        # Parse catalog entries (skip header row at index 0)
        catalog_entries = []
        for row_idx, row in enumerate(sheet_data[1:], start=2):
            if row and len(row) > 0 and row[0]:  # If Catalog ID exists
                catalog_id = str(row[0]).strip()
                # Skip empty rows and instruction rows
                if catalog_id and not catalog_id.startswith("INSTRUCTIONS") and catalog_id != "":
                    entry = {
                        "row": row_idx,
                        "catalog_id": catalog_id,
                        "grid": str(row[1]).strip() if len(row) > 1 and row[1] else "",
                        "item_num": str(row[2]).strip() if len(row) > 2 and row[2] else "",
                        "category": str(row[3]).strip() if len(row) > 3 and row[3] else "",
                        "material": str(row[4]).strip() if len(row) > 4 and row[4] else "",
                        "depth": str(row[5]).strip() if len(row) > 5 and row[5] else "",
                        "condition": str(row[6]).strip() if len(row) > 6 and row[6] else "",
                        "notes": str(row[7]).strip() if len(row) > 7 and row[7] else "",
                    }
                    catalog_entries.append(entry)
        
        # ===== CHECK 1: Correct number of artifacts (20 points) =====
        if len(catalog_entries) == 14:
            score += 20
            feedback_parts.append(f"✅ Correct count: 14 artifacts cataloged")
        elif len(catalog_entries) == 15:
            # They might have included the modern glass - common mistake
            feedback_parts.append(f"❌ Artifact count: Found 15 (likely included modern glass NE-004 which should be excluded)")
        else:
            feedback_parts.append(f"❌ Artifact count: Expected 14, found {len(catalog_entries)}")
        
        # ===== CHECK 2: Catalog ID format validation (15 points) =====
        valid_catalog_ids = 0
        catalog_id_pattern = re.compile(r'^CA-YOL-42-(NE|SW|NW)-\d{3}$', re.IGNORECASE)
        invalid_ids = []
        
        for entry in catalog_entries:
            if catalog_id_pattern.match(entry["catalog_id"]):
                valid_catalog_ids += 1
            else:
                invalid_ids.append(entry["catalog_id"])
        
        if valid_catalog_ids == len(catalog_entries) and len(catalog_entries) > 0:
            score += 15
            feedback_parts.append(f"✅ All Catalog IDs properly formatted")
        else:
            feedback_parts.append(f"❌ Catalog ID format issues: {valid_catalog_ids}/{len(catalog_entries)} valid (invalid: {', '.join(invalid_ids[:3])})")
        
        # ===== CHECK 3: Standardized categories (15 points) =====
        valid_categories = {"Ceramic", "Lithic", "Faunal", "Shell", "Charcoal"}
        category_counts = {}
        category_errors = []
        
        for entry in catalog_entries:
            cat = entry["category"]
            if cat in valid_categories:
                category_counts[cat] = category_counts.get(cat, 0) + 1
            else:
                category_errors.append(f"{entry['catalog_id']}:{cat}")
        
        if len(category_errors) == 0 and len(catalog_entries) > 0:
            score += 15
            feedback_parts.append(f"✅ All categories standardized correctly")
        else:
            feedback_parts.append(f"❌ Category errors: {len(category_errors)} non-standard categories (e.g., {', '.join(category_errors[:3])})")
        
        # ===== CHECK 4: Grid square distribution (15 points) =====
        grid_counts = {"NE": 0, "SW": 0, "NW": 0}
        for entry in catalog_entries:
            grid = entry["grid"].upper()
            if grid in grid_counts:
                grid_counts[grid] += 1
        
        # Expected: NE=4 (excluding NE-004 glass), SW=3, NW=6
        expected_counts = {"NE": 4, "SW": 3, "NW": 6}
        distribution_correct = (grid_counts == expected_counts)
        
        if distribution_correct:
            score += 15
            feedback_parts.append(f"✅ Correct grid distribution: NE={grid_counts['NE']}, SW={grid_counts['SW']}, NW={grid_counts['NW']}")
        else:
            # Check if they're close (allow some flexibility)
            total_correct = sum(1 for g in ["NE", "SW", "NW"] if grid_counts[g] == expected_counts[g])
            if total_correct >= 2:
                partial_score = 10
                score += partial_score
                feedback_parts.append(f"⚠️ Grid distribution mostly correct: NE={grid_counts['NE']} (exp 4), SW={grid_counts['SW']} (exp 3), NW={grid_counts['NW']} (exp 6)")
            else:
                feedback_parts.append(f"❌ Grid distribution: Expected NE=4, SW=3, NW=6; Got NE={grid_counts['NE']}, SW={grid_counts['SW']}, NW={grid_counts['NW']}")
        
        # ===== CHECK 5: Required fields filled (15 points) =====
        complete_entries = 0
        incomplete_details = []
        
        for entry in catalog_entries:
            required_fields = ["catalog_id", "grid", "item_num", "category", "material", "condition"]
            missing = [f for f in required_fields if not entry[f]]
            if len(missing) == 0:
                complete_entries += 1
            else:
                incomplete_details.append(f"{entry['catalog_id']}:missing({','.join(missing)})")
        
        if complete_entries == len(catalog_entries) and len(catalog_entries) > 0:
            score += 15
            feedback_parts.append(f"✅ All required fields filled for all entries")
        else:
            completeness_ratio = complete_entries / max(len(catalog_entries), 1)
            partial_score = int(15 * completeness_ratio)
            score += partial_score
            feedback_parts.append(f"❌ Incomplete entries: {len(catalog_entries) - complete_entries} missing required fields (e.g., {', '.join(incomplete_details[:2])})")
        
        # ===== CHECK 6: Specific critical artifact verification (20 points) =====
        # Check for distinctive artifacts that test understanding of the notes
        critical_finds = {
            "projectile_point": False,  # SW-001, obsidian, depth 22
            "shell_bead": False,  # NW-002, Shell category
            "charcoal_sample": False,  # SW-003, Charcoal category
            "grinding_stone": False, # SW-002, basalt, depth 10
        }
        
        for entry in catalog_entries:
            grid = entry["grid"].upper()
            item_num = entry["item_num"]
            category = entry["category"]
            material = entry["material"]
            depth_str = entry["depth"]
            notes_lower = entry["notes"].lower()
            
            # Try to parse depth as number
            try:
                depth_val = int(float(depth_str)) if depth_str else -1
            except:
                depth_val = -1
            
            # Check for projectile point (SW-001)
            if grid == "SW" and item_num == "001":
                if category == "Lithic" and "Obsidian" in material:
                    if "point" in notes_lower or "projectile" in notes_lower:
                        critical_finds["projectile_point"] = True
                    elif depth_val == 22:  # Correct depth is a good sign
                        critical_finds["projectile_point"] = True
            
            # Check for shell bead (NW-002)
            if grid == "NW" and item_num == "002":
                if category == "Shell":
                    critical_finds["shell_bead"] = True
            
            # Check for charcoal sample (SW-003)
            if grid == "SW" and item_num == "003":
                if category == "Charcoal":
                    critical_finds["charcoal_sample"] = True
            
            # Check for grinding stone (SW-002)
            if grid == "SW" and item_num == "002":
                if category == "Lithic" and "Basalt" in material:
                    if "grind" in notes_lower or "stone" in notes_lower:
                        critical_finds["grinding_stone"] = True
        
        critical_score = sum(critical_finds.values()) * (20 / 4)
        score += critical_score
        
        if all(critical_finds.values()):
            feedback_parts.append(f"✅ All critical artifacts correctly identified")
        else:
            missing = [k.replace('_', ' ') for k, v in critical_finds.items() if not v]
            found = sum(critical_finds.values())
            feedback_parts.append(f"⚠️ Critical artifacts: {found}/4 found correctly (missing: {', '.join(missing)})")
        
        # ===== CHECK 7: Verify modern glass was excluded (bonus/penalty) =====
        # Check if NE-004 appears in the catalog (it shouldn't)
        has_modern_glass = False
        for entry in catalog_entries:
            if entry["grid"].upper() == "NE" and entry["item_num"] == "004":
                has_modern_glass = True
                break
        
        if has_modern_glass:
            feedback_parts.append(f"❌ ERROR: Modern glass (NE-004) included - should be excluded as contamination")
            # Don't penalize score heavily, just note the error
        
        # Ensure score doesn't exceed max
        score = min(score, max_score)
        
        # Determine pass/fail (70% threshold)
        passed = score >= 70.0
        
        # Normalize score to 0-1 range
        normalized_score = score / max_score
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": normalized_score,
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
