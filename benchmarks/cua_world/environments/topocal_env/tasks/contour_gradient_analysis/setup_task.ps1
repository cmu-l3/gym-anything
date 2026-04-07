###############################################################################
# setup_task.ps1 — pre_task hook for contour_gradient_analysis
# Downloads 200 real USGS NED 10m elevation points for Gilpin County, CO
# (high-elevation mountainous terrain with significant gradient variation).
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_contour_gradient_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up contour_gradient_analysis task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Remove pre-existing output files ──
    Write-Host "[1/6] Cleaning up stale output files..."
    Remove-Item "C:\Users\Docker\Desktop\GilpinProject\contour_map.dxf" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Desktop\GilpinProject\slope_analysis.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\contour_gradient_analysis_result.json" -Force -ErrorAction SilentlyContinue

    # ── 2. Record task start timestamp (AFTER cleanup) ──
    Write-Host "[2/6] Recording task start timestamp..."
    (Get-Date).ToString("o") | Set-Content -Path "C:\Users\Docker\contour_ga_start.txt" -Encoding utf8

    # ── 3. Infrastructure ──
    Write-Host "[3/6] Starting infrastructure..."
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    $projDir = "C:\Users\Docker\Desktop\GilpinProject"
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    $pyPath = "C:\Users\Docker\download_gilpin_survey.py"
    @'
import json, math, time, sys, urllib.request

def latlon_to_utm13n(lat, lon):
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

# Gilpin County, CO — high-elevation mountain terrain (Central City area)
# Grid 1: 39.820-39.829N, 105.510-105.519W  (Elevation ~2600-3100m)
grid1 = [(39.820+i*0.001, -105.510-j*0.001) for i in range(10) for j in range(10)]
# Grid 2: 39.830-39.839N, 105.520-105.529W
grid2 = [(39.830+i*0.001, -105.520-j*0.001) for i in range(10) for j in range(10)]

points = []
pt_num = 1

for grid_idx, grid in enumerate([grid1, grid2], 1):
    locs = "|".join(f"{lat},{lon}" for lat, lon in grid)
    url = f"https://api.opentopodata.org/v1/ned10m?locations={locs}"
    print(f"Fetching grid {grid_idx}/2...", flush=True)
    success = False
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TopoCal-Gym/1.0"})
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read())
            if data.get("status") == "OK":
                for r, (lat, lon) in zip(data["results"], grid):
                    elev = r.get("elevation")
                    if elev is None or float(elev) <= 0:
                        elev = 2700.0 + (lat-39.82)*8000 + abs(lon+105.51)*4000 + pt_num*0.7
                    E, Nv = latlon_to_utm13n(lat, lon)
                    points.append((pt_num, E, Nv, round(float(elev), 3), "TOPO"))
                    pt_num += 1
                success = True
                break
        except Exception as exc:
            print(f"  Attempt {attempt+1} failed: {exc}", flush=True)
            time.sleep(2)
    if not success:
        print(f"  WARNING: Synthetic elevations for grid {grid_idx}", flush=True)
        for lat, lon in grid:
            E, Nv = latlon_to_utm13n(lat, lon)
            elev = 2700.0 + (lat-39.82)*7500 + abs(lon+105.51)*3500 + pt_num*0.6
            points.append((pt_num, E, Nv, round(elev, 3), "TOPO"))
            pt_num += 1
    time.sleep(1.2)

# Write survey CSV
out_csv = r"C:\Users\Docker\Desktop\GilpinProject\gilpin_survey.csv"
with open(out_csv, "w", encoding="utf-8") as f:
    f.write("PointNumber,Easting,Northing,Elevation,Code\n")
    for p in points:
        f.write(f"{p[0]},{p[1]},{p[2]},{p[3]},{p[4]}\n")
print(f"Wrote {len(points)} points to {out_csv}", flush=True)

elevs = sorted([p[3] for p in points if p[3] > 100])
min_e, max_e = elevs[0], elevs[-1]
print(f"Elevation range: {min_e:.1f}m to {max_e:.1f}m", flush=True)

# Write cartographic specification
out_spec = r"C:\Users\Docker\Desktop\GilpinProject\ContourSpec.txt"
with open(out_spec, "w", encoding="utf-8") as f:
    f.write("CONTOUR MAPPING — CARTOGRAPHIC SPECIFICATION\n")
    f.write("="*60 + "\n\n")
    f.write("Client: Gilpin County Planning Department\n")
    f.write("Project: Land-Use Permit #GP-2025-0047 — Slope Analysis\n")
    f.write("Location: Gilpin County, Colorado (Central City vicinity)\n")
    f.write("Coordinate System: UTM Zone 13N (EPSG:26913), meters\n")
    f.write(f"Survey File: gilpin_survey.csv ({len(points)} field points)\n\n")
    f.write("CARTOGRAPHIC REQUIREMENTS\n")
    f.write("-"*40 + "\n")
    f.write("Contour Type 1: Intermediate contours\n")
    f.write("  Interval: 1 metre\n")
    f.write("  DXF Layer Name: Curvas_1m\n")
    f.write("  Line weight: 0.15mm\n\n")
    f.write("Contour Type 2: Index (master) contours\n")
    f.write("  Interval: 5 metres\n")
    f.write("  DXF Layer Name: Curvas_5m\n")
    f.write("  Line weight: 0.35mm\n\n")
    f.write("OUTPUT FILES REQUIRED\n")
    f.write("-"*40 + "\n")
    f.write("1. DXF export: C:\\Users\\Docker\\Desktop\\GilpinProject\\contour_map.dxf\n")
    f.write("   (Export the complete drawing in DXF format)\n\n")
    f.write("2. Slope analysis report:\n")
    f.write("   C:\\Users\\Docker\\Desktop\\GilpinProject\\slope_analysis.txt\n\n")
    f.write("SLOPE ANALYSIS REPORT MUST INCLUDE\n")
    f.write("-"*40 + "\n")
    f.write("  - Total number of contour lines generated (1m + 5m)\n")
    f.write(f"  - Minimum elevation in survey area: {min_e:.1f} m (verify in TopoCal)\n")
    f.write(f"  - Maximum elevation in survey area: {max_e:.1f} m (verify in TopoCal)\n")
    f.write("  - Identification of steep gradient zones\n")
    f.write("    (where 1m contours are < 5m apart horizontally = slope > 20%)\n")
    f.write("  - Development suitability recommendation based on slope\n")
    f.write("  - Any areas > 30% slope are UNSUITABLE for building\n\n")
    f.write("SURVEY DATA FORMAT\n")
    f.write("-"*40 + "\n")
    f.write("File: gilpin_survey.csv\n")
    f.write("Encoding: UTF-8, comma-separated\n")
    f.write("Columns: PointNumber, Easting (m), Northing (m), Elevation (m), Code\n")

print("Setup complete.", flush=True)
'@ | Set-Content -Path $pyPath -Encoding utf8

    Write-Host "[4/6] Running data download script..."
    python.exe "$pyPath"
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: Python exited $LASTEXITCODE" }

    Write-Host "[5/6] Launching TopoCal..."
    $launched = Start-TopoCalInteractive -WaitSeconds 12
    if (-not $launched) { Write-Host "WARNING: TopoCal not yet visible" }
    Start-Sleep -Seconds 2
    Set-TopoCalForeground | Out-Null

    Write-Host "[6/6] Final cleanup..."
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== Setup Complete ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
