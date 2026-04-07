###############################################################################
# setup_task.ps1 — pre_task hook for topographic_plan_production
# Downloads 200 real USGS NED 10m elevation points for Clear Creek County, CO
# (mountainous valley terrain along Clear Creek corridor).
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_topographic_plan_production.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up topographic_plan_production task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Remove pre-existing output files ──
    Write-Host "[1/6] Cleaning up stale output files..."
    Remove-Item "C:\Users\Docker\Desktop\ClearCreekProject\ClearCreek_TopoMap.dxf" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Desktop\ClearCreekProject\ClearCreek.top" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\topographic_plan_production_result.json" -Force -ErrorAction SilentlyContinue

    # ── 2. Record task start timestamp (AFTER cleanup) ──
    Write-Host "[2/6] Recording task start timestamp..."
    (Get-Date).ToString("o") | Set-Content -Path "C:\Users\Docker\topo_plan_start.txt" -Encoding utf8

    # ── 3. Infrastructure ──
    Write-Host "[3/6] Starting infrastructure..."
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    $projDir = "C:\Users\Docker\Desktop\ClearCreekProject"
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    $pyPath = "C:\Users\Docker\download_clearcreek_survey.py"
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

# Clear Creek County, CO — Idaho Springs / Georgetown area (~2350-2800m elevation)
# Grid 1: 39.650-39.659N, 105.700-105.709W
grid1 = [(39.650+i*0.001, -105.700-j*0.001) for i in range(10) for j in range(10)]
# Grid 2: 39.660-39.669N, 105.710-105.719W
grid2 = [(39.660+i*0.001, -105.710-j*0.001) for i in range(10) for j in range(10)]

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
                        elev = 2400.0 + (lat-39.65)*6000 + abs(lon+105.70)*3000 + pt_num*0.5
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
            elev = 2400.0 + (lat-39.65)*5500 + abs(lon+105.70)*2800 + pt_num*0.4
            points.append((pt_num, E, Nv, round(elev, 3), "TOPO"))
            pt_num += 1
    time.sleep(1.2)

# Write survey CSV
out_csv = r"C:\Users\Docker\Desktop\ClearCreekProject\clearcreek_survey.csv"
with open(out_csv, "w", encoding="utf-8") as f:
    f.write("PointNumber,Easting,Northing,Elevation,Code\n")
    for p in points:
        f.write(f"{p[0]},{p[1]},{p[2]},{p[3]},{p[4]}\n")
print(f"Wrote {len(points)} points to {out_csv}", flush=True)

elevs = sorted([p[3] for p in points if p[3] > 100])
min_e, max_e = elevs[0], elevs[-1]
center_E = round(sum(p[1] for p in points)/len(points), 1)
center_N = round(sum(p[2] for p in points)/len(points), 1)
print(f"Elevation range: {min_e:.1f}-{max_e:.1f}m  Center UTM: {center_E},{center_N}", flush=True)

# Write plan specification
out_spec = r"C:\Users\Docker\Desktop\ClearCreekProject\PlanSpec.txt"
with open(out_spec, "w", encoding="utf-8") as f:
    f.write("TOPOGRAPHIC PLAN — PRODUCTION SPECIFICATION\n")
    f.write("="*60 + "\n\n")
    f.write("Client: Clear Creek County Road Department\n")
    f.write("Project: County Road 65 — Grading Permit Application\n")
    f.write("Location: Clear Creek County, Colorado\n")
    f.write("Coordinate System: UTM Zone 13N (EPSG:26913), meters\n")
    f.write(f"Survey Data: clearcreek_survey.csv ({len(points)} field points)\n\n")
    f.write("PLAN CONTENT REQUIREMENTS\n")
    f.write("-"*40 + "\n")
    f.write("Layer 1: PUNTOS — Survey point symbols and labels\n")
    f.write("Layer 2: CURVAS — Contour lines at 2-metre intervals\n")
    f.write("Layer 3: PERFIL — Longitudinal profile geometry\n\n")
    f.write("CONTOUR SPECIFICATION\n")
    f.write("-"*40 + "\n")
    f.write("Contour interval: 2 metres\n")
    f.write("Layer name in TopoCal: CURVAS\n\n")
    f.write("PROFILE ALIGNMENT\n")
    f.write("-"*40 + "\n")
    f.write("The longitudinal profile should be drawn along the\n")
    f.write("approximate centreline of the survey area.\n")
    f.write(f"Approximate centreline start (UTM 13N): {center_E:.1f}E, {center_N-400:.1f}N\n")
    f.write(f"Approximate centreline end   (UTM 13N): {center_E:.1f}E, {center_N+400:.1f}N\n")
    f.write("Direction: North-South (approx. azimuth 0 degrees)\n\n")
    f.write("OUTPUT FILES REQUIRED\n")
    f.write("-"*40 + "\n")
    f.write("1. DXF: C:\\Users\\Docker\\Desktop\\ClearCreekProject\\ClearCreek_TopoMap.dxf\n")
    f.write("   Must contain: PUNTOS layer (survey points),\n")
    f.write("                 CURVAS layer (2m contours),\n")
    f.write("                 PERFIL layer (profile geometry)\n\n")
    f.write("2. TopoCal Project: C:\\Users\\Docker\\Desktop\\ClearCreekProject\\ClearCreek.top\n")
    f.write("   (Save the project in TopoCal native format for archival)\n\n")
    f.write("SURVEY DATA FORMAT\n")
    f.write("-"*40 + "\n")
    f.write("File: clearcreek_survey.csv\n")
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

    Write-Host "[6/6] Cleaning up..."
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    Write-Host "=== Setup Complete ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
