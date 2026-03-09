# MS SQL Server Environment - Evidence Documentation

## Environment Overview

This environment provides Microsoft SQL Server 2022 running in a Docker container with Azure Data Studio as the GUI management tool.

### Components
- **SQL Server 2022** (Developer Edition) - Running in Docker container
- **Azure Data Studio** - GUI database management tool (installed via Snap)
- **AdventureWorks2022** - Sample database for testing
- **mssql-tools18** - Command-line SQL tools (sqlcmd)

### Connection Details
- Server: `localhost,1433`
- Username: `sa`
- Password: `GymAnything#2024`
- Default Database: `AdventureWorks2022`

## Screenshots

### 01_connected_to_sql_server.png
Shows Azure Data Studio successfully connected to SQL Server with:
- Version: 16.0.4236.2 (Developer Edition 64-bit)
- OS: Ubuntu 22.04
- Database Size chart showing AdventureWorks2022
- Backup Status panel

### 02_desktop_initial.png
Initial Ubuntu desktop state with Azure Data Studio desktop shortcut visible.

### 03_query_execution_results.png
Query execution demonstrating the environment works:
- Query: SELECT TOP 5 products from Production.Product ordered by price
- Results showing Road-150 Red bikes at $3578.27

### 04_query_editor.png
Azure Data Studio query editor with SQL syntax highlighting.

### 05_csv_exported.png
CSV export confirmation showing the saved file with all 10 products:
- top_products.csv file saved to /home/ga/Documents/exports/
- Shows ProductName,TotalQuantitySold header and 10 data rows

### 06_top10_products_query.png
The actual task query results showing top 10 best-selling products:
1. AWC Logo Cap - 8311
2. Water Bottle - 30 oz. - 6815
3. Sport-100 Helmet, Blue - 6743
4. Long-Sleeve Logo Jersey, L - 6592
5. Sport-100 Helmet, Black - 6532
6. Sport-100 Helmet, Red - 6266
7. Classic Vest, S - 4247
8. Patch Kit/8 Patches - 3865
9. Short-Sleeve Classic Jersey, XL - 3864
10. Long-Sleeve Logo Jersey, M - 3636

### 07_task_start_state.png
Shows the **correct task start state** with:
- Azure Data Studio connected to localhost SQL Server
- Title bar: "SQLQuery_1 - (63) localhost.AdventureWorks2022 (sa)"
- Database dropdown showing "AdventureWorks2022"
- Empty query editor ready for SQL input
- Status bar confirming connection
- This is the state AFTER setup_task.sh runs successfully via Command Palette approach

### 08_query_typed.png
Shows the SQL query typed in the Azure Data Studio query editor:
- SELECT TOP 10 query with JOINs visible
- Proper syntax highlighting
- Ready for execution

### 09_query_results.png
Connection dialog during task execution (demonstrating the connection workflow).

### 11_connected_adventureworks2022.png
Shows ADS successfully connected to AdventureWorks2022:
- Title bar: "SQLQuery_3 - (57) localhost.AdventureWorks2022 (sa)"
- Database dropdown: "AdventureWorks2022"
- Status bar: "localhost : AdventureWorks2022 (57)"

### 12_correct_task_start_state.png
Shows the **verified correct task start state** after setup_task.sh improvements:
- Title bar: "SQLQuery_1 - (52) localhost.AdventureWorks2022 (sa)"
- ADS connected (shows "Disconnect" button, not "Connect")
- Database: AdventureWorks2022
- Query editor: Empty and ready for agent input
- No dialogs blocking the interface

### 13_verified_correct_task_start_state.png
Shows the **final verified task start state** after fourth iteration improvements:
- Title bar: "SQLQuery_1 - (63) localhost.AdventureWorks2022 (sa)"
- ADS connected via Command Palette approach
- Database: AdventureWorks2022 (verified in both toolbar dropdown and status bar)
- Query editor: Empty and ready for agent input
- Interface fully clean with no blocking dialogs

### 14_definitive_task_start_state.png
Shows the **definitive task start state** after all fixes (fifth iteration):
- Title bar: "SQLQuery_1 - (54) localhost.AdventureWorks2022 (sa)"
- ADS fully connected via Command Palette approach with retry logic
- Database: AdventureWorks2022 (visible in toolbar dropdown AND status bar)
- Query editor: Empty, cursor at line 1, ready for SQL input
- No dialogs blocking the interface
- This screenshot matches what the artifact `frame_00000.png` should show

## Log Outputs

### Setup Script Output (setup_mssql.sh)
```
=== Setting up Microsoft SQL Server 2022 ===
Creating Docker Compose configuration...
Starting SQL Server Docker container...
mssql-server ... done
Container starting...
Waiting for SQL Server to be ready...
SQL Server is ready after 5s
Downloading AdventureWorks2022 sample database...
Restoring AdventureWorks2022 database...
RESTORE DATABASE successfully processed 25378 pages in 0.313 seconds (633.424 MB/sec).
AdventureWorks2022 database restored successfully!
  Products: 504
  People: 19972
Configuring Azure Data Studio...
Launching Azure Data Studio...
Azure Data Studio window detected after 4s
=== Microsoft SQL Server Setup Complete ===
SQL Server is running at: localhost:1433
```

### Task Export Script Output (export_result.sh)
```
=== Exporting task result ===
Validating with database query...
Result saved to /tmp/query_result.json
{
    "mssql_running": true,
    "ads_running": true,
    "output_file_exists": true,
    "output_row_count": 10,
    "output_has_headers": true,
    "correct_row_count": true,
    "known_products_found": 5,
    "correct_top_product": true,
    "actual_top_product": "AWC Logo Cap",
    "products_found": "AWC Logo Cap;Water Bottle - 30 oz.;Sport-100 Helmet;Long-Sleeve Logo Jersey;Sport-100 Helmet",
    "timestamp": "2026-02-02T17:33:35+00:00"
}
=== Export complete ===
```

### Exported CSV Contents
```csv
ProductName,TotalQuantitySold
AWC Logo Cap,8311
Water Bottle - 30 oz.,6815
"Sport-100 Helmet, Blue",6743
"Long-Sleeve Logo Jersey, L",6592
"Sport-100 Helmet, Black",6532
"Sport-100 Helmet, Red",6266
"Classic Vest, S",4247
Patch Kit/8 Patches,3865
"Short-Sleeve Classic Jersey, XL",3864
"Long-Sleeve Logo Jersey, M",3636
```

## Verification Checklist

- [x] Installation script completes without errors
- [x] SQL Server container starts and is healthy
- [x] AdventureWorks2022 database restored (504 products, 121317 sales orders)
- [x] Azure Data Studio launches and is visible
- [x] Connection to SQL Server successful
- [x] Queries execute and return correct results
- [x] CSV export functionality works
- [x] Export script produces valid JSON
- [x] Verifier correctly validates task completion

## Key Learnings

### Installation Notes
1. **Azure Data Studio**: Direct download URLs from Microsoft are unreliable. Using Snap (`snap install azuredatastudio`) is more reliable.

2. **Docker Compose healthcheck**: The healthcheck format needs `CMD-SHELL` prefix:
   ```yaml
   healthcheck:
     test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'password' -C -Q 'SELECT 1' || exit 1"]
   ```

3. **Trust Server Certificate**: When connecting from Azure Data Studio, set "Trust server certificate" to True for local connections.

4. **SQL Server startup time**: SQL Server may take 30-60 seconds to fully initialize after container starts.

5. **CSV Export in ADS**: Right-click on results grid → "Save As CSV" saves with headers by default.

### Interactive Testing Notes
- Used `ask_cua.py` for coordinate guidance on 1280x720 → scaled to 1920x1080
- xdotool commands: `mousemove`, `click`, `type`, `key` for GUI automation
- Important to wait after clicks for UI to update

### Task Verification Pattern
Tasks use the standard gym_anything verification pattern:
1. `setup_task.sh` - Prepares initial state, records baseline counts
2. Agent performs task interactively
3. `export_result.sh` - Exports verification data to `/tmp/query_result.json`
4. `verifier.py` - Uses `copy_from_env()` to read results and verify

### Useful Commands
```bash
# Query via command line
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'GymAnything#2024' -C -Q "SELECT @@VERSION"

# List databases
mssql-databases

# Run custom query
mssql-query "SELECT TOP 10 * FROM Production.Product"

# Check container logs
docker-compose -f /home/ga/mssql/docker-compose.yml logs -f
```

## Audit Fixes Applied

### CRITICAL: Task Start State (Fixed - Fourth Iteration)
**Issue**: Previous fix used toolbar "Connect" button which didn't reliably open the Connection Details panel in ADS.

**Fix**: Completely rewrote connection automation using Command Palette approach:
1. Launch ADS and maximize window
2. Dismiss startup dialogs (keyring and Preview features)
3. Open Command Palette (F1), type "new connection", press Enter
4. Fill connection fields using VLM-verified coordinates (1280x720 → 1920x1080):
   - Server field: 1160,460 → 1740,690 (value: localhost)
   - User name field: 1160,503 → 1740,755 (value: sa)
   - Password field: 1160,523 → 1740,785 (value: GymAnything#2024)
   - Trust server certificate: 1160,603 → 1740,905 (set to True)
5. Click Connect button: 1180,699 → 1770,1049
6. Wait for connection (check title for "localhost.*Azure")
7. Open new query with Command Palette → "new query"
8. Change database dropdown (370,92 → 555,138) to AdventureWorks2022 (first item: 345,107 → 518,161)
9. Clear query editor with Ctrl+A Delete
10. Take screenshot showing connected state

**Evidence**: Screenshot `13_verified_correct_task_start_state.png` shows ADS connected to localhost.AdventureWorks2022

### MODERATE: Substring Matching in Validation (Fixed)
**Issue**: Product validation used `grep -qi "$product"` which could match partial strings.

**Fix**: Updated export_result.sh to:
1. Extract only the product name column (first field) for validation
2. Use case-insensitive exact matching instead of substring matching
3. Validate against full product names (e.g., "Water Bottle - 30 oz." not just "Water Bottle")

### CRITICAL: Backup Validation Exit Code Bug (Fixed)
**Issue**: In backup_database/export_result.sh, the `$?` on line 55 checked the exit code of the previous `grep` command, not `mssql_query_raw`.

**Fix**: Store the exit code immediately after `mssql_query_raw`:
```bash
VERIFY_RESULT=$(mssql_query_raw "RESTORE VERIFYONLY FROM DISK = '$BACKUP_PATH'" 2>&1)
QUERY_EXIT_CODE=$?  # Store immediately
```

### HIGH: ADS Startup Dialogs (Fixed)
**Issue**: Azure Data Studio shows OS keyring dialog and Preview features dialog on startup.

**Fix**: Added dialog dismissal logic to all setup_task.sh scripts:
```bash
# Dismiss OS keyring dialog
DISPLAY=:1 xdotool key Tab Tab Return
sleep 1
# Dismiss Preview features dialog
DISPLAY=:1 xdotool key Escape
```

### MODERATE: Column Data Type Validation (Added)
**Issue**: create_customer_orders_view verifier only checked column names, not data types.

**Fix**: Added data type validation to export_result.sh:
- CustomerID must be int
- TotalOrders must be int
- TotalAmount must be money/decimal/numeric
- LastOrderDate must be date/datetime

### MODERATE: SQL Hints Too Verbose (Fixed)
**Issue**: SQL hints in task.json gave complete solutions, allowing agents to copy-paste.

**Fix**: Reduced hints to guidance only:
- `query_product_sales`: "Hint: JOIN tables. Use SUM() for quantities..."
- `create_customer_orders_view`: "Hint: JOIN tables via PersonID/BusinessEntityID..."
- `backup_database`: "Hint: Use BACKUP DATABASE with TO DISK clause..."

### MODERATE: Verifier Gaming Vectors (Fixed)
**Issue**: Agents could hardcode fake CSV values that pass validation.

**Fix**: Added database value validation to export_result.sh:
- Query database for actual top 10 products with quantities
- Cross-validate CSV values against database
- Require at least 3/10 quantity values to match
- Added `values_validated` and `values_match_count` to verifier scoring

### Setup Script Verification (Added)
**Issue**: No explicit verification that ADS connection succeeded.

**Fix**: Added connection verification to all setup_task.sh scripts:
- Extended connection wait loop to 15 seconds
- Retry connection at 8s if still disconnected
- Log window title for debugging
- Save connection state to `/tmp/ads_connection_state.txt`
- Final verification check before screenshot

## Known Limitations

### Hardcoded Screen Coordinates
The setup_task.sh scripts use hardcoded screen coordinates scaled from 1280x720 to 1920x1080 for GUI automation. These coordinates are specific to the current ADS version and screen resolution. If the resolution changes, coordinates will need to be re-verified using ask_cua.py or similar VLM coordinate detection.

Current coordinate mapping (1280x720 → 1920x1080):
- Connection panel Server field: 1160,460 → 1740,690
- User name field: 1160,503 → 1740,755
- Password field: 1160,523 → 1740,785
- Trust server certificate: 1160,603 → 1740,905
- Connect button: 1180,699 → 1770,1049
- Database dropdown: 370,92 → 555,138
- AdventureWorks2022 option: 345,107 → 518,161

### VLM Verification Dependency
VLM visual verification is optional but recommended. If VLM is unavailable, the verifier continues with database-based validation only. Feedback will indicate when VLM verification was skipped.

### AdventureWorks Database Familiarity
AdventureWorks2022 is Microsoft's official sample database, widely used in SQL Server training and documentation. LLM agents may have significant prior exposure to:
- AdventureWorks schema structure
- Common query patterns against AdventureWorks tables
- Standard JOIN relationships between tables

**Implications for evaluation:**
- Results should be interpreted with awareness that agents may have prior AdventureWorks knowledge
- This tests practical SQL execution more than pure SQL design ability
- For tasks requiring novel database exploration, consider using less common datasets

### Resolution Dependency
The environment is configured for 1920x1080 resolution. The setup scripts use hardcoded pixel coordinates that are specific to this resolution. Running on different resolutions may cause:
- Connection automation failures
- Incorrect button clicks
- Database dropdown selection failures

**Required resolution:** 1920x1080 (configured in env.json)

## Date Tested
February 2, 2026

## Environment Version
ms_sql_server_env@0.1
