#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up oauth2_sequence_diagram task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up previous artifacts
rm -f /home/ga/Desktop/oauth2_sequence.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/oauth2_sequence.png 2>/dev/null || true

# Create the Protocol Specification File
cat > /home/ga/Desktop/oauth2_pkce_spec.txt << 'TEXTEOF'
OAuth 2.0 Authorization Code Flow with PKCE Specification
=========================================================
Based on RFC 6749 and RFC 7636.

This protocol secures public clients (like mobile apps) by preventing authorization code interception.

PARTICIPANTS:
1. User (Resource Owner)
2. Client (Mobile/Web App)
3. Authorization Server (Identity Provider)
4. Resource Server (API)

PROTOCOL FLOW:

1. [Client -> Client] 
   The Client generates a random 'code_verifier' and derives a 'code_challenge' (SHA256).

2. [Client -> Authorization Server]
   Client initiates login by redirecting the browser.
   Parameters: response_type=code, client_id, redirect_uri, code_challenge, code_challenge_method=S256.

3. [Authorization Server -> User]
   Server prompts User for credentials and consent.

4. [User -> Authorization Server]
   User authenticates and grants permission.

5. [Authorization Server -> Client]
   Server redirects back to Client with an 'authorization code'.

6. [Client -> Authorization Server]
   Client exchanges the code for a token.
   Parameters: grant_type=authorization_code, code, redirect_uri, client_id, code_verifier.

7. [Authorization Server -> Authorization Server]
   Server calculates SHA256(code_verifier) and compares it to the previously received code_challenge.
   If they match, the request is valid.

8. [Authorization Server -> Client]
   Server returns Access Token and Refresh Token.

9. [Client -> Resource Server]
   Client requests protected data using the Access Token.
   Header: Authorization: Bearer <access_token>

10. [Resource Server -> Client]
    Returns 200 OK with requested resource.

---
TOKEN REFRESH FLOW (Separate Page):
1. Client sends Refresh Token to Authorization Server.
2. Authorization Server validates and issues new Access/Refresh Tokens.
TEXTEOF

chown ga:ga /home/ga/Desktop/oauth2_pkce_spec.txt
chmod 644 /home/ga/Desktop/oauth2_pkce_spec.txt

# Record start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_oauth.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Esc creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify blank canvas
DISPLAY=:1 import -window root /tmp/oauth_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="