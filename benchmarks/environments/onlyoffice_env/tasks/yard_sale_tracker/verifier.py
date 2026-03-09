#!/usr/bin/env python3
"""
Verifier for Yard Sale Tracker task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_yard_sale_tracker(traj, env_info, task_info):
    """
    Verify the yard sale tracker spreadsheet.
    
    Checks:
    1. Correct headers in row 1 (Item, Owner, Price, Status, Notes)
    2. At least 12 data rows with required columns filled
    3. Items distributed across 4 different owners
    4. Prices are numeric and reasonable ($1-$75 range)
    5. Summary section exists with correct structure
    6. Owner totals present (formulas create calculated values)
    7. Grand total present
    8. Headers have formatting (bold detected via style)
    9. Price column has numeric values
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/yard_sale_tracker.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_yard_sale_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load spreadsheet: {error}"
            }
        
        # Get the active sheet
        sheet_name = wb.sheetnames[0]
        sheet = wb[sheet_name]
        
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # Check 1: Verify headers (1.5 points)
        expected_headers = ["item", "owner", "price", "status", "notes"]
        actual_headers = []
        headers_row = 1
        
        # Try to find header row (might not be in row 1 if agent cleared template)
        for row_idx in range(1, 10):
            row_vals = [
                sheet[f'A{row_idx}'].value,
                sheet[f'B{row_idx}'].value,
                sheet[f'C{row_idx}'].value,
                sheet[f'D{row_idx}'].value,
                sheet[f'E{row_idx}'].value
            ]
            
            # Check if this looks like a header row
            if row_vals[0] and row_vals[1] and row_vals[2]:
                row_text = ' '.join([str(v).lower() if v else '' for v in row_vals])
                if 'item' in row_text and 'owner' in row_text and 'price' in row_text:
                    headers_row = row_idx
                    actual_headers = row_vals
                    break
        
        if not actual_headers:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ No valid header row found. Expected: Item, Owner, Price, Status, Notes"
            }
        
        # Check if headers match expected
        headers_correct = True
        for i, expected in enumerate(expected_headers):
            actual = str(actual_headers[i]).lower() if actual_headers[i] else ""
            if expected not in actual:
                headers_correct = False
                break
        
        if headers_correct:
            score += 1.5
            feedback_parts.append(f"✅ Headers correct (row {headers_row})")
        else:
            score += 0.5
            feedback_parts.append(f"⚠️ Headers partially correct: {actual_headers}")
        
        # Check 2: Count data rows (must have at least 12 items) (1.5 points)
        data_rows = []
        start_row = headers_row + 1
        
        for row_idx in range(start_row, start_row + 50):  # Check up to 50 rows
            item = sheet[f'A{row_idx}'].value
            owner = sheet[f'B{row_idx}'].value
            price = sheet[f'C{row_idx}'].value
            
            # Stop if we hit obvious summary section
            if item and isinstance(item, str):
                item_str = str(item).upper()
                if any(keyword in item_str for keyword in ['PROCEEDS', 'SUMMARY', 'TOTAL CASH', 'GRAND TOTAL']):
                    break
            
            # Skip instruction rows
            if item and isinstance(item, str) and 'CREATE' in str(item).upper():
                continue
            if item and isinstance(item, str) and 'TASK:' in str(item).upper():
                continue
                
            # Valid data row must have item, owner, and price
            if item and owner and price is not None:
                try:
                    price_val = float(price) if not isinstance(price, (int, float)) else price
                    data_rows.append({
                        'row': row_idx,
                        'item': str(item),
                        'owner': str(owner),
                        'price': price_val
                    })
                except (ValueError, TypeError):
                    # Price is not numeric, skip this row
                    pass
        
        num_items = len(data_rows)
        if num_items >= 12:
            score += 1.5
            feedback_parts.append(f"✅ Sufficient items: {num_items} found (≥12 required)")
        elif num_items >= 8:
            partial = (num_items / 12.0) * 1.5
            score += partial
            feedback_parts.append(f"⚠️ Only {num_items} items found (12 required, {partial:.1f}/1.5 pts)")
        else:
            feedback_parts.append(f"❌ Insufficient items: {num_items} found (12 required)")
        
        if num_items == 0:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ No valid data rows found"
            }
        
        # Check 3: Verify 4 different owners present (1.5 points)
        owners = set(row['owner'].strip().lower() for row in data_rows)
        required_owners = {"you", "johnsons", "patels", "maria"}
        
        # Check how many required owners are represented
        matching_owners = 0
        found_owners = []
        for req in required_owners:
            for owner in owners:
                if req in owner or owner in req:
                    matching_owners += 1
                    found_owners.append(req)
                    break
        
        if matching_owners >= 4:
            score += 1.5
            feedback_parts.append(f"✅ All 4 owners represented")
        elif matching_owners >= 3:
            score += 1.0
            feedback_parts.append(f"⚠️ Only {matching_owners} owners found (need 4)")
        elif matching_owners >= 2:
            score += 0.5
            feedback_parts.append(f"⚠️ Only {matching_owners} owners found (need 4)")
        else:
            feedback_parts.append(f"❌ Insufficient owner diversity: only {matching_owners} of 4 required owners")
        
        # Check 4: Verify prices are reasonable numbers (1.0 point)
        valid_prices = 0
        for row in data_rows:
            try:
                price_val = float(row['price'])
                if 1.0 <= price_val <= 75.0:
                    valid_prices += 1
            except:
                pass
        
        price_ratio = valid_prices / max(num_items, 1)
        if price_ratio >= 0.9:
            score += 1.0
            feedback_parts.append(f"✅ Prices realistic: {valid_prices}/{num_items} in $1-$75 range")
        elif price_ratio >= 0.6:
            partial = price_ratio * 1.0
            score += partial
            feedback_parts.append(f"⚠️ Some prices unrealistic: {valid_prices}/{num_items} in range ({partial:.1f}/1.0 pts)")
        else:
            feedback_parts.append(f"❌ Many prices unrealistic: {valid_prices}/{num_items} in range")
        
        # Check 5-7: Find and validate summary section (4.5 points total)
        summary_row = None
        last_data_row = data_rows[-1]['row'] if data_rows else headers_row + 1
        
        # Search for summary section starting after data rows
        for row_idx in range(last_data_row + 1, last_data_row + 20):
            cell_val = sheet[f'A{row_idx}'].value
            if cell_val:
                cell_str = str(cell_val).upper()
                if 'PROCEEDS' in cell_str and 'SUMMARY' in cell_str:
                    summary_row = row_idx
                    break
                # Also check for merged cells
                if 'SUMMARY' in cell_str or 'TOTAL' in cell_str:
                    summary_row = row_idx
                    break
        
        if summary_row:
            score += 1.0
            feedback_parts.append(f"✅ Summary section found at row {summary_row}")
            
            # Check 6: Verify owner labels and calculated totals (2.0 points)
            owner_totals_found = 0
            owner_calculations_correct = 0
            
            # Calculate expected totals for each owner
            expected_totals = {}
            for owner_key in ['you', 'johnsons', 'patels', 'maria']:
                total = 0.0
                for row in data_rows:
                    owner_lower = row['owner'].lower()
                    if owner_key in owner_lower or owner_lower in owner_key:
                        total += row['price']
                expected_totals[owner_key] = total
            
            # Check rows after summary header for owner totals
            for offset in range(1, 8):  # Check up to 7 rows after summary
                label_cell = sheet[f'A{summary_row + offset}'].value
                value_cell_raw = sheet[f'B{summary_row + offset}'].value
                
                if not label_cell:
                    continue
                
                label_str = str(label_cell).lower().strip()
                
                # Check if this is an owner label
                matched_owner = None
                for owner_key in required_owners:
                    if owner_key in label_str or label_str in owner_key:
                        matched_owner = owner_key
                        break
                
                if matched_owner and value_cell_raw is not None:
                    owner_totals_found += 1
                    try:
                        value = float(value_cell_raw)
                        expected = expected_totals.get(matched_owner, 0.0)
                        
                        # Allow small tolerance for rounding
                        if abs(value - expected) < 2.0:
                            owner_calculations_correct += 1
                    except (ValueError, TypeError):
                        pass
            
            if owner_calculations_correct >= 4:
                score += 2.0
                feedback_parts.append(f"✅ All owner totals calculated correctly")
            elif owner_calculations_correct >= 3:
                score += 1.5
                feedback_parts.append(f"⚠️ Most owner totals correct ({owner_calculations_correct}/4)")
            elif owner_totals_found >= 3:
                score += 1.0
                feedback_parts.append(f"⚠️ Owner labels present but calculations may be incorrect")
            elif owner_totals_found >= 2:
                score += 0.5
                feedback_parts.append(f"⚠️ Some owner totals present ({owner_totals_found}/4)")
            else:
                feedback_parts.append(f"❌ Owner totals missing or incorrect")
            
            # Check 7: Verify grand total (1.5 points)
            grand_total_found = False
            grand_total_correct = False
            expected_grand_total = sum(row['price'] for row in data_rows)
            
            # Search for grand total row
            for offset in range(1, 12):
                label_cell = sheet[f'A{summary_row + offset}'].value
                value_cell = sheet[f'B{summary_row + offset}'].value
                
                if label_cell:
                    label_str = str(label_cell).upper()
                    if 'TOTAL' in label_str and ('CASH' in label_str or 'GRAND' in label_str):
                        grand_total_found = True
                        if value_cell is not None:
                            try:
                                value = float(value_cell)
                                if abs(value - expected_grand_total) < 2.0:
                                    grand_total_correct = True
                            except (ValueError, TypeError):
                                pass
                        break
            
            if grand_total_correct:
                score += 1.5
                feedback_parts.append(f"✅ Grand total correct: ${expected_grand_total:.2f}")
            elif grand_total_found:
                score += 0.5
                feedback_parts.append(f"⚠️ Grand total present but value may be incorrect")
            else:
                feedback_parts.append(f"❌ Grand total not found")
                
        else:
            feedback_parts.append(f"❌ Summary section not found (expected after row {last_data_row})")
        
        # Check 8: Header formatting (0.5 points)
        # Check if first header cell has bold formatting
        header_cell = sheet[f'A{headers_row}']
        has_formatting = False
        
        if header_cell.font and header_cell.font.bold:
            has_formatting = True
        if header_cell.fill and header_cell.fill.start_color and header_cell.fill.start_color.rgb:
            has_formatting = True
        
        if has_formatting:
            score += 0.5
            feedback_parts.append("✅ Header formatting detected")
        else:
            feedback_parts.append("⚠️ Header formatting not clearly detected (may still be present)")
        
        # Check 9: Column widths adjusted (0.5 points - bonus, give benefit of doubt)
        col_a_width = sheet.column_dimensions['A'].width
        if col_a_width and col_a_width > 15:
            score += 0.5
            feedback_parts.append("✅ Column widths appear adjusted")
        else:
            score += 0.25  # Partial credit
            feedback_parts.append("⚠️ Column widths may not be optimally adjusted")
        
        # Determine pass/fail (need 7.0/10.0 = 70%)
        passed = score >= 7.0
        
        # Normalize score to 0-100 range
        final_score = (score / max_score) * 100
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": " | ".join(feedback_parts)
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
