# ONLYOFFICE Desktop Editors Environment

This environment provides a complete ONLYOFFICE Desktop Editors setup for document editing, spreadsheet analysis, and presentation creation tasks with full Microsoft Office compatibility.

## Features

- **Document Editor**: Create and format text documents (DOCX, ODT)
- **Spreadsheet Editor**: Create formulas, charts, and analyze data (XLSX, ODS)
- **Presentation Editor**: Create and edit presentations (PPTX, ODP)
- **High Compatibility**: Full support for Microsoft Office formats
- **Robust Setup**: 6GB RAM allocation for stability (prevents crashes)
- **Comprehensive Verification**: Python-based verification for all document types

## Resource Allocation

- **CPU**: 4 cores
- **Memory**: 6GB (increased from standard 4GB to prevent crashes)
- **GPU**: Not required
- **Network**: Enabled

## Environment Structure

```
onlyoffice_env/
├── env.json                 # Environment configuration
├── scripts/
│   ├── install_onlyoffice.sh   # Installation script
│   ├── setup_onlyoffice.sh     # Post-install configuration
│   └── task_utils.sh           # Shared utilities for tasks
├── config/                  # Configuration files (if needed)
├── tasks/                   # Task definitions
│   ├── format_document/        # Document formatting task
│   ├── create_formula/         # Spreadsheet formula task
│   └── create_presentation/    # Presentation creation task
└── utils/
    └── onlyoffice_verification_utils.py  # Verification utilities
```

## Example Tasks

### 1. Format Document (Easy)
**Task**: Apply text formatting (bold, italic, headings) to a document
**Skills tested**:
- Text selection
- Applying bold/italic formatting
- Using heading styles
- Saving documents

**File**: `tasks/format_document/`

### 2. Create Formula (Medium)
**Task**: Create spreadsheet formulas for calculations
**Skills tested**:
- Understanding cell references
- Creating SUM, AVERAGE, MAX formulas
- Working with data ranges
- Verifying formula results

**File**: `tasks/create_formula/`

### 3. Create Presentation (Easy)
**Task**: Create a multi-slide presentation with content
**Skills tested**:
- Adding new slides
- Entering titles and content
- Creating bullet point lists
- Managing multiple slides

**File**: `tasks/create_presentation/`

## Installation

The environment installs:
1. ONLYOFFICE Desktop Editors (latest version)
2. Python document parsing libraries (python-docx, openpyxl, python-pptx)
3. LibreOffice (as fallback for format conversions)
4. GUI automation tools (xdotool, wmctrl)
5. Microsoft-compatible fonts

## Configuration

### User Setup
- Main user: `ga` with password `password123`
- Display: `:1`
- VNC port: `5954`

### Directories Created
- `/home/ga/Documents/TextDocuments/` - For document files
- `/home/ga/Documents/Spreadsheets/` - For spreadsheet files
- `/home/ga/Documents/Presentations/` - For presentation files
- `/home/ga/Desktop/` - Desktop shortcuts for all three editors

### Launch Scripts
- `~/launch_document.sh <file>` - Launch Document Editor
- `~/launch_spreadsheet.sh <file>` - Launch Spreadsheet Editor
- `~/launch_presentation.sh <file>` - Launch Presentation Editor

## Utilities

### Command-line Tools
- `onlyoffice-convert <input> <format>` - Convert documents between formats

### Verification Functions

The `onlyoffice_verification_utils.py` module provides:

**Document Functions:**
- `parse_docx_file()` - Parse DOCX files
- `get_document_text()` - Extract all text
- `check_text_formatting()` - Verify bold, italic, underline, font size
- `check_paragraph_alignment()` - Verify alignment (left, center, right, justify)

**Spreadsheet Functions:**
- `parse_xlsx_file()` - Parse XLSX files
- `get_cell_value()` - Get value from specific cell
- `verify_formula()` - Check formula results
- `get_sheet_data()` - Extract all data as 2D array

**Presentation Functions:**
- `parse_pptx_file()` - Parse PPTX files
- `count_slides()` - Count number of slides
- `get_slide_text()` - Extract text from specific slide
- `check_slide_has_image()` - Check for images

**Generic Functions:**
- `copy_and_parse_document()` - Copy and parse any supported format
- `cleanup_temp_dir()` - Clean up temporary files

## Task Development Guide

### Creating a New Task

1. **Create task directory**:
   ```bash
   mkdir -p tasks/my_task
   ```

2. **Create task.json**:
   ```json
   {
     "id": "my_task@1",
     "version": "1.0",
     "env_id": "onlyoffice_env@0.1",
     "description": "Task description",
     "difficulty": "easy|medium|hard",
     "init": {
       "timeout_sec": 180,
       "max_steps": 25,
       "reward_type": "sparse"
     },
     "hooks": {
       "pre_task": "/workspace/tasks/my_task/setup_task.sh",
       "post_task": "/workspace/tasks/my_task/export_result.sh"
     },
     "success": {
       "mode": "program",
       "spec": {
         "program": "verifier.py::verify_my_task"
       }
     }
   }
   ```

3. **Create setup_task.sh**:
   - Kill existing ONLYOFFICE instances
   - Create initial document/spreadsheet/presentation
   - Launch ONLYOFFICE with the file
   - Wait for window to appear
   - Focus the window

4. **Create export_result.sh**:
   - Save the document (Ctrl+S)
   - Close ONLYOFFICE
   - Verify file exists

5. **Create verifier.py**:
   - Import verification utilities
   - Copy file from container
   - Parse document
   - Verify criteria
   - Return result dict with passed/score/feedback

### Best Practices

1. **Always kill existing ONLYOFFICE instances** in setup_task.sh:
   ```bash
   kill_onlyoffice ga
   sleep 1
   ```

2. **Use task utilities** for common operations:
   ```bash
   source /workspace/scripts/task_utils.sh
   wait_for_window "ONLYOFFICE" 30
   focus_onlyoffice_window
   save_document ga :1
   ```

3. **Proper error handling** in verifiers:
   ```python
   try:
       success, doc, error = copy_and_parse_document(path, copy_fn, 'docx')
       if not success:
           return {"passed": False, "score": 0, "feedback": error}
       # verification logic
   except Exception as e:
       return {"passed": False, "score": 0, "feedback": str(e)}
   finally:
       cleanup_temp_dir(temp_dir)
   ```

4. **Clear feedback messages**:
   ```python
   feedback_parts = []
   feedback_parts.append("✅ Criterion passed")
   feedback_parts.append("❌ Criterion failed: reason")
   feedback = " | ".join(feedback_parts)
   ```

## Troubleshooting

### ONLYOFFICE Won't Start
- Check log file: `/tmp/onlyoffice_*_task.log`
- Verify process: `pgrep -f onlyoffice-desktopeditors`
- Check window: `wmctrl -l | grep -i onlyoffice`

### Memory Issues/Crashes
- Environment is configured with 6GB RAM to prevent crashes
- If still experiencing issues, consider reducing concurrent operations
- Check system memory: `free -h`

### Document Not Saving
- Ensure Ctrl+S is being sent correctly
- Check file permissions in target directory
- Verify file exists after export: `ls -l /home/ga/Documents/...`

### Verification Failures
- Enable debug logging: `logging.basicConfig(level=logging.DEBUG)`
- Check if document was actually saved
- Verify Python libraries are installed: `pip3 list | grep -E "docx|openpyxl|pptx"`

## License

ONLYOFFICE Desktop Editors is licensed under AGPL-3.0

## Links

- ONLYOFFICE Website: https://www.onlyoffice.com/
- Documentation: https://helpcenter.onlyoffice.com/
- GitHub: https://github.com/ONLYOFFICE/DesktopEditors
