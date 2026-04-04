# Configure Custom File Viewer Task

**Difficulty**: 🟡 Medium  
**Skills**: Extension management, file associations, configuration, database viewing  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure VSCode to view SQLite database files by installing an appropriate extension and extracting information from a test database.

## Scenario

Your QA team sent you a `.sqlite` database file containing test data related to a production bug. You need to:
1. Install an SQLite viewer extension (search marketplace for "SQLite")
2. Open and view the `test_data.sqlite` file
3. Extract specific information from the `users` table
4. Fill in the investigation notes

## Expected Workflow

1. Open Extensions view (Ctrl+Shift+X) or Command Palette
2. Search for "SQLite" viewer extension
3. Install an appropriate extension (e.g., "SQLite" by alexcvzz, "SQLite Viewer" by qwtel, or similar)
4. Wait for installation to complete
5. Open `test_data.sqlite` file from workspace
6. Navigate to `users` table
7. Find alice's user_id, bob's user_id, and count total users
8. Update `investigation_notes.txt` with findings
9. Save the notes file

## Verification

Checks for:
1. SQLite viewer extension installed (40%)
2. File associations configured (optional, 20%)
3. Investigation notes filled with correct data (40%)

**Pass Threshold**: 70% (at least extension + correct notes)