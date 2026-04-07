###############################################################################
# setup_task.ps1 — pre_task hook for site_complete_survey_analysis
# Downloads 200 real USGS NED 10m elevation points for El Paso County, CO
# (Colorado Springs area — flatter terrain, ~1750-2100m elevation)
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_site_complete.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up site_complete_survey_analysis task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Remove pre-existing output files ──
    Write-Host "[1/6] Cleaning up stale output files..."
    Remove-Item "C:\Users\Docker\Desktop\ElPasoSite\SiteAnalysis_ElPaso.dxf" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\Desktop\ElPasoSite\SiteAnalysis.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\site_complete_survey_analysis_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Users\Docker\site_complete_meta.json" -Force -ErrorAction SilentlyContinue

    # ── 2. Record task start timestamp (AFTER cleanup) ──
    Write-Host "[2/6] Recording task start timestamp..."
    (Get-Date).ToString("o") | Set-Content -Path "C:\Users\Docker\site_complete_start.txt" -Encoding utf8

    # ── 3. Infrastructure ──
    Write-Host "[3/6] Starting infrastructure..."
    $edgeKiller = Start-EdgeKillerTask
    Close-Browsers
    Ensure-HTTPServer
    Ensure-PyAutoGUIServer

    $projDir = "C:\Users\Docker\Desktop\ElPasoSite"
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    $pyPath = "C:\Users\Docker\download_elpaso_survey.py"
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

# El Paso County, CO — NW Colorado Springs foothills (~1900-2100m)
# Grid 1: 38.860-38.869N, 104.860-104.869W
grid1 = [(38.860+i*0.001, -104.860-j*0.001) for i in range(10) for j in range(10)]
# Grid 2: 38.870-38.879N, 104.870-104.879W
grid2 = [(38.870+i*0.001, -104.870-j*0.001) for i in range(10) for j in range(10)]

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
                        elev = 1950.0 + (lat-38.86)*3000 + abs(lon+104.86)*1500 + pt_num*0.3
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
            elev = 1950.0 + (lat-38.86)*2800 + abs(lon+104.86)*1400 + pt_num*0.35
            points.append((pt_num, E, Nv, round(elev, 3), "TOPO"))
            pt_num += 1
    time.sleep(1.2)

# Write survey CSV
out_csv = r"C:\Users\Docker\Desktop\ElPasoSite\elpaso_survey.csv"
with open(out_csv, "w", encoding="utf-8") as f:
    f.write("PointNumber,Easting,Northing,Elevation,Code\n")
    for p in points:
        f.write(f"{p[0]},{p[1]},{p[2]},{p[3]},{p[4]}\n")
print(f"Wrote {len(points)} points to {out_csv}", flush=True)

elevs = sorted([p[3] for p in points if p[3] > 100])
min_e, max_e, mean_e = elevs[0], elevs[-1], sum(elevs)/len(elevs)
print(f"Elevation range: {min_e:.1f}-{max_e:.1f}m  mean={mean_e:.1f}m", flush=True)

# Calculate two reference planes for volume analysis
# Lower plane: 20m below mean (rounded to 5m)
lower_plane = round((mean_e - 20) / 5) * 5
# Upper plane: 20m above mean (rounded to 5m)
upper_plane = round((mean_e + 20) / 5) * 5

# Write analysis specification
out_spec = r"C:\Users\Docker\Desktop\ElPasoSite\AnalysisSpec.txt"
with open(out_spec, "w", encoding="utf-8") as f:
    f.write("SITE COMPREHENSIVE SURVEY ANALYSIS — SPECIFICATION\n")
    f.write("="*60 + "\n\n")
    f.write("Client: Falcon Ridge Development Group LLC\n")
    f.write("Project: Proposed Subdivision — Lot 4, Section 12\n")
    f.write("Location: El Paso County, Colorado (NW Colorado Springs)\n")
    f.write("Coordinate System: UTM Zone 13N (EPSG:26913), meters\n")
    f.write(f"Survey Data: elpaso_survey.csv ({len(points)} field points)\n\n")
    f.write("REQUIRED DELIVERABLES\n")
    f.write("-"*40 + "\n\n")
    f.write("DELIVERABLE A — DXF Export\n")
    f.write("  File: SiteAnalysis_ElPaso.dxf\n")
    f.write("  Path: C:\\Users\\Docker\\Desktop\\ElPasoSite\\SiteAnalysis_ElPaso.dxf\n")
    f.write("  Must contain:\n")
    f.write("    Layer PUNTOS — survey point entities\n")
    f.write("    Layer CURVAS — contour polylines at 2.5m intervals\n\n")
    f.write("DELIVERABLE B — Earthwork Volume Analysis\n")
    f.write("  Compute earthwork volumes between two reference planes\n")
    f.write(f"  Lower Reference Plane (Plano Inferior): {lower_plane} m\n")
    f.write(f"  Upper Reference Plane (Plano Superior): {upper_plane} m\n")
    f.write("  Report: Cut Volume and Fill Volume between these two planes\n\n")
    f.write("DELIVERABLE C — North-South Profile\n")
    f.write("  Create a longitudinal profile along the N-S centreline\n")
    f.write("  Draw alignment along the approximate N-S centreline of site\n")
    f.write("  Note: profile length and total elevation change\n\n")
    f.write("DELIVERABLE D — Written Analysis Report\n")
    f.write("  File: SiteAnalysis.txt\n")
    f.write("  Path: C:\\Users\\Docker\\Desktop\\ElPasoSite\\SiteAnalysis.txt\n")
    f.write("  Required content:\n")
    f.write("    1. Project identification (name, location, date)\n")
    f.write("    2. Survey area extent (min/max Easting and Northing)\n")
    f.write("    3. Elevation statistics:\n")
    f.write(f"       - Minimum elevation: [value from TopoCal] m\n")
    f.write(f"       - Maximum elevation: [value from TopoCal] m\n")
    f.write(f"       - Mean elevation:    [value from TopoCal] m\n")
    f.write("    4. Contour information: interval (2.5m), total contour lines\n")
    f.write("    5. Earthwork volumes:\n")
    f.write(f"       - Lower plane: {lower_plane} m\n")
    f.write(f"       - Upper plane: {upper_plane} m\n")
    f.write("       - Cut Volume (m3): [from TopoCal]\n")
    f.write("       - Fill Volume (m3): [from TopoCal]\n")
    f.write("       - Net Volume (m3): [from TopoCal]\n")
    f.write("    6. Profile summary: alignment direction, length, elevation range\n")
    f.write("    7. Development suitability assessment (suitable/not suitable)\n")
    f.write("       (Areas with slope > 15% are restricted per county code)\n\n")
    f.write("SURVEY DATA FORMAT\n")
    f.write("-"*40 + "\n")
    f.write("File: elpaso_survey.csv\n")
    f.write("Encoding: UTF-8, comma-separated\n")
    f.write("Columns: PointNumber, Easting (m), Northing (m), Elevation (m), Code\n")

# Save reference planes for verifier
import json as _json
meta = {"lower_plane": lower_plane, "upper_plane": upper_plane,
        "min_elev": round(min_e, 1), "max_elev": round(max_e, 1), "mean_elev": round(mean_e, 1)}
with open(r"C:\Users\Docker\site_complete_meta.json", "w", encoding="utf-8") as f:
    _json.dump(meta, f)
print(f"Reference planes: lower={lower_plane}m, upper={upper_plane}m", flush=True)
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
