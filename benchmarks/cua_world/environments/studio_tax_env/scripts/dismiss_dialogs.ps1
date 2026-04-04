# dismiss_dialogs.ps1 — Dismiss StudioTax startup dialogs via PyAutoGUI
# Uses the PyAutoGUI server on port 5555 for reliable GUI interaction.
# Resolution: 1280x720

$ErrorActionPreference = "Continue"

$dismissScript = @'
import socket, json, time

def send_cmd(cmd):
    for attempt in range(3):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(10)
            s.connect(('127.0.0.1', 5555))
            s.sendall((json.dumps(cmd) + '\n').encode())
            data = b''
            while True:
                chunk = s.recv(65536)
                if not chunk: break
                data += chunk
                if b'\n' in data: break
            s.close()
            return json.loads(data.decode().split('\n')[0])
        except Exception as e:
            time.sleep(1)
    return {'success': False}

def click(x, y):
    return send_cmd({'action': 'click', 'x': x, 'y': y})

def press(key):
    return send_cmd({'action': 'press', 'key': key})

# Wait for StudioTax to finish loading
time.sleep(5)

# Phase 1: Dismiss any update/license/first-run dialogs with Escape
press('escape')
time.sleep(1)

# Phase 2: Try clicking common dialog button positions (at 1280x720)
# Center OK button area
click(640, 400)
time.sleep(0.5)

# Press Enter to confirm any focused dialog
press('enter')
time.sleep(1)

# Phase 3: Another round of Escape for remaining popups
press('escape')
time.sleep(0.5)
press('escape')
time.sleep(0.5)

# Phase 4: Handle OneDrive notification if it reappeared
# Close OneDrive X button (top-right area)
click(1237, 391)
time.sleep(0.5)

print("Dialog dismissal complete")
'@

$pyScript = "C:\Windows\Temp\dismiss_dialogs_ga.py"
Set-Content -Path $pyScript -Value $dismissScript
Start-Process -FilePath "python" -ArgumentList $pyScript -Wait -NoNewWindow -ErrorAction SilentlyContinue
Remove-Item $pyScript -Force -ErrorAction SilentlyContinue

Write-Host "Dialog dismissal complete"
