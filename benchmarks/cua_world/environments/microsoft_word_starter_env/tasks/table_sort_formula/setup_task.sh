# Note: In the Windows environment, this is actually setup_task.ps1
# The extension .sh is used here for syntax highlighting compatibility with the prompt requirement,
# but the content is PowerShell.

$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Table Sort & Formula Task ==="

# 1. Record Start Time
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File -FilePath "C:\Users\Docker\task_start_time.txt" -Encoding ascii

# 2. Prepare Data Directory
$docPath = "C:\Users\Docker\Documents\quarterly_expenses.docx"
Remove-Item -Path $docPath -Force -ErrorAction SilentlyContinue

# 3. Create the Document using Word COM Object (Ensures clean state)
Write-Host "Creating fresh expense document..."
$word = New-Object -ComObject Word.Application
$word.Visible = $true
$word.DisplayAlerts = 0 # wdAlertsNone

# Create new doc
$doc = $word.Documents.Add()
$selection = $word.Selection

# Add Title
$selection.ParagraphFormat.Alignment = 1 # Center
$selection.Font.Size = 16
$selection.Font.Bold = 1
$selection.TypeText("Q3 2024 Departmental Expense Report")
$selection.TypeParagraph()
$selection.Font.Size = 12
$selection.Font.Bold = 0
$selection.TypeText("Administrative Services Division")
$selection.TypeParagraph()
$selection.TypeParagraph()
$selection.ParagraphFormat.Alignment = 0 # Left

# Add Table (12 rows, 5 columns)
$range = $selection.Range
$table = $doc.Tables.Add($range, 12, 5)
$table.Borders.Enable = 1

# Helper to set cell text
function Set-Cell($row, $col, $text) {
    $table.Cell($row, $col).Range.Text = $text
}

# Header Row
Set-Cell 1 1 "Expense Category"
Set-Cell 1 2 "October"
Set-Cell 1 3 "November"
Set-Cell 1 4 "December"
Set-Cell 1 5 "Q3 Total"
$table.Rows.Item(1).Range.Font.Bold = 1
$table.Rows.Item(1).Shading.BackgroundPatternColor = -603914241 # Light Gray

# Data Rows (Unsorted)
# Format: Category, Oct, Nov, Dec, Total (calculated manually for setup)
$data = @(
    @("Travel & Lodging", "5,670.00", "3,450.25", "4,890.50", "14,010.75"),
    @("Office Supplies", "2,340.50", "1,890.75", "3,120.00", "7,351.25"),
    @("Contracted Services", "12,000.00", "12,000.00", "15,000.00", "39,000.00"),
    @("Telecommunications", "3,200.00", "3,200.00", "3,200.00", "9,600.00"),
    @("Software Licenses", "8,900.00", "8,900.00", "8,900.00", "26,700.00"),
    @("Utilities", "4,500.00", "4,800.00", "5,200.00", "14,500.00"),
    @("Equipment Maintenance", "950.00", "1,200.00", "2,800.00", "4,950.00"),
    @("Miscellaneous", "450.00", "890.50", "1,670.00", "3,010.50"),
    @("Training & Development", "1,500.00", "2,750.00", "4,200.00", "8,450.00"),
    @("Printing & Copying", "780.50", "620.30", "1,450.75", "2,851.55")
)

for ($i = 0; $i -lt $data.Count; $i++) {
    $rowIdx = $i + 2
    Set-Cell $rowIdx 1 $data[$i][0]
    Set-Cell $rowIdx 2 $data[$i][1]
    Set-Cell $rowIdx 3 $data[$i][2]
    Set-Cell $rowIdx 4 $data[$i][3]
    Set-Cell $rowIdx 5 $data[$i][4]
}

# Total Row
Set-Cell 12 1 "TOTAL"
# Leave other cells empty for the agent to fill

# Save Document
$doc.SaveAs([ref]$docPath)
Write-Host "Document saved to $docPath"

# 4. Window Management
# Ensure Word is maximized and focused
$wsh = New-Object -ComObject WScript.Shell
$wsh.AppActivate("Word")
Start-Sleep -Seconds 1
# Maximize (Alt+Space, x)
$wsh.SendKeys("% n") 
Start-Sleep -Seconds 1
$word.ActiveWindow.WindowState = 1 # wdWindowStateMaximize

Write-Host "=== Setup Complete ==="