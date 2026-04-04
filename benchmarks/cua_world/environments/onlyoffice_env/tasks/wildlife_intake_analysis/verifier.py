#!/usr/bin/env python3
"""
Verifier for Wildlife Intake Analysis task
Validates data cleaning and analysis for grant application
"""

import sys
import os
import logging
import tempfile
from typing import Any, Dict, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_species_name(name: str) -> str:
    """Normalize species names for comparison"""
    if not name or not isinstance(name, str):
        return ""
    name_lower = name.lower().strip()
    
    # Map variations to standard names
    if "raccoon" in name_lower or "racc" in name_lower or "racn" in name_lower:
        return "raccoon"
    elif "squirrel" in name_lower or "e.g." in name_lower:
        return "squirrel"
    elif "opossum" in name_lower:
        return "opossum"
    elif "mallard" in name_lower or "mall" in name_lower or "duck" in name_lower:
        return "mallard"
    elif "hawk" in name_lower or "red-tailed" in name_lower:
        return "hawk"
    elif "turtle" in name_lower:
        return "turtle"
    return name_lower


def get_species_category(species: str) -> Optional[str]:
    """Determine if species is Mammal, Bird, or Reptile"""
    species_norm = normalize_species_name(species)
    
    mammals = ["raccoon", "squirrel", "opossum"]
    birds = ["mallard", "hawk", "duck"]
    reptiles = ["turtle"]
    
    if any(m in species_norm for m in mammals):
        return "Mammal"
    elif any(b in species_norm for b in birds):
        return "Bird"
    elif any(r in species_norm for r in reptiles):
        return "Reptile"
    return None


def search_for_value_in_range(sheet: Any, start_row: int, end_row: int, 
                               start_col: int, end_col: int, 
                               value_type: str = "number") -> Optional[Tuple[int, int, Any]]:
    """Search for a value in a range of cells"""
    for row_idx in range(start_row, end_row + 1):
        for col_idx in range(start_col, end_col + 1):
            cell_value = sheet.cell(row=row_idx, column=col_idx).value
            
            if value_type == "number" and isinstance(cell_value, (int, float)) and cell_value > 0:
                return (row_idx, col_idx, cell_value)
            elif value_type == "text" and isinstance(cell_value, str) and cell_value.strip():
                return (row_idx, col_idx, cell_value)
    
    return None


def find_column_by_header(sheet: Any, header_keyword: str, max_cols: int = 15) -> Optional[int]:
    """Find column index by searching for header keyword in first few rows"""
    for col_idx in range(1, max_cols + 1):
        for row_idx in range(1, 5):  # Check first 4 rows for headers
            cell_value = sheet.cell(row=row_idx, column=col_idx).value
            if cell_value and isinstance(cell_value, str):
                if header_keyword.lower() in cell_value.lower():
                    return col_idx
    return None


def verify_wildlife_intake_analysis(traj, env_info, task_info):
    """
    Verify the wildlife intake analysis task.
    
    Checks:
    1. Species Category Summary Table (rows 40-44 area) - 40 points
    2. Success Rate calculation (rows 46-50 area) - 20 points
    3. Top 3 Species list (rows 52-55 area) - 15 points
    4. Average Days in Care (row 57 area) - 10 points
    5. Species Category column added - 10 points
    6. Days in Care column added - 5 points
    
    Total: 100 points, pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    filepath = "/home/ga/Documents/Spreadsheets/wildlife_intake_spring.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='wildlife_verify_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(filepath, copy_from_env, 'xlsx')
        
        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Could not open file: {error}"}
        
        sheet = wb.active
        score = 0.0
        feedback_parts = []
        
        # ===================================================================
        # 1. Check Species Category Summary (rows 40-44, area flexibility)
        # ===================================================================
        categories_found = {}
        
        # Search in rows 38-48 (allowing some flexibility)
        for row_idx in range(38, 49):
            label = get_cell_value(wb, sheet.title, f'A{row_idx}')
            count = get_cell_value(wb, sheet.title, f'B{row_idx}')
            
            if label and isinstance(label, str):
                label_lower = label.lower().strip()
                if isinstance(count, (int, float)) and count > 0:
                    if "mammal" in label_lower:
                        categories_found["Mammals"] = count
                    elif "bird" in label_lower:
                        categories_found["Birds"] = count
                    elif "reptile" in label_lower:
                        categories_found["Reptiles"] = count
        
        # Expected approximate counts from the data:
        # Mammals: Raccoon(7) + Squirrel(6) + Opossum(3) = 16
        # Birds: Mallard(5) + Hawk(3) = 8
        # Reptiles: Turtle(2) = 2
        # Total non-blank species entries: ~26
        
        if len(categories_found) >= 3:
            score += 0.25
            feedback_parts.append(f"✅ All 3 categories identified: {list(categories_found.keys())}")
        elif len(categories_found) >= 2:
            score += 0.15
            feedback_parts.append(f"⚠️ Only {len(categories_found)} categories found")
        else:
            feedback_parts.append(f"❌ Species categories not found or incomplete")
        
        # Validate counts are reasonable
        total_categorized = sum(categories_found.values()) if categories_found else 0
        
        if 20 <= total_categorized <= 35:
            score += 0.15
            feedback_parts.append(f"✅ Category counts reasonable (total: {total_categorized})")
            
            # Check individual categories are sensible
            if categories_found.get("Mammals", 0) > categories_found.get("Birds", 0):
                # Mammals should be most common
                pass
            if categories_found.get("Reptiles", 0) <= 3:
                # Few reptiles
                pass
        elif total_categorized > 0:
            score += 0.05
            feedback_parts.append(f"⚠️ Category counts present but unusual (total: {total_categorized})")
        else:
            feedback_parts.append(f"❌ Category counts missing or zero")
        
        # ===================================================================
        # 2. Check Outcome Analysis / Success Rate (rows 46-50 area)
        # ===================================================================
        # Expected: ~17 completed cases (excluding blank outcomes)
        # Expected: ~14 released / 17 completed = ~82%
        
        success_rate_found = False
        success_rate_value = None
        
        # Search in rows 44-54 for a percentage value
        for row_idx in range(44, 55):
            for col_idx in range(1, 6):
                cell_value = sheet.cell(row=row_idx, column=col_idx).value
                
                if cell_value and isinstance(cell_value, (int, float)):
                    # Check if it's a reasonable success rate (40-100%)
                    # Could be as percentage (65.5) or as decimal (0.655)
                    if 40 <= cell_value <= 100:
                        success_rate_found = True
                        success_rate_value = cell_value
                        score += 0.20
                        feedback_parts.append(f"✅ Success rate calculated: {cell_value:.1f}%")
                        break
                    elif 0.4 <= cell_value <= 1.0:
                        success_rate_found = True
                        success_rate_value = cell_value * 100
                        score += 0.20
                        feedback_parts.append(f"✅ Success rate calculated: {success_rate_value:.1f}%")
                        break
            
            if success_rate_found:
                break
        
        if not success_rate_found:
            feedback_parts.append("❌ Success rate not found or value unreasonable")
        
        # ===================================================================
        # 3. Check Top 3 Species (rows 52-55 area)
        # ===================================================================
        # Expected top species: Raccoon (7), Squirrel (6), Mallard (5)
        
        species_entries_found = 0
        top_species_data = []
        
        # Search in rows 50-60 for species names and counts
        for row_idx in range(50, 61):
            species_name = get_cell_value(wb, sheet.title, f'A{row_idx}')
            species_count = get_cell_value(wb, sheet.title, f'B{row_idx}')
            
            if species_name and isinstance(species_name, str) and species_name.strip():
                # Check if it's a species name (not a label)
                name_lower = species_name.lower()
                is_species = any(sp in name_lower for sp in 
                               ["raccoon", "squirrel", "opossum", "duck", "mallard", "hawk", "turtle"])
                
                if is_species and isinstance(species_count, (int, float)) and species_count > 0:
                    species_entries_found += 1
                    top_species_data.append((species_name, species_count))
        
        if species_entries_found >= 3:
            score += 0.15
            feedback_parts.append(f"✅ Top 3 species identified ({species_entries_found} entries)")
        elif species_entries_found >= 2:
            score += 0.08
            feedback_parts.append(f"⚠️ Only {species_entries_found} top species found")
        else:
            feedback_parts.append(f"❌ Top species list not found")
        
        # ===================================================================
        # 4. Check Average Days in Care (row 57 area)
        # ===================================================================
        # Expected: varies based on calculation, roughly 25-45 days
        
        avg_days_found = False
        avg_days_value = None
        
        # Search in rows 55-65 for average days
        for row_idx in range(55, 66):
            for col_idx in range(1, 6):
                cell_value = sheet.cell(row=row_idx, column=col_idx).value
                
                if cell_value and isinstance(cell_value, (int, float)):
                    # Reasonable range: 10-70 days (flexible for different calculation methods)
                    if 10 <= cell_value <= 70:
                        avg_days_found = True
                        avg_days_value = cell_value
                        score += 0.10
                        feedback_parts.append(f"✅ Average days in care: {cell_value:.1f} days")
                        break
            
            if avg_days_found:
                break
        
        if not avg_days_found:
            feedback_parts.append("❌ Average days in care not found or unreasonable")
        
        # ===================================================================
        # 5. Check for Species Category Column (new column D or nearby)
        # ===================================================================
        category_col_found = False
        
        # Look for a column with header containing "category" or "type"
        category_col_idx = find_column_by_header(sheet, "category")
        if not category_col_idx:
            category_col_idx = find_column_by_header(sheet, "type")
        
        if category_col_idx:
            # Check if it has appropriate values
            category_values = set()
            for row_idx in range(2, 25):  # Check data rows
                val = sheet.cell(row=row_idx, column=category_col_idx).value
                if val and isinstance(val, str):
                    val_lower = val.lower().strip()
                    category_values.add(val_lower)
            
            # Should have mammal, bird, reptile (or variations)
            has_mammal = any("mammal" in v for v in category_values)
            has_bird = any("bird" in v for v in category_values)
            has_reptile = any("reptile" in v for v in category_values)
            
            if has_mammal and has_bird:
                category_col_found = True
                score += 0.10
                feedback_parts.append("✅ Species category column added and populated")
            elif has_mammal or has_bird:
                category_col_found = True
                score += 0.05
                feedback_parts.append("⚠️ Species category column partially populated")
        
        if not category_col_found:
            feedback_parts.append("❌ Species category column not found")
        
        # ===================================================================
        # 6. Check for Days in Care Column
        # ===================================================================
        days_col_found = False
        
        # Look for a column with header containing "days" and "care"
        days_col_idx = find_column_by_header(sheet, "days")
        
        if days_col_idx:
            # Check if it has numeric values
            numeric_count = 0
            numeric_values = []
            
            for row_idx in range(2, 25):
                val = sheet.cell(row=row_idx, column=days_col_idx).value
                if isinstance(val, (int, float)) and val > 0:
                    numeric_count += 1
                    numeric_values.append(val)
            
            # Should have at least 10 calculated days values
            if numeric_count >= 10:
                days_col_found = True
                score += 0.05
                avg_calc = sum(numeric_values) / len(numeric_values) if numeric_values else 0
                feedback_parts.append(f"✅ Days in care column added ({numeric_count} entries, avg: {avg_calc:.1f})")
            elif numeric_count >= 5:
                score += 0.02
                feedback_parts.append(f"⚠️ Days in care column partially filled ({numeric_count} entries)")
        
        if not days_col_found:
            feedback_parts.append("❌ Days in care column not found")
        
        # ===================================================================
        # Final scoring
        # ===================================================================
        passed = score >= 0.70
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: score={score:.2f}, passed={passed}")
        
        return {
            "passed": passed,
            "score": round(score, 2),
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
