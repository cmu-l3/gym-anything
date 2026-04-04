# Fix Resource Leaks Task

**Difficulty**: 🟡 Medium  
**Skills**: Code analysis, Python resource management, multi-file refactoring, VSCode navigation  
**Duration**: 240 seconds  
**Steps**: ~60

## Objective

Investigate and fix resource leaks in a Python Flask application by identifying patterns where files, database connections, and network resources are opened but never properly closed, then refactor the code to use proper resource management (context managers or explicit cleanup).

## Scenario

You're maintaining a Flask REST API that processes uploaded files and interacts with a PostgreSQL database. The ops team reports that after running for several hours, the application's memory usage climbs steadily and eventually gets OOM-killed. They've also noticed warnings about "too many open files" in the logs. You need to audit the codebase for resource leaks and fix them.

## Expected Workflow

1. Open the workspace at `/home/ga/workspace/flask_api/`
2. Use Find in Files (Ctrl+Shift+F) to search for resource acquisition patterns:
   - `open(`
   - `requests.get(`
   - `psycopg2.connect(`
3. Navigate to each occurrence and analyze if resource is properly closed
4. Refactor to use `with` statements (context managers) or add explicit `.close()` in `finally` blocks
5. Save all modified files (Ctrl+K S)

## Files to Investigate

- **app.py** - Main Flask application (file logging leak)
- **db.py** - Database connection handling (connection leak in error path)
- **file_processor.py** - File upload processing (temporary file leak)
- **report_generator.py** - PDF report generation (HTTP response leak)
- **backup.py** - Backup utility script (multiple file leaks in loop)

## Verification

Checks for proper resource management in each file:
1. ✅ app.py leak fixed (file opened without cleanup)
2. ✅ db.py leak fixed (connection not closed in error path)
3. ✅ file_processor.py leak fixed (temporary file not closed)
4. ✅ report_generator.py leak fixed (HTTP response not consumed)
5. ✅ backup.py leak fixed (files in loop not closed)

**Pass Threshold**: 80% (4 out of 5 leaks fixed)

## Resource Management Patterns

### Good Pattern (Context Manager):