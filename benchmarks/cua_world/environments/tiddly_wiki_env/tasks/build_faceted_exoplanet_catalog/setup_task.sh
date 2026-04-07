#!/bin/bash
echo "=== Setting up build_faceted_exoplanet_catalog task ==="

source /workspace/scripts/task_utils.sh

# Record initial task start time
date +%s > /tmp/task_start_time.txt
date +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_time_formatted.txt

TIDDLERS_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TIDDLERS_DIR"

echo "Seeding exoplanet dataset..."

# Create a set of real exoplanets for the catalog
cat << 'EOF' > "$TIDDLERS_DIR/Kepler-22b.tid"
title: Kepler-22b
tags: Exoplanet
discovery-method: Transit
planet-type: Super Earth

A confirmed super-Earth located in the habitable zone of a Sun-like star.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/TRAPPIST-1 d.tid"
title: TRAPPIST-1 d
tags: Exoplanet
discovery-method: Transit
planet-type: Terrestrial

A rocky Earth-sized exoplanet orbiting within the habitable zone of the ultracool dwarf star TRAPPIST-1.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/51 Pegasi b.tid"
title: 51 Pegasi b
tags: Exoplanet
discovery-method: Radial Velocity
planet-type: Gas Giant

The first exoplanet discovered orbiting a main-sequence star. A classic Hot Jupiter.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/Beta Pictoris b.tid"
title: Beta Pictoris b
tags: Exoplanet
discovery-method: Imaging
planet-type: Gas Giant

A young gas giant exoplanet located in the debris disk of Beta Pictoris, discovered via direct imaging.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/Gliese 581 g.tid"
title: Gliese 581 g
tags: Exoplanet
discovery-method: Radial Velocity
planet-type: Super Earth

An unconfirmed (but historically significant) exoplanet claimed to orbit the red dwarf Gliese 581.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/Proxima Centauri b.tid"
title: Proxima Centauri b
tags: Exoplanet
discovery-method: Radial Velocity
planet-type: Terrestrial

The closest known exoplanet to the Solar System, orbiting in the habitable zone of Proxima Centauri.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/Kepler-186f.tid"
title: Kepler-186f
tags: Exoplanet
discovery-method: Transit
planet-type: Terrestrial

The first Earth-sized exoplanet discovered in the habitable zone of another star.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/HD 209458 b.tid"
title: HD 209458 b
tags: Exoplanet
discovery-method: Radial Velocity
planet-type: Gas Giant

An exoplanet that transits the solar analog star HD 209458 in the constellation Pegasus.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/HR 8799 c.tid"
title: HR 8799 c
tags: Exoplanet
discovery-method: Imaging
planet-type: Gas Giant

One of four massive planets directly imaged around the young star HR 8799.
EOF

cat << 'EOF' > "$TIDDLERS_DIR/Kepler-452b.tid"
title: Kepler-452b
tags: Exoplanet
discovery-method: Transit
planet-type: Super Earth

Sometimes called Earth's older, bigger cousin. Orbits a G-class star similar to our Sun.
EOF

chown -R ga:ga "$TIDDLERS_DIR"

# Allow TiddlyWiki to pick up the new files
sleep 3

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot showing seeded wiki
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="