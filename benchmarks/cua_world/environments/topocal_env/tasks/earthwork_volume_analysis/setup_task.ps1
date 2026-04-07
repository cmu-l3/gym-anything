###############################################################################
# setup_task.ps1 — pre_task hook for earthwork_volume_analysis
# Downloads 200 real USGS NED 10m elevation points for Jefferson County, CO,
# converts to UTM Zone 13N, writes project CSV and spec, launches TopoCal.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_earthwork_volume_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up earthwork_volume_analysis task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Remove pre-existing output files ──
    Write-Host "[1/6] Cleaning up stale output files..."
    Remove-Item "C:\Users\Docker\Desktop\JeffersonCountyProject\volume_report.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\earthwork_volume_analysis_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\earthwork_va_ref_plane.txt" -Force -ErrorAction SilentlyContinue

    # ── 2. Record task start timestamp (AFTER cleanup) ──
    Write-Host "[2/6] Recording task start timestamp..."
    (Get-Date).ToString("o") | Set-Content -Path "C:\Users\Docker\earthwork_va_start.txt" -Encoding utf8

    # ── 3. Infrastructure ──
    Write-Host "[3/6] Starting infrastructure..."
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    # Create project directory
    $projDir = "C:\Users\Docker\Desktop\JeffersonCountyProject"
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    # Write Python data-download script
    $pyPath = "C:\Users\Docker\download_jefferson_survey.py"
    @'
import json, math, time, sys, urllib.request, os

def latlon_to_utm13n(lat, lon):
    """Convert WGS84 lat/lon to UTM Zone 13N (EPSG:26913)."""
    a = 6378137.0; f = 1/298.257223563; b = a*(1-f); e2 = 1-(b/a)**2
    k0 = 0.9996; lr = math.radians(lat); nr = math.radians(lon); l0 = math.radians(-105)
    N = a / math.sqrt(1 - e2*math.sin(lr)**2)
    T = math.tan(lr)**2; C = e2/(1-e2)*math.cos(lr)**2; A = math.cos(lr)*(nr-l0)
    M = a*((1-e2/4-3*e2**2/64-5*e2**3/256)*lr
           -(3*e2/8+3*e2**2/32+45*e2**3/1024)*math.sin(2*lr)
           +(15*e2**2/256+45*e2**3/1024)*math.sin(4*lr)
           -(35*e2**3/3072)*math.sin(6*lr))
    E = k0*N*(A+(1-T+C)*A**3/6+(5-18*T+T**2+72*C-58*e2/(1-e2))*A**5/120)+500000
    Nv = k0*(M+N*math.tan(lr)*(A**2/2+(5-T+9*C+4*C**2)*A**4/24
             +(61-58*T+T**2+600*C-330*e2/(1-e2))*A**6/720))
    return round(E, 3), round(Nv, 3)

# Two 10x10 grids covering the Jefferson County road corridor
# Grid 1: 39.720-39.729N, 105.250-105.259W
grid1 = [(39.720+i*0.001, -105.250-j*0.001) for i in range(10) for j in range(10)]
# Grid 2: 39.730-39.739N, 105.260-105.269W
grid2 = [(39.730+i*0.001, -105.260-j*0.001) for i in range(10) for j in range(10)]

points = []
pt_num = 1

for grid_idx, grid in enumerate([grid1, grid2], 1):
    locs = "|".join(f"{lat},{lon}" for lat, lon in grid)
    url = f"https://api.opentopodata.org/v1/ned10m?locations={locs}"
    print(f"Fetching grid {grid_idx}/2 from OpenTopoData...", flush=True)
    success = False
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TopoCal-Gym/1.0"})
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read())
            if data.get("status") == "OK":
                for r, (lat, lon) in zip(data["results"], grid):
                    elev = r.get("elevation") or 0.0
                    if elev is None or elev <= 0:
                        # Fallback elevation if API returns null
                        elev = 1800.0 + (lat - 39.72) * 3000 + (lon + 105.25) * 1500
                    E, Nv = latlon_to_utm13n(lat, lon)
                    points.append((pt_num, E, Nv, round(float(elev), 3), "TOPO"))
                    pt_num += 1
                success = True
                break
        except Exception as exc:
            print(f"  Attempt {attempt+1} failed: {exc}", flush=True)
            time.sleep(2)
    if not success:
        # Synthetic fallback so setup never blocks the task
        print(f"  WARNING: Using synthetic elevations for grid {grid_idx}", flush=True)
        for lat, lon in grid:
            E, Nv = latlon_to_utm13n(lat, lon)
            elev = 1800.0 + (lat - 39.72) * 2800 + abs(lon + 105.25) * 1200 + pt_num * 0.3
            points.append((pt_num, E, Nv, round(elev, 3), "TOPO"))
            pt_num += 1
    time.sleep(1.2)

# Write survey CSV
out_csv = r"C:\Users\Docker\Desktop\JeffersonCountyProject\site_survey.csv"
with open(out_csv, "w", encoding="utf-8") as f:
    f.write("PointNumber,Easting,Northing,Elevation,Code\n")
    for p in points:
        f.write(f"{p[0]},{p[1]},{p[2]},{p[3]},{p[4]}\n")
print(f"Wrote {len(points)} points to {out_csv}", flush=True)

# Compute reference plane (mean elevation rounded to nearest 5m)
elevs = [p[3] for p in points if p[3] > 100]
mean_elev = sum(elevs)/len(elevs) if elevs else 1900.0
ref_plane = round(mean_elev / 5) * 5
print(f"Mean elevation: {mean_elev:.2f}m  ->  Reference plane: {ref_plane}m", flush=True)

# Write project specification
out_spec = r"C:\Users\Docker\Desktop\JeffersonCountyProject\ProjectSpec.txt"
with open(out_spec, "w", encoding="utf-8") as f:
    f.write("EARTHWORK VOLUME ANALYSIS — PROJECT SPECIFICATION\n")
    f.write("="*60 + "\n\n")
    f.write("Client: Jefferson County Road & Bridge Department\n")
    f.write("Project: US-285 Corridor Improvement — Cut/Fill Study\n")
    f.write("Location: Jefferson County, Colorado\n")
    f.write("Coordinate System: UTM Zone 13N (EPSG:26913), meters\n")
    f.write(f"Survey Data File: site_survey.csv ({len(points)} field points)\n\n")
    f.write("PROPOSED ROAD GRADE (REFERENCE PLANE)\n")
    f.write("-"*40 + "\n")
    f.write(f"Reference Plane Elevation: {ref_plane} m\n")
    f.write("(This represents the proposed finished road grade.)\n\n")
    f.write("SURVEY DATA FORMAT\n")
    f.write("-"*40 + "\n")
    f.write("File: site_survey.csv\n")
    f.write("Encoding: UTF-8, comma-separated\n")
    f.write("Columns: PointNumber, Easting (m), Northing (m), Elevation (m), Code\n\n")
    f.write("REQUIRED DELIVERABLE\n")
    f.write("-"*40 + "\n")
    f.write("File: volume_report.txt\n")
    f.write("Path: C:\\Users\\Docker\\Desktop\\JeffersonCountyProject\\volume_report.txt\n\n")
    f.write("The report must contain:\n")
    f.write("  - Project name and date\n")
    f.write(f"  - Reference Plane Elevation: {ref_plane} m\n")
    f.write("  - Cut Volume (m3)\n")
    f.write("  - Fill Volume (m3)\n")
    f.write("  - Net Volume (m3)\n")
    f.write("  - Engineer's summary and assessment\n")

# Save reference plane value for verifier
with open(r"C:\Users\Docker\earthwork_va_ref_plane.txt", "w", encoding="utf-8") as f:
    f.write(str(ref_plane))
print("Setup complete.", flush=True)
'@ | Set-Content -Path $pyPath -Encoding utf8

    # ── 4. Download real USGS elevation data ──
    Write-Host "[4/6] Running data download script..."
    python.exe "$pyPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Python script exited with code $LASTEXITCODE"
    }

    # ── 5. Launch TopoCal ──
    Write-Host "[5/6] Launching TopoCal..."
    $launched = Start-TopoCalInteractive -WaitSeconds 12
    if (-not $launched) {
        Write-Host "WARNING: TopoCal main window may not be visible yet"
    }
    Start-Sleep -Seconds 2
    Set-TopoCalForeground | Out-Null

    # ── 6. Final cleanup ──
    Write-Host "[6/6] Final cleanup..."
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== Setup Complete ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
