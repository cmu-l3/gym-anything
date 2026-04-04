#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up airline_passenger_journey_map task ==="

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

# Clean up any existing files
rm -f /home/ga/Desktop/passenger_journey_map.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/passenger_journey_map.png 2>/dev/null || true
rm -f /home/ga/Desktop/passenger_journey_requirements.txt 2>/dev/null || true

# Create the requirements file with real-world IATA standard phases
cat > /home/ga/Desktop/passenger_journey_requirements.txt << 'REQEOF'
PASSENGER JOURNEY MAP REQUIREMENTS
==================================
Project: End-to-End Economy Class Experience
Persona: "Occasional Leisure Traveler"

STRUCTURE
---------
Format: Cross-functional Swimlane Diagram
Phases (Columns):
  1. Research & Booking
  2. Pre-Departure (24h before)
  3. Airport Departure
  4. In-Flight
  5. Arrival
  6. Post-Trip

Lanes (Rows):
  1. Touchpoints (What they interact with)
  2. Channels (Digital/Physical)
  3. Customer Actions (What they do)
  4. Emotions (How they feel)
  5. Pain Points (Friction areas)
  6. Opportunities (Ideas for improvement)

CONTENT TO MAP
--------------

PHASE 1: RESEARCH & BOOKING
- Action: Compare prices, select dates
- Touchpoint: Website, OTA (Expedia/Skyscanner)
- Channel: Digital
- Emotion: Excited, Anxious
- Pain Point: Hidden fees revealed at checkout, confusing fare classes
- Opportunity: Transparent pricing calendar

PHASE 2: PRE-DEPARTURE
- Action: Online check-in, seat selection
- Touchpoint: Mobile App, Email confirmation
- Channel: Digital
- Emotion: Anticipation
- Pain Point: App bugs during check-in, upsell spam
- Opportunity: Auto-check-in feature

PHASE 3: AIRPORT DEPARTURE
- Action: Bag drop, security screening, boarding
- Touchpoint: Kiosk, Security Checkpoint, Gate Agent
- Channel: Physical
- Emotion: Stressed (high peak)
- Pain Point: Long queues at security, confusing signage, gate changes
- Opportunity: Biometric boarding, real-time queue wait times

PHASE 4: IN-FLIGHT
- Action: Stow luggage, meal service, entertainment
- Touchpoint: Cabin Crew, IFE Screen, Seat
- Channel: Physical
- Emotion: Cramped, Bored -> Relaxed
- Pain Point: Limited legroom, poor Wi-Fi connectivity
- Opportunity: Free messaging Wi-Fi, BYOD entertainment support

PHASE 5: ARRIVAL
- Action: Deplane, immigration, baggage claim
- Touchpoint: Immigration Officer, Baggage Carousel
- Channel: Physical
- Emotion: Fatigued, Impatient
- Pain Point: Slow bag delivery, long walk to exit, lost luggage risk
- Opportunity: Real-time bag tracking notification

PHASE 6: POST-TRIP
- Action: Travel home, loyalty points update
- Touchpoint: Uber/Taxi, Loyalty Email
- Channel: Hybrid
- Emotion: Relieved, Satisfied
- Pain Point: Missing frequent flyer points
- Opportunity: Auto-credit points, personalized "Welcome Home" offer

PAGE 2: KEY METRICS SUMMARY
---------------------------
Please create a second page summarizing the critical metrics.

Top 5 Pain Points (Ranked):
1. Hidden fees (Booking)
2. Long queues (Security)
3. Limited legroom (In-Flight)
4. Slow bag delivery (Arrival)
5. App bugs (Pre-Departure)

Moments of Truth (NPS Drivers):
1. Booking Confirmation (Ease of use)
2. Boarding Experience (Efficiency)
3. Baggage Claim (Speed/Reliability)
REQEOF

chown ga:ga /home/ga/Desktop/passenger_journey_requirements.txt
echo "Requirements file created at ~/Desktop/passenger_journey_requirements.txt"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Wait for UI stability
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="