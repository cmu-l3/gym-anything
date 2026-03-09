#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_system_smtp_relay task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Start Mock SMTP Server (Python)
# This mimics an open relay that accepts any auth and any recipient
echo "Starting mock SMTP server..."
cat > /tmp/mock_smtp.py << 'EOF'
import socket
import sys

def run_server():
    host = '127.0.0.1'
    port = 1025
    
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, port))
        s.listen(5)
        print(f"Mock SMTP listening on {host}:{port}")
        
        while True:
            conn, addr = s.accept()
            print(f"Connection from {addr}")
            try:
                conn.send(b'220 localhost MockSMTP Ready\r\n')
                while True:
                    data = conn.recv(1024)
                    if not data: break
                    
                    cmd = data.strip().upper()
                    if cmd.startswith(b'EHLO') or cmd.startswith(b'HELO'):
                        conn.send(b'250-localhost\r\n250 AUTH PLAIN LOGIN\r\n')
                    elif cmd.startswith(b'AUTH'):
                        conn.send(b'235 2.7.0 Authentication successful\r\n')
                    elif cmd.startswith(b'MAIL FROM'):
                        conn.send(b'250 2.1.0 Ok\r\n')
                    elif cmd.startswith(b'RCPT TO'):
                        conn.send(b'250 2.1.5 Ok\r\n')
                    elif cmd.startswith(b'DATA'):
                        conn.send(b'354 End data with <CR><LF>.<CR><LF>\r\n')
                    elif cmd == b'.': # Dot on its own line
                        conn.send(b'250 2.0.0 Ok: queued\r\n')
                    elif cmd.startswith(b'QUIT'):
                        conn.send(b'221 2.0.0 Bye\r\n')
                        break
                    else:
                        # Accept data lines during DATA phase or other commands
                        # For simplicity in this mock, we just ACK everything
                        pass
            except Exception as e:
                print(f"Error: {e}")
            finally:
                conn.close()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    run_server()
EOF

# Run the mock server in background logging to file
nohup python3 -u /tmp/mock_smtp.py > /tmp/smtp_relay.log 2>&1 &
echo $! > /tmp/mock_smtp.pid
sleep 2

# 2. Reset System Mail Settings to Defaults
# Ensure we start from a clean state (PHP mail driver)
echo "Resetting mail settings..."
fs_query "UPDATE options SET option_value='mail' WHERE option_key='mail_driver'"
fs_query "UPDATE options SET option_value='' WHERE option_key='mail_host'"
fs_query "UPDATE options SET option_value='' WHERE option_key='mail_port'"
fs_query "UPDATE options SET option_value='freescout@example.com' WHERE option_key='mail_from_address'"
fs_query "UPDATE options SET option_value='FreeScout' WHERE option_key='mail_from_name'"
fs_query "UPDATE options SET option_value=NULL WHERE option_key='mail_encryption'"
fs_query "UPDATE options SET option_value='' WHERE option_key='mail_username'"
fs_query "UPDATE options SET option_value='' WHERE option_key='mail_password'"

# Clear cache to ensure settings take effect
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 3. Launch Firefox and login
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Automate Login
ensure_logged_in

# Navigate to Dashboard to start
navigate_to_url "http://localhost:8080/dashboard"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="