# Setup script for create_printable_model task.
# Launches Blue Sky Plan with the mandible_case.bsp project file pre-loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_create_printable_model.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {