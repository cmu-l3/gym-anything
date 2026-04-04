# Fix File Encoding Issue Task

**Difficulty**: 🟡 Medium  
**Skills**: File encoding, problem diagnosis, VSCode settings, internationalization  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Fix a file encoding issue in a Python script that was created on Windows with Windows-1252 encoding. The file contains French accented characters that appear garbled when opened with default UTF-8 encoding. Reopen the file with the correct encoding and save it as UTF-8.

## Background

This task simulates a common real-world scenario in cross-platform development: a colleague on Windows sends you a file with accented characters (French: é, à, è, ç, ô), but when you open it on Linux with UTF-8 encoding (the default), these characters appear garbled as `Ã©`, `Ã¨`, `Ã `, etc.

## Expected Workflow

1. Open file `/home/ga/workspace/encoding_project/analyze_data.py` in VSCode
2. Notice that French characters appear garbled (e.g., "données" appears as "donnÃ©es")
3. Click on the encoding indicator in the status bar (bottom-right corner, shows "UTF-8")
4. Select "Reopen with Encoding"
5. Choose "Western (Windows 1252)" or "Western (ISO 8859-1)"
6. Verify that French characters now display correctly
7. Click on the encoding indicator again
8. Select "Save with Encoding"
9. Choose "UTF-8"
10. Save the file (Ctrl+S)

## Verification

Checks for:
1. File is now in UTF-8 encoding (detected via chardet)
2. French accented characters are correctly preserved (données, été, météo, etc.)
3. No garbled character patterns remain (Ã©, Ã¨, Ã , etc.)
4. File structure and code remain intact

**Pass Threshold**: All criteria must pass (encoding issues are binary - either fixed or not)