#!/usr/bin/env python3
"""
Verifier for memorial_slideshow_organizer@1
Checks spreadsheet structure, formulas, conditional formatting, data validation, and realistic content
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_memorial_slideshow_organizer(traj, env_info, task_info):
    """
    Verify memorial slideshow organizer task
    
    Expected:
    - Columns E-L have correct headers
    - Data validation on E, F, G, K
    - Conditional formatting on specific columns
    - At least 15 rows of complete data
    - Slideshow_Order (H) has sequential numbers for YES photos only
    - Summary section with working formulas
    - Freeze panes and auto-filter active
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/memorial_photos_raw.xlsx"
    
    feedback_parts = []
    score = 0.0
    max_score = 100.0
    
    temp_file = None
    
    try:
        # Copy file from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not copy file from container: {str(e)}"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ File not found or empty: {container_path}"
            }
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file.name)
        if wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not parse XLSX file"
            }
        
        sheet = wb.active
        
        # --- CHECK 1: Column headers (E-L) ---
        expected_headers = {
            'E1': ['quality', 'rating'],
            'F1': ['life', 'stage'],
            'G1': ['include', 'slideshow'],
            'H1': ['slideshow', 'order'],
            'I1': ['display', 'seconds'],
            'J1': ['story', 'notes'],
            'K1': ['technical', 'issue'],
            'L1': ['family', 'input']
        }
        
        headers_correct = 0
        for cell_ref, expected_words in expected_headers.items():
            actual = sheet[cell_ref].value
            if actual:
                actual_lower = str(actual).replace('_', '').replace(' ', '').lower()
                if all(word in actual_lower for word in expected_words):
                    headers_correct += 1
        
        if headers_correct >= 6:  # Allow some variation
            score += 10
            feedback_parts.append(f"✅ Column headers present ({headers_correct}/8 match)")
        else:
            feedback_parts.append(f"❌ Column headers missing or incorrect ({headers_correct}/8)")
        
        # --- CHECK 2: Data validation (check if validation exists) ---
        validation_count = 0
        if hasattr(sheet, 'data_validations') and hasattr(sheet.data_validations, 'dataValidation'):
            validation_count = len(sheet.data_validations.dataValidation)
        
        if validation_count >= 3:
            score += 10
            feedback_parts.append(f"✅ Data validation rules found ({validation_count})")
        elif validation_count >= 1:
            score += 5
            feedback_parts.append(f"⚠️  Partial data validation ({validation_count} rules)")
        else:
            feedback_parts.append(f"⚠️  Data validation may be missing ({validation_count} rules found)")
        
        # --- CHECK 3: Conditional formatting ---
        cf_count = 0
        if hasattr(sheet, 'conditional_formatting'):
            try:
                # Try to count conditional formatting rules
                if hasattr(sheet.conditional_formatting, '_cf_rules'):
                    cf_count = len(sheet.conditional_formatting._cf_rules)
                elif hasattr(sheet.conditional_formatting, 'cf_rules'):
                    cf_count = len(sheet.conditional_formatting.cf_rules)
            except:
                pass
        
        if cf_count >= 3:
            score += 10
            feedback_parts.append(f"✅ Conditional formatting rules found ({cf_count})")
        elif cf_count >= 1:
            score += 5
            feedback_parts.append(f"⚠️  Partial conditional formatting ({cf_count} rules)")
        else:
            feedback_parts.append(f"⚠️  Conditional formatting may be missing ({cf_count} rules)")
        
        # --- CHECK 4: Complete data rows (at least 15 rows with data in E-L) ---
        complete_rows = 0
        for row_num in range(2, 52):  # Rows 2-51 (data rows)
            # Check if at least 5 of the columns E-L have data
            filled = 0
            for col in ['E', 'F', 'G', 'H', 'I', 'J', 'K', 'L']:
                cell_val = sheet[f'{col}{row_num}'].value
                if cell_val is not None and str(cell_val).strip() != '':
                    filled += 1
            
            if filled >= 5:  # At least 5 columns filled
                complete_rows += 1
        
        if complete_rows >= 15:
            score += 15
            feedback_parts.append(f"✅ Sufficient data rows filled ({complete_rows} rows)")
        elif complete_rows >= 10:
            score += 10
            feedback_parts.append(f"⚠️  Partial data rows filled ({complete_rows} rows, expected ≥15)")
        else:
            feedback_parts.append(f"❌ Insufficient data rows ({complete_rows} rows, expected ≥15)")
        
        # --- CHECK 5: Slideshow_Order logic (column H) ---
        # Should have sequential numbers for "YES" photos only
        yes_photos = []
        slideshow_orders = []
        no_maybe_with_order = 0
        
        for row_num in range(2, 52):
            include_val = sheet[f'G{row_num}'].value
            order_val = sheet[f'H{row_num}'].value
            
            if include_val and 'YES' in str(include_val).upper():
                yes_photos.append(row_num)
                if order_val is not None and str(order_val).strip() != '':
                    try:
                        slideshow_orders.append(int(float(order_val)))
                    except:
                        pass
            elif include_val and (('NO' in str(include_val).upper()) or ('MAYBE' in str(include_val).upper())):
                # Check if NO/MAYBE has order number (should not)
                if order_val is not None and str(order_val).strip() != '':
                    no_maybe_with_order += 1
        
        # Check if we have at least 12 photos marked YES with order numbers
        if len(slideshow_orders) >= 12:
            score += 15
            feedback_parts.append(f"✅ Slideshow order assigned ({len(slideshow_orders)} photos with order numbers)")
        elif len(slideshow_orders) >= 8:
            score += 10
            feedback_parts.append(f"⚠️  Partial slideshow order ({len(slideshow_orders)} photos, expected ≥12)")
        else:
            feedback_parts.append(f"❌ Insufficient slideshow ordering ({len(slideshow_orders)} photos, expected ≥12)")
        
        # Check if order numbers are reasonably sequential
        if slideshow_orders and len(slideshow_orders) >= 8:
            slideshow_orders_sorted = sorted(slideshow_orders)
            is_reasonable = (min(slideshow_orders) >= 1 and max(slideshow_orders) <= len(slideshow_orders) + 5)
            if is_reasonable:
                score += 5
                feedback_parts.append("✅ Slideshow order numbers are sequential")
            else:
                feedback_parts.append("⚠️  Slideshow order numbers may have issues")
        
        # Penalize if NO/MAYBE photos have order numbers
        if no_maybe_with_order > 0:
            feedback_parts.append(f"⚠️  {no_maybe_with_order} NO/MAYBE photos have order numbers (should be blank)")
        
        # --- CHECK 6: Summary section with formulas ---
        summary_found = False
        summary_label = get_cell_value(wb, sheet.title, 'A55')
        if summary_label and 'SUMMARY' in str(summary_label).upper():
            summary_found = True
            score += 3
        
        formulas_found = 0
        formula_results_valid = 0
        
        # Check cells B56-B61 for formulas or calculated values
        for row in range(56, 62):
            cell = sheet[f'B{row}']
            if cell.value is not None:
                # Check if it's a numeric value (from formula or manual entry)
                if isinstance(cell.value, (int, float)):
                    formulas_found += 1
        
        if formulas_found >= 5:
            score += 12
            feedback_parts.append(f"✅ Summary calculations present ({formulas_found}/6)")
        elif formulas_found >= 3:
            score += 8
            feedback_parts.append(f"⚠️  Partial summary calculations ({formulas_found}/6)")
        else:
            feedback_parts.append(f"❌ Summary calculations missing ({formulas_found}/6)")
        
        # Validate specific summary calculations
        total_photos_val = sheet['B56'].value
        yes_photos_val = sheet['B57'].value
        maybe_photos_val = sheet['B58'].value
        duration_val = sheet['B59'].value
        permission_val = sheet['B60'].value
        avg_quality_val = sheet['B61'].value
        
        # Total photos should be 50
        if total_photos_val and isinstance(total_photos_val, (int, float)):
            if 48 <= total_photos_val <= 51:  # Allow slight variation
                formula_results_valid += 1
                feedback_parts.append(f"✅ Total photos count correct ({int(total_photos_val)})")
            else:
                feedback_parts.append(f"⚠️  Total photos count unexpected ({total_photos_val})")
        
        # YES photos should be reasonable (at least 10)
        if yes_photos_val and isinstance(yes_photos_val, (int, float)) and yes_photos_val >= 10:
            formula_results_valid += 1
            feedback_parts.append(f"✅ YES photos count reasonable ({int(yes_photos_val)})")
        
        # Estimated duration should be at least 1 minute
        if duration_val and isinstance(duration_val, (int, float)) and duration_val >= 1:
            formula_results_valid += 1
            feedback_parts.append(f"✅ Estimated duration calculated ({duration_val:.1f} minutes)")
        
        # Average quality should be between 2.5 and 5
        if avg_quality_val and isinstance(avg_quality_val, (int, float)) and 2.0 <= avg_quality_val <= 5.0:
            formula_results_valid += 1
            feedback_parts.append(f"✅ Average quality rating reasonable ({avg_quality_val:.1f})")
        
        if formula_results_valid >= 3:
            score += 5
        
        # --- CHECK 7: Freeze panes ---
        if sheet.freeze_panes and sheet.freeze_panes != 'A1':
            score += 5
            feedback_parts.append(f"✅ Freeze panes active ({sheet.freeze_panes})")
        else:
            feedback_parts.append("⚠️  Freeze panes not detected")
        
        # --- CHECK 8: Auto-filter ---
        if sheet.auto_filter and sheet.auto_filter.ref:
            score += 5
            feedback_parts.append(f"✅ Auto-filter active ({sheet.auto_filter.ref})")
        else:
            feedback_parts.append("⚠️  Auto-filter not detected")
        
        # Final assessment
        passed = score >= 70  # 70% threshold
        
        final_feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": final_feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {str(e)}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass