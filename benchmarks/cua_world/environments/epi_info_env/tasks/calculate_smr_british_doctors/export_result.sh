# Note: In the epi_info_env (Windows), hooks call .ps1 files directly.
# This file is provided for completeness but the actual logic is in export_result.ps1 below.

#!/bin/bash
# Redirect to PowerShell script on Windows
powershell -ExecutionPolicy Bypass -File "C:\workspace\tasks\calculate_smr_british_doctors\export_result.ps1"