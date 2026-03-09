# Note: In the Windows environment, this is actually a PowerShell script (setup_task.ps1)
# but the system expects the content here. I will write it as PowerShell.

Write-Host "=== Setting up IMDB Genre Trends Task ==="

# 1. Create Data Directory
$dataDir = "C:\Users\Docker\Documents\TaskData"
if (!(Test-Path -Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir | Out-Null
    Write-Host "Created data directory: $dataDir"
}

# 2. Cleanup previous run artifacts
Remove-Item -Path "$dataDir\IMDB_Analysis.pbix" -ErrorAction SilentlyContinue
Remove-Item -Path "$dataDir\genre_stats.csv" -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Users\Docker\Desktop\IMDB_Analysis.pbix" -ErrorAction SilentlyContinue

# 3. Download Real Data
$csvPath = "$dataDir\movie_metadata.csv"
$url = "https://raw.githubusercontent.com/sundeepblue/movie_rating_prediction/master/movie_metadata.csv"

Write-Host "Downloading dataset from $url..."
try {
    Invoke-WebRequest -Uri $url -OutFile $csvPath -UseBasicParsing
    Write-Host "Download complete."
} catch {
    Write-Error "Failed to download dataset. Using fallback if available."
    # Fallback creation if internet fails (minimal valid structure for task to arguably proceed)
    $header = "movie_title,duration,director_name,director_facebook_likes,actor_3_facebook_likes,actor_2_name,actor_1_facebook_likes,gross,genres,actor_1_name,num_voted_users,cast_total_facebook_likes,actor_3_name,facenumber_in_poster,plot_keywords,movie_imdb_link,num_user_for_reviews,language,country,content_rating,budget,title_year,actor_2_facebook_likes,imdb_score,aspect_ratio,movie_facebook_likes"
    $row1 = "Avatar,178,James Cameron,0,855,Joel David Moore,1000,760505847,Action|Adventure|Fantasy|Sci-Fi,CCH Pounder,886204,4834,Wes Studi,0,avatar|future|marine|native|paraplegic,http://www.imdb.com/title/tt0499549/?ref_=fn_tt_tt_1,3054,English,USA,PG-13,237000000,2009,936,7.9,1.78,33000"
    Set-Content -Path $csvPath -Value "$header`n$row1"
}

# 4. Record Start Time (Anti-gaming)
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
Set-Content -Path "C:\tmp\task_start_time.txt" -Value $startTime

# 5. Ensure Power BI Desktop is ready (Kill existing to ensure fresh start)
Get-Process "PBIDesktop" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "Starting Power BI Desktop..."
Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
# Wait for window
$timeout = 60
for ($i=0; $i -lt $timeout; $i++) {
    if (Get-Process "PBIDesktop" -ErrorAction SilentlyContinue) {
        Write-Host "Power BI Desktop started."
        break
    }
    Start-Sleep -Seconds 1
}

# 6. Maximize Window (using external tool if available, or just assume agent handles it)
# In this environment, we rely on the agent to manage window state, but ensuring it's running is key.

Write-Host "=== Setup Complete ==="