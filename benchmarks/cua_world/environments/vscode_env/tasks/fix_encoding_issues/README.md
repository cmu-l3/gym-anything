# Fix Encoding Issues Task

**Difficulty**: 🟡 Medium  
**Skills**: File encoding, line endings, internationalization, VSCode settings  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Fix file encoding and line ending issues in a dataset from international partners. Convert files from Windows-1252/ISO-8859-1 to UTF-8 and change CRLF line endings to LF to match project standards.

## Scenario

Your colleague in Germany sent you a dataset archive, but several files display garbled characters - "José" shows as "José" or "JosÃ©", "café" shows as "cafÃ©", and names like "Müller" appear corrupted. Additionally, Git shows several files as modified even though you haven't changed them - they have Windows (CRLF) line endings instead of the project's Unix (LF) standard.

## Expected Workflow

1. Open workspace and notice garbled characters
2. Check `.editorconfig` to understand project standards (UTF-8, LF)
3. For encoding issues:
   - Click on encoding indicator in status bar (bottom-right)
   - Select "Reopen with Encoding"
   - Choose correct source encoding (Windows-1252 or ISO-8859-1)
   - Verify characters display correctly
   - Click encoding again, select "Save with Encoding" → "UTF-8"
4. For line ending issues:
   - Click on "CRLF" in status bar
   - Select "LF"
   - Save file (Ctrl+S)
5. Repeat for all affected files

## Files to Fix

### Encoding Issues (Windows-1252/ISO-8859-1 → UTF-8):
- `data/customers.csv` - Contains: José, François, Müller, Søren
- `data/locations.txt` - Contains: São Paulo, Malmö, Zürich, Montréal
- `docs/glossary.txt` - Contains: naïve, café, résumé, façade

### Line Ending Issues (CRLF → LF):
- `README.md`
- `docs/notes.md`
- `scripts/validate.sh`

### Control Files (should remain unchanged):
- `data/products.json`
- `scripts/process.py`

## Verification

Checks for:
1. All files converted to UTF-8 encoding
2. Special characters (José, café, Müller, etc.) display correctly
3. All text files have LF line endings (no CRLF)
4. Control files remain unchanged

**Pass Threshold**: 90% (9/10 criteria)