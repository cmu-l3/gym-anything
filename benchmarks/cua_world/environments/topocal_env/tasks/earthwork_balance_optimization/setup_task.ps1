###############################################################################
# setup_task.ps1 — pre_task hook for earthwork_balance_optimization
# Downloads 300 real USGS NED 10m elevation points for El Paso County, CO,
# converts to UTM Zone 13N, writes project CSV and spec, launches TopoCal.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_earthwork_balance_optimization.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up earthwork_balance_optimization task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Remove pre-existing output files ──
    Write-Host "[1/6] Cleaning up stale output files..."
    Remove-Item "C:\Users\Docker\Desktop\GradingStudy\grading_report.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Desktop\GradingStudy\site_grading.dxf" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Desktop\GradingStudy\site_grading.top" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\earthwork_balance_optimization_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\earthwork_bal_meta.json" -Force -ErrorAction SilentlyContinue

    # ── 2. Record task start timestamp (AFTER cleanup) ──
    Write-Host "[2/6] Recording task start timestamp..."
    (Get-Date).ToString("o") | Set-Content -Path "C:\Users\Docker\earthwork_bal_start.txt" -Encoding utf8

    # ── 3. Infrastructure ──
    Write-Host "[3/6] Starting infrastructure..."
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    # Force activation bypass registry key (defensive — may not have been set during post_start warm-up)
    $regPath = "HKCU:\Software\VB and VBA Program Settings\TopoCal\TopoCal Proceso"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name "Termina" -Value "1" -ErrorAction SilentlyContinue
        Write-Host "  Set Termina=1 in registry (activation bypass)"
    }

    # Create project directory
    $projDir = "C:\Users\Docker\Desktop\GradingStudy"
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    # Write Python data-download script
    $pyPath = "C:\Users\Docker\download_grading_survey.py"
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

# Three 10x10 grids covering a ~500m x 500m area near Colorado Springs
# Grid 1: 38.855-38.864N, 104.855-104.864W  (SW block)
grid1 = [(38.855+i*0.001, -104.855-j*0.001) for i in range(10) for j in range(10)]
# Grid 2: 38.862-38.871N, 104.862-104.871W  (center block, overlapping)
grid2 = [(38.862+i*0.001, -104.862-j*0.001) for i in range(10) for j in range(10)]
# Grid 3: 38.869-38.878N, 104.869-104.878W  (NE block, overlapping)
grid3 = [(38.869+i*0.001, -104.869-j*0.001) for i in range(10) for j in range(10)]

points = []
pt_num = 1
codes = ["GND"] * 80 + ["CP"] * 5 + ["TP"] * 10 + ["BM"] * 5
# Extend to 300
while len(codes) < 300:
    codes.append("GND")

for grid_idx, grid in enumerate([grid1, grid2, grid3], 1):
    locs = "|".join(f"{lat},{lon}" for lat, lon in grid)
    url = f"https://api.opentopodata.org/v1/ned10m?locations={locs}"
    print(f"Fetching grid {grid_idx}/3 from OpenTopoData...", flush=True)
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
                        elev = 1900.0 + (lat - 38.86) * 4000 + (lon + 104.86) * 2000
                    E, Nv = latlon_to_utm13n(lat, lon)
                    code = codes[pt_num - 1] if pt_num <= len(codes) else "GND"
                    points.append((pt_num, E, Nv, round(float(elev), 3), code))
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
            elev = 1900.0 + (lat - 38.86) * 3500 + abs(lon + 104.86) * 1800 + pt_num * 0.25
            code = codes[pt_num - 1] if pt_num <= len(codes) else "GND"
            points.append((pt_num, E, Nv, round(elev, 3), code))
            pt_num += 1
    time.sleep(1.2)

# Write survey CSV
out_csv = r"C:\Users\Docker\Desktop\GradingStudy\site_survey.csv"
with open(out_csv, "w", encoding="utf-8") as f:
    f.write("PointNumber,Easting,Northing,Elevation,Code\n")
    for p in points:
        f.write(f"{p[0]},{p[1]},{p[2]},{p[3]},{p[4]}\n")
print(f"Wrote {len(points)} points to {out_csv}", flush=True)

# Compute elevation statistics
elevs = [p[3] for p in points if p[3] > 100]
mean_elev = sum(elevs)/len(elevs) if elevs else 1950.0
min_elev = min(elevs) if elevs else 1850.0
max_elev = max(elevs) if elevs else 2100.0

# Suggested starting elevation is NOT the answer — deliberately offset from true balance
# Use mean rounded to 10m as the starting suggestion
start_elev = round(mean_elev / 10) * 10
print(f"Elevation range: {min_elev:.1f} - {max_elev:.1f} m", flush=True)
print(f"Mean elevation: {mean_elev:.2f} m", flush=True)
print(f"Suggested starting elevation: {start_elev} m", flush=True)

# Write project specification
out_spec = r"C:\Users\Docker\Desktop\GradingStudy\ProjectSpec.txt"
with open(out_spec, "w", encoding="utf-8") as f:
    f.write("EARTHWORK BALANCE OPTIMIZATION — PROJECT SPECIFICATION\n")
    f.write("=" * 60 + "\n\n")
    f.write("Client: Pikes Peak Development Group\n")
    f.write("Project: Colorado Springs Residential Grading Study\n")
    f.write("Location: El Paso County, Colorado\n")
    f.write("Coordinate System: UTM Zone 13N (EPSG:26913), meters\n")
    f.write(f"Survey Data File: site_survey.csv ({len(points)} field points)\n\n")
    f.write("OBJECTIVE\n")
    f.write("-" * 40 + "\n")
    f.write("Determine the optimal pad grading elevation where earthwork\n")
    f.write("is balanced: cut volume approximately equals fill volume.\n")
    f.write("Target cut-to-fill ratio: between 0.9 and 1.1\n\n")
    f.write("METHODOLOGY\n")
    f.write("-" * 40 + "\n")
    f.write("1. Import the survey data and build a terrain model (TIN/MDT)\n")
    f.write("2. Use the volume computation tool (Volumen con plano / cota)\n")
    f.write("   to test candidate grading elevations\n")
    f.write("3. Test at least 5 candidate elevations, systematically\n")
    f.write("   narrowing toward the balance point\n")
    f.write(f"4. Suggested starting elevation: {start_elev} m\n")
    f.write(f"   (site elevation range: {min_elev:.0f} - {max_elev:.0f} m)\n\n")
    f.write("REQUIRED DELIVERABLES\n")
    f.write("-" * 40 + "\n")
    f.write("File: grading_report.txt\n")
    f.write("  - Each candidate elevation tested, with its cut and fill\n")
    f.write("    volumes (m3) and the resulting cut-to-fill ratio\n")
    f.write("  - The final balanced elevation and its ratio\n\n")
    f.write("File: site_grading.dxf\n")
    f.write("  - Terrain contour map at 2-meter intervals\n\n")
    f.write("File: site_grading.top\n")
    f.write("  - Saved TopoCal project file\n\n")
    f.write("All files must be saved to:\n")
    f.write("C:\\Users\\Docker\\Desktop\\GradingStudy\\\n")

# Save metadata for verifier
meta = {
    "min_elevation": round(min_elev, 2),
    "max_elevation": round(max_elev, 2),
    "mean_elevation": round(mean_elev, 2),
    "suggested_start": start_elev,
    "point_count": len(points)
}
with open(r"C:\Users\Docker\earthwork_bal_meta.json", "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2)

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
