#!/usr/bin/env python3
"""
Verifier for declutter_inventory@1
Checks kitchen decluttering spreadsheet structure, data, calculations, and formatting
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_declutter_inventory(traj, env_info, task_info):
    """
    Verify the kitchen decluttering inventory spreadsheet.
    
    Checks:
    1. Proper headers present
    2. Minimum 15 data rows with complete information
    3. Required distribution of decisions (4+ KEEP, 6+ DONATE, 3+ SELL)
    4. Valid categories for all items (at least 2 per category)
    5. SELL items have sell values
    6. Calculations present and correct (Total Revenue, Items to Remove, Retention Rate)
    7. Formatting (header bold/colored, decision colors, currency format, percentage format)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/kitchen_declutter.xlsx"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    try:
        # Copy file from environment
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) < 1000:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File not found or too small - spreadsheet not properly saved"
            }
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file.name)
        if wb is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not parse XLSX file - file may be corrupted"
            }
        
        # Get the first sheet
        sheet_names = wb.sheetnames
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No sheets found in workbook"
            }
        
        ws = wb[sheet_names[0]]
        
        # Expected headers
        expected_headers = ['Item Name', 'Last Used', 'Condition', 'Category', 'Decision', 
                          'Estimated Sell Value', 'Reason']
        
        # Check headers (row 1)
        headers_found = []
        for col in range(1, 8):
            cell = ws.cell(row=1, column=col)
            headers_found.append(str(cell.value) if cell.value else "")
        
        # Flexible header matching (case-insensitive, partial match)
        headers_match = True
        for i, expected in enumerate(expected_headers):
            if i < len(headers_found):
                found = headers_found[i].lower()
                expected_words = expected.lower().split()
                # Check if at least key words are present
                if not any(word in found for word in expected_words):
                    headers_match = False
                    break
            else:
                headers_match = False
                break
        
        if headers_match:
            score += 10
            feedback_parts.append("✅ Headers present and correct")
        else:
            feedback_parts.append(f"❌ Headers incorrect. Expected similar to: {expected_headers}, Got: {headers_found}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
        # Check header formatting (bold and/or background)
        header_cell = ws.cell(row=1, column=1)
        header_has_bold = header_cell.font and header_cell.font.bold
        header_has_fill = header_cell.fill and header_cell.fill.start_color and \
                         str(header_cell.fill.start_color.index) not in ['00000000', '00FFFFFF', 'FFFFFFFF', None]
        
        if header_has_bold:
            score += 5
            feedback_parts.append("✅ Header row is bold")
        else:
            feedback_parts.append("⚠️ Header row should be bold")
        
        if header_has_fill:
            score += 5
            feedback_parts.append("✅ Header row has background color")
        else:
            feedback_parts.append("⚠️ Header row should have background color")
        
        # Collect data rows (starting from row 2)
        data_rows = []
        max_row = min(ws.max_row, 100)  # Limit to first 100 rows to avoid placeholder text
        
        for row_idx in range(2, max_row + 1):
            item_name = ws.cell(row=row_idx, column=1).value
            if not item_name or not str(item_name).strip():
                continue
            
            # Skip instruction/placeholder rows
            item_name_str = str(item_name).strip().lower()
            if any(skip_word in item_name_str for skip_word in ['[add', 'instruction', 'summary', 'total', 'items to remove', 'retention rate']):
                continue
                
            decision_val = ws.cell(row=row_idx, column=5).value
            # Skip rows without decision (likely incomplete)
            if not decision_val or not str(decision_val).strip():
                continue
            
            row_data = {
                'item_name': str(item_name).strip(),
                'last_used': ws.cell(row=row_idx, column=2).value,
                'condition': ws.cell(row=row_idx, column=3).value,
                'category': ws.cell(row=row_idx, column=4).value,
                'decision': ws.cell(row=row_idx, column=5).value,
                'sell_value': ws.cell(row=row_idx, column=6).value,
                'reason': ws.cell(row=row_idx, column=7).value,
                'row_num': row_idx,
                'decision_cell': ws.cell(row=row_idx, column=5),
                'sell_value_cell': ws.cell(row=row_idx, column=6)
            }
            data_rows.append(row_data)
        
        num_items = len(data_rows)
        
        # Check minimum 15 items
        if num_items >= 15:
            score += 15
            feedback_parts.append(f"✅ Found {num_items} items (minimum 15 required)")
        else:
            feedback_parts.append(f"❌ Only {num_items} items found, need at least 15")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
        # Count decisions
        keep_count = 0
        donate_count = 0
        sell_count = 0
        
        valid_conditions = ['Excellent', 'Good', 'Fair', 'Poor']
        valid_categories = ['Cooking', 'Baking', 'Serving', 'Storage', 'Appliance']
        
        category_counts = {cat: 0 for cat in valid_categories}
        
        sell_values = []
        sell_missing_value = []
        decision_colored_count = 0
        
        for row in data_rows:
            # Count decisions (flexible matching)
            decision = str(row['decision']).upper().strip() if row['decision'] else ""
            if 'KEEP' in decision:
                keep_count += 1
            elif 'DONATE' in decision:
                donate_count += 1
            elif 'SELL' in decision:
                sell_count += 1
                # Check if sell value is present and non-zero
                sell_val = row['sell_value']
                if sell_val is None or (isinstance(sell_val, (int, float)) and sell_val == 0):
                    sell_missing_value.append(row['item_name'])
                elif isinstance(sell_val, (int, float)) and sell_val > 0:
                    sell_values.append(float(sell_val))
                elif isinstance(sell_val, str) and sell_val.strip():
                    # Try to parse string as number
                    try:
                        val = float(re.sub(r'[^\d.]', '', sell_val))
                        if val > 0:
                            sell_values.append(val)
                    except:
                        pass
            
            # Validate and count category (flexible matching)
            category = str(row['category']).strip() if row['category'] else ""
            category_matched = False
            for valid_cat in valid_categories:
                if valid_cat.lower() in category.lower():
                    category_counts[valid_cat] += 1
                    category_matched = True
                    break
            
            # Check decision color formatting
            decision_cell = row['decision_cell']
            if decision_cell.font and decision_cell.font.color:
                font_color = decision_cell.font.color
                if hasattr(font_color, 'rgb') and font_color.rgb:
                    rgb = str(font_color.rgb).upper()
                    # Check for appropriate colors
                    if 'KEEP' in decision and any(green in rgb for green in ['00FF00', '008000', '00B050']):
                        decision_colored_count += 1
                    elif 'DONATE' in decision and any(blue in rgb for blue in ['0000FF', '0070C0', '002060']):
                        decision_colored_count += 1
                    elif 'SELL' in decision and (rgb[:2] in ['FF', 'C0', 'E0'] or 'C00000' in rgb or 'FF6600' in rgb):
                        decision_colored_count += 1
        
        # Check decision distribution
        if keep_count >= 4:
            score += 10
            feedback_parts.append(f"✅ KEEP items: {keep_count} (minimum 4)")
        else:
            feedback_parts.append(f"❌ KEEP items: {keep_count}, need at least 4")
        
        if donate_count >= 6:
            score += 10
            feedback_parts.append(f"✅ DONATE items: {donate_count} (minimum 6)")
        else:
            feedback_parts.append(f"❌ DONATE items: {donate_count}, need at least 6")
        
        if sell_count >= 3:
            score += 10
            feedback_parts.append(f"✅ SELL items: {sell_count} (minimum 3)")
        else:
            feedback_parts.append(f"❌ SELL items: {sell_count}, need at least 3")
        
        # Check category distribution
        categories_with_two_plus = sum(1 for count in category_counts.values() if count >= 2)
        if categories_with_two_plus >= 5:
            score += 10
            feedback_parts.append(f"✅ All 5 categories have at least 2 items")
        elif categories_with_two_plus >= 3:
            score += 5
            cat_report = ", ".join([f"{cat}:{cnt}" for cat, cnt in category_counts.items()])
            feedback_parts.append(f"⚠️ Category distribution: {cat_report} (need 2+ per category)")
        else:
            cat_report = ", ".join([f"{cat}:{cnt}" for cat, cnt in category_counts.items()])
            feedback_parts.append(f"❌ Category distribution insufficient: {cat_report}")
        
        # Check for sell values on SELL items
        if sell_missing_value:
            feedback_parts.append(f"⚠️ {len(sell_missing_value)} SELL items missing values: {', '.join(sell_missing_value[:3])}")
        elif sell_count > 0:
            score += 5
            feedback_parts.append("✅ All SELL items have estimated values")
        
        # Check for calculations (search in rows 15-50)
        calculation_found = False
        total_revenue_correct = False
        items_to_remove_found = False
        retention_rate_found = False
        
        expected_total_revenue = sum(sell_values) if sell_values else 0
        expected_items_to_remove = donate_count + sell_count
        expected_retention_rate = keep_count / num_items if num_items > 0 else 0
        
        for row_idx in range(15, min(50, max_row + 1)):
            for col_idx in range(1, 8):
                cell = ws.cell(row=row_idx, column=col_idx)
                cell_value = str(cell.value).lower() if cell.value else ""
                
                # Look for "total" or "revenue" labels
                if ('total' in cell_value and 'revenue' in cell_value) or 'total potential revenue' in cell_value:
                    calculation_found = True
                    # Check adjacent cells (right and below) for the sum
                    for check_col in [col_idx, col_idx + 1, col_idx + 2]:
                        for check_row in [row_idx, row_idx + 1]:
                            check_cell = ws.cell(row=check_row, column=check_col)
                            if check_cell.value and isinstance(check_cell.value, (int, float)):
                                if abs(float(check_cell.value) - expected_total_revenue) < 0.01:
                                    total_revenue_correct = True
                                    break
                
                # Look for "items to remove"
                if 'items to remove' in cell_value or ('item' in cell_value and 'remove' in cell_value):
                    for check_col in [col_idx, col_idx + 1, col_idx + 2]:
                        for check_row in [row_idx, row_idx + 1]:
                            check_cell = ws.cell(row=check_row, column=check_col)
                            if check_cell.value and isinstance(check_cell.value, (int, float)):
                                if abs(float(check_cell.value) - expected_items_to_remove) <= 1:
                                    items_to_remove_found = True
                                    break
                
                # Look for "retention rate"
                if 'retention' in cell_value or ('retention' in cell_value and 'rate' in cell_value):
                    for check_col in [col_idx, col_idx + 1, col_idx + 2]:
                        for check_row in [row_idx, row_idx + 1]:
                            check_cell = ws.cell(row=check_row, column=check_col)
                            if check_cell.value is not None:
                                val = check_cell.value
                                # Could be decimal (0.33) or percentage (33%)
                                if isinstance(val, (int, float)):
                                    # Check if it's close to expected (either as decimal or percentage)
                                    if abs(float(val) - expected_retention_rate) < 0.05 or \
                                       abs(float(val) - expected_retention_rate * 100) < 5:
                                        retention_rate_found = True
                                        break
        
        # Score calculations
        if total_revenue_correct:
            score += 10
            feedback_parts.append(f"✅ Total Potential Revenue calculation correct (${expected_total_revenue:.2f})")
        elif calculation_found:
            score += 5
            feedback_parts.append(f"⚠️ Revenue calculation found but value may be incorrect (expected ${expected_total_revenue:.2f})")
        else:
            feedback_parts.append("❌ Missing Total Potential Revenue calculation")
        
        if items_to_remove_found:
            score += 5
            feedback_parts.append(f"✅ Items to Remove calculation found ({expected_items_to_remove})")
        else:
            feedback_parts.append(f"⚠️ Missing Items to Remove calculation (expected {expected_items_to_remove})")
        
        if retention_rate_found:
            score += 5
            feedback_parts.append(f"✅ Retention Rate calculation found (~{expected_retention_rate*100:.1f}%)")
        else:
            feedback_parts.append(f"⚠️ Missing Retention Rate calculation (expected ~{expected_retention_rate*100:.1f}%)")
        
        # Check currency formatting on sell value column
        currency_formatted = False
        for row in data_rows[:5]:  # Check first 5 rows
            if row['sell_value'] and isinstance(row['sell_value'], (int, float)) and row['sell_value'] > 0:
                number_format = row['sell_value_cell'].number_format
                if number_format and ('$' in str(number_format) or 'currency' in str(number_format).lower() or '#,##0' in str(number_format)):
                    currency_formatted = True
                    break
        
        if currency_formatted:
            score += 5
            feedback_parts.append("✅ Sell values have currency formatting")
        else:
            feedback_parts.append("⚠️ Sell values should have currency formatting ($)")
        
        # Check decision color coding
        color_ratio = decision_colored_count / num_items if num_items > 0 else 0
        if color_ratio >= 0.7:
            score += 10
            feedback_parts.append(f"✅ Decision column has color coding ({decision_colored_count}/{num_items} items)")
        elif color_ratio >= 0.3:
            score += 5
            feedback_parts.append(f"⚠️ Decision column partially color-coded ({decision_colored_count}/{num_items} items)")
        else:
            feedback_parts.append("⚠️ Decision column should have color coding (KEEP=green, DONATE=blue, SELL=orange/red)")
        
        # Final pass/fail determination
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass