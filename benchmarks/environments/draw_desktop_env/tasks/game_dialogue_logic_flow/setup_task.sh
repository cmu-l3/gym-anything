#!/bin/bash
set -u

echo "=== Setting up game_dialogue_logic_flow task ==="

# 1. Define paths
SCRIPT_PATH="/home/ga/Desktop/quest_script.txt"
DRAWIO_BIN="drawio"

# 2. Create the Quest Script
cat > "$SCRIPT_PATH" << 'EOF'
QUEST: BLACK MARKET DEAL
SCENE: Neon Alley behind the 'Circuit Breaker' Bar.
CHARACTERS: Player, Fixer (NPC)

[START]
NPC (Fixer): "You lookin' to buy the neural chip? Top quality, fresh from the lab."

CHOICE A: "Yes, how much?" -> GOTO [PRICE_NEGOTIATION]
CHOICE B: [Streetwise Check] "I know it's stolen property. Cut the crap." -> GOTO [LEVERAGE_CHECK]
CHOICE C: "Just browsing." -> GOTO [NEUTRAL_EXIT]

[PRICE_NEGOTIATION]
NPC: "2000 Credits. No refunds."
  IF (Player.Credits >= 2000):
     CHOICE: "Deal." -> EVENT: [Remove 2000 Credits, Add Neural Chip] -> ENDING [SUCCESS]
  IF (Player.Credits < 2000):
     NPC: "Get lost, scrub. Come back when you have the eddies." -> ENDING [FAIL_POOR]

[LEVERAGE_CHECK]
LOGIC TEST: (Player.Streetwise > 5)
  SUCCESS:
    NPC: "Fine. You know the game. 1000 Credits."
    -> GOTO [DISCOUNT_DEAL]
  FAILURE:
    NPC: "You wearing a wire? Boys, get him!"
    -> EVENT: [Combat Starts] -> ENDING [COMBAT]

[DISCOUNT_DEAL]
IF (Player.Credits >= 1000):
   CHOICE: "I'll take it." -> EVENT: [Remove 1000 Credits, Add Neural Chip] -> ENDING [SUCCESS]
ELSE:
   NPC: "Even with a discount, you're broke." -> ENDING [FAIL_POOR]

[NEUTRAL_EXIT]
NPC: "Don't waste my time then." -> ENDING [NEUTRAL]

[RANDOM_EVENT CHECK]
LOGIC TEST: (Global.PoliceHeat > 50)
  YES:
    EVENT: [Police Drone Scan]
    NPC: "Cops! Scatter!"
    -> ENDING [ARRESTED]
  NO:
    (Proceed with normal flow above)
EOF

chown ga:ga "$SCRIPT_PATH"
chmod 644 "$SCRIPT_PATH"

# 3. Clean previous artifacts
rm -f /home/ga/Desktop/quest_flow.drawio
rm -f /home/ga/Desktop/quest_flow.png

# 4. Record timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io (blank)
# We launch it in background to ensure it's ready for the user
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss startup dialog (Escape) to get blank canvas
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="