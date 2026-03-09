# ==========================================================================
# create_ecoli_classic.ps1 - Create EColi_classic Epi Info 7 project
#
# MUST be run with 32-bit PowerShell for Jet OLEDB 4.0 access:
# C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
#
# Creates TWO things:
#   1. EColi_classic.mdb - flat Access table for Classic Analysis tasks
#      (pure OLEDB, no Epi Info API needed)
#   2. EColi_classic.prj - Epi Info project for Enter module tasks
#      (uses Epi Info .NET API with working directory initialization fix)
# ==========================================================================

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$LOG = "C:\Users\Docker\create_ecoli_classic.log"
try { Start-Transcript -Path $LOG -Force | Out-Null } catch {}

$ECO_DIR  = "C:\EpiInfo7\Projects\EColi"
$SRC_MDB  = "C:\EpiInfo7\Projects\EColi\EColi.mdb"
$PROJ_DIR = "C:\EpiInfo7\Projects\EColi\EColi_classic"
$PROJ_MDB = "$PROJ_DIR\EColi_classic.mdb"
$PROJ_PRJ = "$PROJ_DIR\EColi_classic.prj"
$CONFIG_PATH = "C:\EpiInfo7\Configuration\EpiInfo.Config.xml"

Write-Host "=== create_ecoli_classic.ps1 starting ==="

# -----------------------------------------------------------------------
# PART 1: Create EColi_classic directory and flat MDB (pure OLEDB)
#         This is needed for Classic Analysis tasks (READ command).
#         Does NOT require any Epi Info .NET API.
# -----------------------------------------------------------------------
Write-Host "--- Part 1: Creating EColi_classic directory and MDB ---"

if (-not (Test-Path $PROJ_DIR)) {
    New-Item -ItemType Directory -Path $PROJ_DIR -Force | Out-Null
    Write-Host "Created directory: $PROJ_DIR"
}

# Create EColi_classic.mdb using ADOX COM if it doesn't exist
if (-not (Test-Path $PROJ_MDB)) {
    try {
        $adox = New-Object -ComObject ADOX.Catalog
        $adox.Create("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=$PROJ_MDB")
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($adox) | Out-Null
        Write-Host "Created empty MDB: $PROJ_MDB"
    } catch {
        Write-Host "ADOX failed ($($_.Exception.Message)), trying OLEDB create..."
        # Fallback: OLEDB will auto-create the file when we execute DDL
    }
}

# Open connection to EColi_classic.mdb (creates it if needed via OLEDB)
$conn = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=$PROJ_MDB;Jet OLEDB:Engine Type=5")
$conn.Open()
Write-Host "Opened connection to EColi_classic.mdb"

# Create FoodHistory flat data table (for Classic Analysis READ command)
$createTableSQL = @"
CREATE TABLE FoodHistory (
    [UniqueKey]      COUNTER PRIMARY KEY,
    [RecStatus]      SHORT DEFAULT 1,
    [GlobalRecordId] TEXT(255),
    [FKEY]           TEXT(255),
    [RECNUM]         DOUBLE,
    [SEX]            TEXT(1),
    [AGENUM]         DOUBLE,
    [ILLDUM]         SHORT,
    [ONSETDATE]      DATETIME,
    [HAMBURGER]      TEXT(1)
)
"@
$cmdCreate = $conn.CreateCommand()
$cmdCreate.CommandText = $createTableSQL
try {
    $cmdCreate.ExecuteNonQuery() | Out-Null
    Write-Host "FoodHistory data table created"
} catch {
    Write-Host "FoodHistory table may already exist: $($_.Exception.Message)"
}

# Import data from original EColi.mdb
if (Test-Path $SRC_MDB) {
    # Check if already has data
    $cntCmd = $conn.CreateCommand()
    $cntCmd.CommandText = "SELECT COUNT(*) FROM FoodHistory"
    $existing = $cntCmd.ExecuteScalar()

    if ($existing -eq 0) {
        $insertSQL = @"
INSERT INTO FoodHistory ([RecStatus],[GlobalRecordId],[RECNUM],[SEX],[AGENUM],[ILLDUM],[ONSETDATE],[HAMBURGER])
SELECT 1                           AS [RecStatus],
       [fh].[GlobalRecordId],
       [fh1].[CaseID]             AS [RECNUM],
       Left([fh1].[Sex],1)        AS [SEX],
       [fh1].[Age]                AS [AGENUM],
       [fh1].[ILL]                AS [ILLDUM],
       [fh1].[OnsetDate]          AS [ONSETDATE],
       IIF([fh2].[Beefjerkey]=1 OR [fh2].[Beefjerkey]=-1, 'Y', 'N') AS [HAMBURGER]
FROM  ([FoodHistory] AS fh
       INNER JOIN [FoodHistory1] AS fh1 ON [fh].[GlobalRecordId]=[fh1].[GlobalRecordId])
       LEFT  JOIN [FoodHistory2] AS fh2 ON [fh].[GlobalRecordId]=[fh2].[GlobalRecordId]
IN '$SRC_MDB'
WHERE [fh1].[ILL] IS NOT NULL
"@
        $cmdInsert = $conn.CreateCommand()
        $cmdInsert.CommandText = $insertSQL
        try {
            $cnt = $cmdInsert.ExecuteNonQuery()
            Write-Host "Inserted $cnt rows from original EColi.mdb"
        } catch {
            Write-Host "Import error: $($_.Exception.Message)"
        }
    } else {
        Write-Host "FoodHistory already has $existing rows, skipping import"
    }
} else {
    Write-Host "WARNING: Source EColi.mdb not found at $SRC_MDB"
}

# Report row count
$cntCmd2 = $conn.CreateCommand()
$cntCmd2.CommandText = "SELECT COUNT(*) FROM FoodHistory"
$total = $cntCmd2.ExecuteScalar()
Write-Host "Total rows in FoodHistory: $total"
$conn.Close()
Write-Host "Part 1 complete: EColi_classic.mdb ready with $total FoodHistory rows"

# -----------------------------------------------------------------------
# PART 2: Create EColi_classic Epi Info project (.prj + metadata tables)
#         Needed for Enter module (enter_case_record task).
#         Uses Epi Info .NET API with working directory initialization.
# -----------------------------------------------------------------------
Write-Host "--- Part 2: Creating EColi_classic.prj for Enter module ---"

if (Test-Path $PROJ_PRJ) {
    Write-Host "EColi_classic.prj already exists, skipping Part 2"
} else {
    # Ensure EpiInfo working directory exists (required by Configuration.Load)
    $epiDocsDir = [System.IO.Path]::Combine(
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments),
        "EpiInfo7")
    if (-not (Test-Path $epiDocsDir)) {
        New-Item -ItemType Directory -Path $epiDocsDir -Force | Out-Null
        Write-Host "Created EpiInfo docs dir: $epiDocsDir"
    }

    # Set working directory to Epi Info 7 installation
    Push-Location "C:\EpiInfo7"
    Write-Host "Working dir set to C:\EpiInfo7"

    try {
        # Load Epi Info DLLs (must be done from C:\EpiInfo7 context)
        Add-Type -Path "C:\EpiInfo7\Epi.Core.dll" -ErrorAction Stop
        Add-Type -Path "C:\EpiInfo7\Epi.Data.Office.dll" -ErrorAction SilentlyContinue
        Add-Type -Path "C:\EpiInfo7\EpiInfo.Plugin.dll" -ErrorAction SilentlyContinue
        Write-Host "Epi Info DLLs loaded"

        # Compile C# helper that creates the project
        Add-Type -ReferencedAssemblies @(
            "C:\EpiInfo7\Epi.Core.dll",
            "C:\EpiInfo7\EpiInfo.Plugin.dll",
            "System.Data.dll",
            "System.Xml.dll"
        ) -TypeDefinition @'
using System;
using Epi;
using Epi.Data;

public static class EpiProjectCreator {
    private static Epi.Page _page;

    public static void CreateClassicProject(string configPath, string location, string mdbPath) {
        // Ensure the EpiInfo documents directory exists
        string docsDir = System.IO.Path.Combine(
            System.Environment.GetFolderPath(System.Environment.SpecialFolder.MyDocuments),
            "EpiInfo7");
        System.IO.Directory.CreateDirectory(docsDir);

        // Set working directory to Epi Info 7 installation directory
        System.IO.Directory.SetCurrentDirectory(@"C:\EpiInfo7\");

        // Load configuration
        Configuration.Load(configPath);

        // Verify configuration loaded
        var cfg = Configuration.GetInstance();
        if (cfg == null) throw new Exception("Configuration.GetInstance() is null after Load");

        // Set up database driver info for Access MDB
        var ddi = new DbDriverInfo();
        var cb = new System.Data.OleDb.OleDbConnectionStringBuilder();
        cb["Provider"] = "Microsoft.Jet.OLEDB.4.0";
        cb["Data Source"] = mdbPath;
        ddi.DBCnnStringBuilder = cb;
        ddi.DBName = "EColi_classic";

        // Create the project (creates .prj and populates metadata tables in MDB)
        var proj = new Project();
        var created = proj.CreateProject(
            "EColi_classic",
            "E. coli classic outbreak investigation dataset (ILLDUM HAMBURGER AGENUM SEX ONSETDATE RECNUM)",
            location,
            "Epi.Data.Office.AccessDBFactory, Epi.Data.Office",
            ddi);

        // Create FoodHistory view with a single flat page
        var view = created.CreateView("FoodHistory");
        _page = view.CreatePage("Page 1", 0);

        // Add fields with integer positions (0-100 scale, API handles conversion)
        AddNum("RECNUM",     "Record Number (RECNUM)",      5);
        AddText("SEX",       "Sex (SEX): M or F",          15, 1);
        AddNum("AGENUM",     "Age (AGENUM)",               25);
        AddYesNo("ILLDUM",   "Ill? (ILLDUM)",              35);
        AddDate("ONSETDATE", "Onset Date (ONSETDATE)",     45);
        AddYesNo("HAMBURGER","Beef product (HAMBURGER)",   55);

        created.Save();
    }

    private static void AddNum(string n, string p, int t) {
        var f = new Epi.Fields.NumberField(_page);
        f.Name=n; f.PromptText=p;
        f.ControlTopPositionPercentage=t; f.ControlLeftPositionPercentage=30;
        f.ControlHeightPercentage=4; f.ControlWidthPercentage=20;
        f.PromptTopPositionPercentage=t; f.PromptLeftPositionPercentage=1;
        f.HasTabStop=true; f.SaveToDb();
    }
    private static void AddText(string n, string p, int t, int maxLen) {
        var f = new Epi.Fields.SingleLineTextField(_page);
        f.Name=n; f.PromptText=p; f.MaxLength=maxLen;
        f.ControlTopPositionPercentage=t; f.ControlLeftPositionPercentage=30;
        f.ControlHeightPercentage=4; f.ControlWidthPercentage=10;
        f.PromptTopPositionPercentage=t; f.PromptLeftPositionPercentage=1;
        f.HasTabStop=true; f.SaveToDb();
    }
    private static void AddDate(string n, string p, int t) {
        var f = new Epi.Fields.DateField(_page);
        f.Name=n; f.PromptText=p;
        f.ControlTopPositionPercentage=t; f.ControlLeftPositionPercentage=30;
        f.ControlHeightPercentage=4; f.ControlWidthPercentage=20;
        f.PromptTopPositionPercentage=t; f.PromptLeftPositionPercentage=1;
        f.HasTabStop=true; f.SaveToDb();
    }
    private static void AddYesNo(string n, string p, int t) {
        var f = new Epi.Fields.YesNoField(_page);
        f.Name=n; f.PromptText=p;
        f.ControlTopPositionPercentage=t; f.ControlLeftPositionPercentage=30;
        f.ControlHeightPercentage=4; f.ControlWidthPercentage=10;
        f.PromptTopPositionPercentage=t; f.PromptLeftPositionPercentage=1;
        f.HasTabStop=true; f.SaveToDb();
    }
}
'@
        Write-Host "C# helper compiled"

        # Create the project (this writes .prj file and populates metadata in MDB)
        [EpiProjectCreator]::CreateClassicProject($CONFIG_PATH, ($ECO_DIR + "\"), $PROJ_MDB)
        Write-Host "Epi Info project created"

        if (Test-Path $PROJ_PRJ) {
            Write-Host "Verified: EColi_classic.prj exists"

            # Open the MDB to fix metadata issues that the API introduces:
            # 1. PageId in metaFields may use transient object IDs instead of DB IDs
            # 2. Control positions use integer scale (0-100) but Epi Info needs 0.0-1.0
            $conn2 = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.Jet.OLEDB.4.0;Data Source=$PROJ_MDB;")
            $conn2.Open()

            # Fix DataTableName
            $updCmd = $conn2.CreateCommand()
            $updCmd.CommandText = "UPDATE metaFields SET DataTableName='FoodHistory' WHERE DataTableName IS NULL OR DataTableName=''"
            $n = $updCmd.ExecuteNonQuery()
            Write-Host "Updated $n metaFields.DataTableName"

            # Fix PageId: use actual DB-assigned PageId from metaPages
            $vCmd = $conn2.CreateCommand()
            $vCmd.CommandText = "SELECT TOP 1 ViewId FROM metaViews WHERE Name='FoodHistory'"
            $vId = $vCmd.ExecuteScalar()
            $pCmd = $conn2.CreateCommand()
            $pCmd.CommandText = "SELECT TOP 1 PageId FROM metaPages WHERE ViewId=$vId ORDER BY PageId"
            $pId = $pCmd.ExecuteScalar()
            Write-Host "FoodHistory ViewId=$vId PageId=$pId"
            $pfCmd = $conn2.CreateCommand()
            $pfCmd.CommandText = "UPDATE metaFields SET PageId=$pId WHERE Name IN ('RECNUM','SEX','AGENUM','ILLDUM','ONSETDATE','HAMBURGER')"
            $nPf = $pfCmd.ExecuteNonQuery()
            Write-Host "Fixed PageId=$pId for $nPf metaFields rows"

            # Fix control positions to decimal fractions (0.0-1.0 range)
            $posData = @(
                @{Name="RECNUM";    CTop=0.05; CLeft=0.30; CH=0.06; CW=0.20; PTop=0.05; PLeft=0.01},
                @{Name="SEX";       CTop=0.15; CLeft=0.30; CH=0.06; CW=0.10; PTop=0.15; PLeft=0.01},
                @{Name="AGENUM";    CTop=0.25; CLeft=0.30; CH=0.06; CW=0.20; PTop=0.25; PLeft=0.01},
                @{Name="ILLDUM";    CTop=0.35; CLeft=0.30; CH=0.06; CW=0.10; PTop=0.35; PLeft=0.01},
                @{Name="ONSETDATE"; CTop=0.45; CLeft=0.30; CH=0.06; CW=0.20; PTop=0.45; PLeft=0.01},
                @{Name="HAMBURGER"; CTop=0.55; CLeft=0.30; CH=0.06; CW=0.10; PTop=0.55; PLeft=0.01}
            )
            foreach ($f in $posData) {
                $posCmd = $conn2.CreateCommand()
                $posCmd.CommandText = "UPDATE metaFields SET ControlTopPositionPercentage=$($f.CTop),ControlLeftPositionPercentage=$($f.CLeft),ControlHeightPercentage=$($f.CH),ControlWidthPercentage=$($f.CW),PromptTopPositionPercentage=$($f.PTop),PromptLeftPositionPercentage=$($f.PLeft) WHERE Name='$($f.Name)'"
                $nPos = $posCmd.ExecuteNonQuery()
                Write-Host "Set positions for $($f.Name): $nPos rows"
            }

            $conn2.Close()
            Write-Host "Metadata fixes applied to EColi_classic.mdb"
        } else {
            Write-Host "WARNING: EColi_classic.prj was NOT created by the API"
            Write-Host "Available files in ${PROJ_DIR}:"
            Get-ChildItem $PROJ_DIR -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
        }

    } catch {
        Write-Host "Part 2 ERROR: $($_.Exception.Message)"
        Write-Host "Stack trace: $($_.ScriptStackTrace)"
        Write-Host "Note: EColi_classic.mdb flat table (Part 1) is still available for Classic Analysis tasks."
        Write-Host "      The enter_case_record task may need to use the original EColi project."
    } finally {
        Pop-Location
    }
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== create_ecoli_classic.ps1 complete ==="
Write-Host "  MDB (for Classic Analysis): $(if(Test-Path $PROJ_MDB){'OK'}else{'MISSING'}) - $PROJ_MDB"
Write-Host "  PRJ (for Enter module):     $(if(Test-Path $PROJ_PRJ){'OK'}else{'MISSING (see log above)'}) - $PROJ_PRJ"

try { Stop-Transcript | Out-Null } catch {}
