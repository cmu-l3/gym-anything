#!/usr/bin/env python3
"""
Verifier for Vinyl Collection Tracker task
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
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vinyl_collection_tracker(traj, env_info, task_info):
    """
    Verify the vinyl collection tracker spreadsheet.
    
    Checks:
    1. File exists and can be parsed
    2. Has appropriate column headers (flexible matching)
    3. Contains at least 8-10 data rows with content
    4. Prices are numeric values
    5. Formulas exist for Profit/Loss calculations
    6. Formulas exist for ROI% calculations
    7. Summary section exists with key metrics
    8. Formatting is applied (bold headers, currency, percentage)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/vinyl_collection.xlsx"
    
    # Use tempfile for copying
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy file from container
        try:
            copy_from_env(container_path, temp_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ File not found or cannot be copied: {container_path}"
            }
        
        # Check file exists and has content
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            os.unlink(temp_path)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File is empty or doesn't exist"
            }
        
        score = 0
        feedback_parts = []
        
        # File exists
        score += 5
        feedback_parts.append("✅ File exists (5 pts)")
        
        # Parse workbook
        wb = parse_xlsx_file(temp_path)
        if not wb:
            os.unlink(temp_path)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ Failed to parse XLSX"
            }
        
        # Get the first sheet (flexible - don't require specific name)
        sheet_name = wb.sheetnames[0]
        sheet = wb[sheet_name]
        
        # Check if it's named "Collection Tracker" (bonus points)
        if "collection" in sheet_name.lower() and "track" in sheet_name.lower():
            score += 5
            feedback_parts.append(f"✅ Sheet named '{sheet_name}' (5 pts)")
        else:
            score += 2
            feedback_parts.append(f"⚠️ Sheet named '{sheet_name}' (2/5 pts)")
        
        # Get all data
        data = get_sheet_data(wb, sheet_name, max_rows=50, max_cols=15)
        
        if len(data) == 0:
            os.unlink(temp_path)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ Sheet is empty"
            }
        
        # Check for column headers (row 1)
        # Required concepts: album/title, artist, date, source, price, condition, value, profit/loss, roi
        header_row = [str(cell).lower() if cell else '' for cell in data[0]]
        
        required_concepts = {
            'album': ['album', 'title', 'record'],
            'artist': ['artist', 'musician', 'performer'],
            'date': ['date', 'purchased', 'bought'],
            'source': ['source', 'store', 'from', 'where'],
            'price': ['price', 'paid', 'cost', 'purchase price'],
            'condition': ['condition', 'grade', 'quality'],
            'value': ['value', 'current', 'worth', 'market'],
            'profit': ['profit', 'loss', 'gain', 'difference'],
            'roi': ['roi', '%', 'return', 'percent']
        }
        
        concepts_found = {}
        for concept, keywords in required_concepts.items():
            concepts_found[concept] = -1  # -1 means not found
            for idx, header in enumerate(header_row):
                if any(kw in header for kw in keywords):
                    concepts_found[concept] = idx
                    break
        
        headers_found = sum(1 for idx in concepts_found.values() if idx >= 0)
        
        if headers_found >= 7:
            score += 5
            feedback_parts.append(f"✅ Found {headers_found}/9 required column concepts (5 pts)")
        elif headers_found >= 5:
            score += 3
            feedback_parts.append(f"⚠️ Found {headers_found}/9 column concepts (3/5 pts)")
        else:
            score += 0
            feedback_parts.append(f"❌ Only found {headers_found}/9 column concepts (0/5 pts)")
        
        # Check number of data rows (should be at least 10 for all records)
        data_rows = []
        for row_idx, row in enumerate(data[1:], start=1):
            # Consider a row as data if it has at least 3 non-empty cells
            non_empty = sum(1 for cell in row if cell)
            if non_empty >= 3:
                data_rows.append((row_idx, row))
        
        num_records = len(data_rows)
        
        if num_records >= 10:
            score += 5
            feedback_parts.append(f"✅ Contains {num_records} record rows (5 pts)")
        elif num_records >= 8:
            score += 3
            feedback_parts.append(f"⚠️ Contains {num_records} record rows, expected 10 (3/5 pts)")
        elif num_records >= 5:
            score += 1
            feedback_parts.append(f"⚠️ Only {num_records} record rows found (1/5 pts)")
        else:
            score += 0
            feedback_parts.append(f"❌ Only {num_records} record rows found (0/5 pts)")
        
        # Data quality: Check if purchase prices are numeric
        price_col_idx = concepts_found.get('price', -1)
        
        if price_col_idx >= 0 and num_records > 0:
            numeric_prices = 0
            for _, row in data_rows[:10]:
                if price_col_idx < len(row):
                    cell_val = row[price_col_idx]
                    if isinstance(cell_val, (int, float)) and cell_val > 0:
                        numeric_prices += 1
            
            if numeric_prices >= 8:
                score += 10
                feedback_parts.append(f"✅ {numeric_prices} records have valid numeric prices (10 pts)")
            elif numeric_prices >= 6:
                score += 6
                feedback_parts.append(f"⚠️ {numeric_prices} records have valid prices (6/10 pts)")
            elif numeric_prices >= 4:
                score += 3
                feedback_parts.append(f"⚠️ Only {numeric_prices} records have valid prices (3/10 pts)")
            else:
                feedback_parts.append(f"❌ Only {numeric_prices} records have valid prices (0/10 pts)")
        else:
            feedback_parts.append("❌ Could not verify price data (0/10 pts)")
        
        # Check dates are present
        date_col_idx = concepts_found.get('date', -1)
        
        if date_col_idx >= 0 and num_records > 0:
            dates_present = 0
            for _, row in data_rows[:10]:
                if date_col_idx < len(row):
                    cell_val = row[date_col_idx]
                    if cell_val:  # Any non-empty value counts
                        dates_present += 1
            
            if dates_present >= 8:
                score += 5
                feedback_parts.append(f"✅ {dates_present} records have dates (5 pts)")
            elif dates_present >= 6:
                score += 3
                feedback_parts.append(f"⚠️ {dates_present} records have dates (3/5 pts)")
            else:
                feedback_parts.append(f"❌ Only {dates_present} records have dates (0/5 pts)")
        else:
            feedback_parts.append("❌ Could not verify dates (0/5 pts)")
        
        # Check for Profit/Loss calculations
        profit_col_idx = concepts_found.get('profit', -1)
        
        if profit_col_idx >= 0 and num_records > 0:
            profit_calcs = 0
            for row_idx, row in data_rows[:10]:
                if profit_col_idx < len(row):
                    cell_val = row[profit_col_idx]
                    # Check if it's a numeric value (could be formula result)
                    if isinstance(cell_val, (int, float)):
                        profit_calcs += 1
                    # Also check the actual cell for formula
                    actual_row = row_idx + 1  # Convert to 1-based
                    cell = sheet.cell(row=actual_row, column=profit_col_idx + 1)
                    if cell.value is not None and isinstance(cell.value, (int, float)):
                        profit_calcs = max(profit_calcs, profit_calcs)  # Ensure we count it
            
            if profit_calcs >= 8:
                score += 10
                feedback_parts.append(f"✅ Profit/Loss calculated for {profit_calcs} records (10 pts)")
            elif profit_calcs >= 6:
                score += 6
                feedback_parts.append(f"⚠️ Profit/Loss calculated for {profit_calcs} records (6/10 pts)")
            elif profit_calcs >= 4:
                score += 3
                feedback_parts.append(f"⚠️ Profit/Loss for {profit_calcs} records (3/10 pts)")
            else:
                feedback_parts.append(f"❌ Profit/Loss only for {profit_calcs} records (0/10 pts)")
        else:
            feedback_parts.append("❌ No Profit/Loss column found (0/10 pts)")
        
        # Check for ROI% calculations
        roi_col_idx = concepts_found.get('roi', -1)
        
        if roi_col_idx >= 0 and num_records > 0:
            roi_calcs = 0
            for row_idx, row in data_rows[:10]:
                if roi_col_idx < len(row):
                    cell_val = row[roi_col_idx]
                    if isinstance(cell_val, (int, float)):
                        roi_calcs += 1
            
            if roi_calcs >= 8:
                score += 15
                feedback_parts.append(f"✅ ROI % calculated for {roi_calcs} records (15 pts)")
            elif roi_calcs >= 6:
                score += 9
                feedback_parts.append(f"⚠️ ROI % calculated for {roi_calcs} records (9/15 pts)")
            elif roi_calcs >= 4:
                score += 5
                feedback_parts.append(f"⚠️ ROI % for {roi_calcs} records (5/15 pts)")
            else:
                feedback_parts.append(f"❌ ROI % only for {roi_calcs} records (0/15 pts)")
        else:
            feedback_parts.append("❌ No ROI % column found (0/15 pts)")
        
        # Check for summary section (look in rows below main data)
        summary_start_row = max(12, len(data_rows) + 2)  # Start looking after data
        summary_found = 0
        summary_keywords = {
            'total invested': ['total', 'invest'],
            'current value': ['current', 'value', 'collection'],
            'profit/loss': ['profit', 'loss', 'overall', 'gain'],
            'average roi': ['average', 'roi', 'avg', 'mean']
        }
        
        # Search through potential summary rows
        for row_idx in range(summary_start_row, min(summary_start_row + 15, len(data))):
            if row_idx < len(data):
                row = data[row_idx]
                row_text = ' '.join([str(cell).lower() for cell in row if cell])
                
                # Check if this row contains summary labels
                for summary_type, keywords in summary_keywords.items():
                    if all(kw in row_text for kw in keywords):
                        summary_found += 1
                        break  # Only count once per row
        
        # Also check for actual summary values (numbers in summary area)
        summary_values = 0
        for row_idx in range(summary_start_row, min(summary_start_row + 15, len(data))):
            if row_idx < len(data):
                row = data[row_idx]
                for cell in row:
                    if isinstance(cell, (int, float)) and cell > 0:
                        summary_values += 1
                        break  # Only count once per row
        
        summary_score = min(summary_found * 5, 20)
        
        if summary_found >= 3 or summary_values >= 3:
            score += summary_score
            feedback_parts.append(f"✅ Summary section found with {max(summary_found, summary_values)} metrics ({summary_score} pts)")
        elif summary_found >= 2 or summary_values >= 2:
            partial_score = min(summary_found * 4, 10)
            score += partial_score
            feedback_parts.append(f"⚠️ Partial summary section ({partial_score}/20 pts)")
        else:
            feedback_parts.append("❌ Summary section missing or incomplete (0/20 pts)")
        
        # Check formatting: Header row bold
        try:
            header_cell = sheet.cell(row=1, column=1)
            if header_cell.font and header_cell.font.bold:
                score += 3
                feedback_parts.append("✅ Header row is bold (3 pts)")
            else:
                feedback_parts.append("⚠️ Header row not bold (0/3 pts)")
        except:
            feedback_parts.append("⚠️ Could not check header formatting (0/3 pts)")
        
        # Check currency formatting on price columns
        currency_formatted = False
        if price_col_idx >= 0:
            try:
                # Check a data cell in the price column
                price_cell = sheet.cell(row=2, column=price_col_idx + 1)
                if price_cell.number_format:
                    fmt = price_cell.number_format.lower()
                    if '$' in fmt or 'currency' in fmt or '"$"' in fmt:
                        currency_formatted = True
            except:
                pass
        
        # Also check current value column
        value_col_idx = concepts_found.get('value', -1)
        if value_col_idx >= 0 and not currency_formatted:
            try:
                value_cell = sheet.cell(row=2, column=value_col_idx + 1)
                if value_cell.number_format:
                    fmt = value_cell.number_format.lower()
                    if '$' in fmt or 'currency' in fmt or '"$"' in fmt:
                        currency_formatted = True
            except:
                pass
        
        if currency_formatted:
            score += 4
            feedback_parts.append("✅ Currency formatting applied (4 pts)")
        else:
            feedback_parts.append("⚠️ Currency formatting not detected (0/4 pts)")
        
        # Check percentage formatting for ROI
        if roi_col_idx >= 0:
            try:
                roi_cell = sheet.cell(row=2, column=roi_col_idx + 1)
                if roi_cell.number_format and '%' in roi_cell.number_format:
                    score += 3
                    feedback_parts.append("✅ Percentage formatting for ROI (3 pts)")
                else:
                    feedback_parts.append("⚠️ Percentage formatting not detected (0/3 pts)")
            except:
                feedback_parts.append("⚠️ Could not check ROI formatting (0/3 pts)")
        else:
            feedback_parts.append("⚠️ No ROI column for formatting check (0/3 pts)")
        
        # Organization bonus (always give some points for having structured data)
        if num_records >= 8:
            score += 5
            feedback_parts.append("✅ Data is well organized (5 pts)")
        else:
            score += 2
            feedback_parts.append("⚠️ Data organization could be better (2/5 pts)")
        
        # Verify some actual vinyl data is present (sanity check)
        # Look for artist names or album titles that match the input
        all_text = ' '.join([' '.join([str(c) for c in row if c]) for row in data])
        vinyl_references = 0
        vinyl_names = ['miles davis', 'coltrane', 'monk', 'evans', 'mingus', 
                      'hancock', 'brubeck', 'rollins', 'adderley', 'blakey',
                      'kind of blue', 'love supreme', 'brilliant corners']
        
        for name in vinyl_names:
            if name in all_text.lower():
                vinyl_references += 1
        
        if vinyl_references >= 5:
            # Bonus points for accuracy
            score += 5
            feedback_parts.append(f"✅ Actual vinyl data entered correctly (5 bonus pts)")
        elif vinyl_references >= 3:
            score += 2
            feedback_parts.append(f"⚠️ Some vinyl data found (2 bonus pts)")
        
        # Clean up
        os.unlink(temp_path)
        
        # Determine pass/fail
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": min(score, 100),  # Cap at 100
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return {
            "passed": False,
            "score": score if 'score' in locals() else 0,
            "feedback": " | ".join(feedback_parts) + f" | ❌ Verification error: {str(e)}" if 'feedback_parts' in locals() else f"❌ Verification error: {str(e)}"
        }