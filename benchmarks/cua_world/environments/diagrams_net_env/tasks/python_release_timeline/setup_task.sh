#!/bin/bash
set -e

echo "=== Setting up python_release_timeline task ==="

# Ensure directories exist
su - ga -c "mkdir -p /home/ga/Diagrams/exports /home/ga/Desktop" 2>/dev/null || true

# 1. Create the structured data file
DATA_FILE="/home/ga/Desktop/python_releases.txt"
cat > "$DATA_FILE" << 'DATAEOF'
# Python Major Release History
# Source: python.org/doc/versions/ and PEPs
# Format: VERSION | DATE | KEY_FEATURES | PHASE

Python 2.0 | Oct 16, 2000 | List comprehensions, garbage collection | python2
Python 2.1 | Apr 17, 2001 | Nested scopes, weak references | python2
Python 2.2 | Dec 21, 2001 | New-style classes, iterators, generators | python2
Python 2.3 | Jul 29, 2003 | Sets module, logging, csv modules | python2
Python 2.4 | Nov 30, 2004 | Decorators, generator expressions | python2
Python 2.5 | Sep 19, 2006 | with statement, conditional expressions | python2
Python 2.6 | Oct 1, 2008 | Multiprocessing, Python 3 transition features | transition
Python 2.7 | Jul 3, 2010 | OrderedDict, set literals, EOL: Jan 1 2020 | transition

Python 3.0 | Dec 3, 2008 | Print function, Unicode by default, new I/O | transition
Python 3.1 | Jun 27, 2009 | OrderedDict, io module improvements | transition
Python 3.2 | Feb 20, 2011 | concurrent.futures, argparse | transition
Python 3.3 | Sep 29, 2012 | yield from, venv module, namespace packages | transition

Python 3.4 | Mar 16, 2014 | asyncio, pathlib, enum, pip bundled | modern
Python 3.5 | Sep 13, 2015 | async/await syntax, type hints (PEP 484) | modern
Python 3.6 | Dec 23, 2016 | f-strings, variable annotations, secrets | modern
Python 3.7 | Jun 27, 2018 | Dataclasses, breakpoint(), contextvars | modern
Python 3.8 | Oct 14, 2019 | Walrus operator :=, positional-only params | modern
Python 3.9 | Oct 5, 2020 | Dict merge operators, type hint generics | modern
Python 3.10 | Oct 4, 2021 | Structural pattern matching (match/case) | modern
Python 3.11 | Oct 24, 2022 | Exception groups, 10-60% faster CPython | modern
Python 3.12 | Oct 2, 2023 | Per-interpreter GIL, f-string improvements | modern
Python 3.13 | Oct 7, 2024 | Experimental JIT compiler, free-threaded mode | modern
DATAEOF
chown ga:ga "$DATA_FILE"

# 2. Create the starter diagram (compressed XML format for draw.io)
# This represents a simple timeline with just Python 2.0-2.7 dots
DIAGRAM_FILE="/home/ga/Diagrams/python_timeline.drawio"

# We create a simple uncompressed XML for easier generation
cat > "$DIAGRAM_FILE" << 'XML'
<mxfile host="Electron" modified="2023-10-01T12:00:00.000Z" agent="Mozilla/5.0" version="21.6.8" type="device">
  <diagram id="timeline_page" name="Release Timeline">
    <mxGraphModel dx="1422" dy="786" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="3300" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Main Timeline Axis -->
        <mxCell id="axis" value="" style="endArrow=classic;html=1;strokeWidth=3;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="100" y="400" as="sourcePoint" />
            <mxPoint x="3000" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Python 2.0 -->
        <mxCell id="p20" value="" style="ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="120" y="390" width="20" height="20" as="geometry" />
        </mxCell>
        <mxCell id="p20label" value="Python 2.0&#xa;Oct 2000" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="100" y="420" width="60" height="40" as="geometry" />
        </mxCell>
        <!-- Python 2.7 (Last one currently drawn) -->
        <mxCell id="p27" value="" style="ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="600" y="390" width="20" height="20" as="geometry" />
        </mxCell>
        <mxCell id="p27label" value="Python 2.7&#xa;Jul 2010" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="580" y="420" width="60" height="40" as="geometry" />
        </mxCell>
        <!-- Title -->
        <mxCell id="title" value="Python Release History" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=24;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="100" y="50" width="300" height="40" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML
chown ga:ga "$DIAGRAM_FILE"

# Record initial stats
date +%s > /tmp/task_start_time.txt
grep -c "<mxCell" "$DIAGRAM_FILE" > /tmp/initial_shape_count.txt || echo "10" > /tmp/initial_shape_count.txt

# 3. Launch Application
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox '$DIAGRAM_FILE' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window found"
        break
    fi
    sleep 1
done

# Dismiss update dialog (Aggressive)
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done
# Try clicking "Cancel" button blind coordinates (approx center-ish right)
DISPLAY=:1 xdotool mousemove 1100 600 click 1 2>/dev/null || true

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="