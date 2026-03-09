# Post-task export script for implant_site_assessment.
# Checks .bsp file existence/size/timestamp, checks for exported images,
# analyzes .bsp SQLite for measurement and annotation data.
# Writes a structured JSON result for the verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_implant_site_assessment.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting implant_site_assessment results ==="

    $taskDir = "C:\Users\Docker\Desktop\BlueSkyPlanTasks"
    $bspFile = "$taskDir\site_assessment.bsp"
    $imagesDir = "$taskDir\site_images"
    $resultFile = "$taskDir\site_assessment_result.json"
    $taskStartFile = "$taskDir\task_start.txt"

    # ---- Read task start timestamp ----
    $taskStartTime = 0
    if (Test-Path $taskStartFile) {
        $raw = (Get-Content $taskStartFile -Raw).Trim()
        try { $taskStartTime = [long]$raw } catch { $taskStartTime = 0 }
    }

    # ---- Check .bsp project file ----
    $bspExists = $false
    $bspSizeBytes = 0
    $bspSizeKB = 0
    $bspLastWriteUnix = 0
    $bspModifiedAfterStart = $false

    if (Test-Path $bspFile) {
        $bspExists = $true
        $fi = Get-Item $bspFile
        $bspSizeBytes = $fi.Length
        $bspSizeKB = [math]::Round($fi.Length / 1024, 2)
        $bspLastWriteUnix = [DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        if ($taskStartTime -gt 0 -and $bspLastWriteUnix -gt $taskStartTime) {
            $bspModifiedAfterStart = $true
        }
        Write-Host "BSP file: $bspFile ($bspSizeKB KB, modified=$bspModifiedAfterStart)"
    } else {
        Write-Host "BSP file NOT found: $bspFile"
    }

    # ---- Check exported cross-section images ----
    $imageFiles = @()
    $imageDetails = @()

    if (Test-Path $imagesDir) {
        # Accept PNG, JPG, JPEG, BMP, TIFF image formats
        $imageFiles = @(Get-ChildItem -Path $imagesDir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @(".png", ".jpg", ".jpeg", ".bmp", ".tiff", ".tif")
        })
        foreach ($img in $imageFiles) {
            $sizeKB = [math]::Round($img.Length / 1024, 2)
            $imageDetails += @{
                name = $img.Name
                size_kb = $sizeKB
                valid = ($sizeKB -gt 10)
            }
            Write-Host "  Image: $($img.Name) ($sizeKB KB)"
        }
    } else {
        Write-Host "Images directory NOT found: $imagesDir"
    }

    $validImageCount = 0
    if ($imageDetails.Count -gt 0) {
        $filtered = @($imageDetails | Where-Object { $_.valid -eq $true })
        $validImageCount = $filtered.Count
    }
    Write-Host "Valid images (>10 KB): $validImageCount"

    # ---- Analyze .bsp SQLite for measurement and annotation data ----
    $isSqlite = $false
    $tableNames = @()
    $hasAnnotationData = $false
    $annotationRecordCount = 0
    $hasMeasurementData = $false
    $measurementRecordCount = 0
    $sqliteError = $null

    if ($bspExists -and $bspSizeBytes -gt 0) {
        try {
            $pythonScript = @"
import sqlite3, json, sys

bsp_path = r'$bspFile'
result = {
    'is_sqlite': False,
    'table_names': [],
    'has_annotation_data': False,
    'annotation_record_count': 0,
    'has_measurement_data': False,
    'measurement_record_count': 0,
    'table_details': {}
}

try:
    conn = sqlite3.connect(bsp_path)
    cursor = conn.cursor()

    # Get all table names
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [row[0] for row in cursor.fetchall()]
    result['is_sqlite'] = True
    result['table_names'] = tables

    # ---- Look for annotation/marker/fiducial data ----
    annotation_keywords = [
        'annot', 'markup', 'marker', 'point', 'landmark', 'label',
        'note', 'nerve', 'canal', 'foramen', 'fiducial', 'drawing',
        'pin', 'flag', 'tag'
    ]
    annotation_tables_found = []
    total_annotation_rows = 0

    for t in tables:
        t_lower = t.lower()
        name_match = any(kw in t_lower for kw in annotation_keywords)
        col_match = False

        if not name_match:
            try:
                cursor.execute(f"PRAGMA table_info([{t}])")
                cols = ' '.join(c[1].lower() for c in cursor.fetchall())
                col_match = any(kw in cols for kw in annotation_keywords)
            except:
                pass

        if name_match or col_match:
            try:
                cursor.execute(f'SELECT COUNT(*) FROM [{t}]')
                count = cursor.fetchone()[0]
                if count > 0:
                    annotation_tables_found.append(t)
                    total_annotation_rows += count
                    result['table_details'][t] = {
                        'type': 'annotation',
                        'match': 'name' if name_match else 'column',
                        'rows': count
                    }
            except:
                pass

    if annotation_tables_found:
        result['has_annotation_data'] = True
        result['annotation_record_count'] = total_annotation_rows

    # ---- Look for measurement/distance data ----
    measurement_keywords = [
        'measure', 'distance', 'ruler', 'line', 'dimension',
        'length', 'width', 'height', 'metric', 'caliper'
    ]
    measurement_tables_found = []
    total_measurement_rows = 0

    for t in tables:
        t_lower = t.lower()
        name_match = any(kw in t_lower for kw in measurement_keywords)
        col_match = False

        if not name_match:
            try:
                cursor.execute(f"PRAGMA table_info([{t}])")
                cols = ' '.join(c[1].lower() for c in cursor.fetchall())
                col_match = any(kw in cols for kw in measurement_keywords)
            except:
                pass

        if name_match or col_match:
            try:
                cursor.execute(f'SELECT COUNT(*) FROM [{t}]')
                count = cursor.fetchone()[0]
                if count > 0:
                    measurement_tables_found.append(t)
                    total_measurement_rows += count
                    result['table_details'][t] = {
                        'type': 'measurement',
                        'match': 'name' if name_match else 'column',
                        'rows': count
                    }
            except:
                pass

    if measurement_tables_found:
        result['has_measurement_data'] = True
        result['measurement_record_count'] = total_measurement_rows

    # ---- Fallback: check generic data tables ----
    if not annotation_tables_found or not measurement_tables_found:
        generic_keywords = ['object', 'data', 'item', 'entity', 'element']
        for t in tables:
            t_lower = t.lower()
            if any(kw in t_lower for kw in generic_keywords):
                try:
                    cursor.execute(f'SELECT COUNT(*) FROM [{t}]')
                    count = cursor.fetchone()[0]
                    if count > 0:
                        cursor.execute(f'PRAGMA table_info([{t}])')
                        cols = [c[1].lower() for c in cursor.fetchall()]
                        col_str = ' '.join(cols)

                        if not result['has_annotation_data']:
                            if any(k in col_str for k in ['coord', 'position', 'x_pos', 'y_pos', 'point']):
                                result['has_annotation_data'] = True
                                result['annotation_record_count'] += count
                                result['table_details'][t] = {
                                    'type': 'annotation_inferred',
                                    'rows': count
                                }

                        if not result['has_measurement_data']:
                            if any(k in col_str for k in ['distance', 'length', 'value', 'measure', 'start', 'end']):
                                result['has_measurement_data'] = True
                                result['measurement_record_count'] += count
                                result['table_details'][t] = {
                                    'type': 'measurement_inferred',
                                    'rows': count
                                }
                except:
                    pass

    conn.close()
except sqlite3.DatabaseError as e:
    result['is_sqlite'] = False
    result['error'] = f'Not a valid SQLite file: {str(e)}'
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
"@
            $pythonResult = python3 -c $pythonScript 2>&1
            if ($LASTEXITCODE -ne 0) {
                $pythonResult = python -c $pythonScript 2>&1
            }

            if ($pythonResult) {
                $parsed = $pythonResult | ConvertFrom-Json
                $isSqlite = $parsed.is_sqlite
                $tableNames = $parsed.table_names
                $hasAnnotationData = $parsed.has_annotation_data
                $annotationRecordCount = $parsed.annotation_record_count
                $hasMeasurementData = $parsed.has_measurement_data
                $measurementRecordCount = $parsed.measurement_record_count
                if ($parsed.error) { $sqliteError = $parsed.error }

                Write-Host "SQLite analysis:"
                Write-Host "  Is SQLite: $isSqlite"
                Write-Host "  Tables: $($tableNames -join ', ')"
                Write-Host "  Annotation data: $hasAnnotationData ($annotationRecordCount records)"
                Write-Host "  Measurement data: $hasMeasurementData ($measurementRecordCount records)"
            }
        } catch {
            Write-Host "WARNING: SQLite analysis failed: $($_.Exception.Message)"
            $sqliteError = "SQLite analysis failed: $($_.Exception.Message)"

            # Fallback: check file header for SQLite magic bytes
            try {
                $bytes = [System.IO.File]::ReadAllBytes($bspFile)
                $header = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(16, $bytes.Length))
                if ($header.StartsWith("SQLite format 3")) {
                    $isSqlite = $true
                    Write-Host "File has SQLite header (detailed analysis unavailable)"
                }
            } catch {
                Write-Host "WARNING: Could not read file header"
            }
        }
    }

    # ---- Build result JSON ----
    $result = @{
        task_start_unix         = $taskStartTime
        export_timestamp        = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        bsp_exists              = $bspExists
        bsp_size_bytes          = $bspSizeBytes
        bsp_size_kb             = $bspSizeKB
        bsp_last_write_unix     = $bspLastWriteUnix
        bsp_modified_after_start = $bspModifiedAfterStart
        images_dir_exists       = (Test-Path $imagesDir)
        total_image_count       = $imageFiles.Count
        valid_image_count       = $validImageCount
        image_files             = $imageDetails
        is_sqlite               = $isSqlite
        table_names             = $tableNames
        has_annotation_data     = $hasAnnotationData
        annotation_record_count = $annotationRecordCount
        has_measurement_data    = $hasMeasurementData
        measurement_record_count = $measurementRecordCount
        sqlite_error            = $sqliteError
    }

    $resultJsonStr = $result | ConvertTo-Json -Depth 5
    $resultJsonStr | Out-File -FilePath $resultFile -Encoding utf8 -Force
    Write-Host "Result JSON written to: $resultFile"

    Write-Host "=== implant_site_assessment export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
