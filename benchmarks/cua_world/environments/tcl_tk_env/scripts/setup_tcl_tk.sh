#!/bin/bash
set -e

echo "=== Setting up Tcl/Tk Environment ==="

# Wait for desktop to be ready
sleep 5

# Create working directories for the ga user
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/.config/gedit

# Copy real data files to user's Documents folder
cp /workspace/data/pittsburgh_weather.csv /home/ga/Documents/
cp /workspace/data/periodic_table.csv /home/ga/Documents/

# Find and copy the real Tk plot.tcl demo to Documents
TK_DEMO_DIR=""
if [ -d "/usr/share/tcltk/tk8.6/demos" ]; then
    TK_DEMO_DIR="/usr/share/tcltk/tk8.6/demos"
elif [ -d "/usr/share/tk8.6/demos" ]; then
    TK_DEMO_DIR="/usr/share/tk8.6/demos"
fi

if [ -n "$TK_DEMO_DIR" ] && [ -f "$TK_DEMO_DIR/plot.tcl" ]; then
    cp "$TK_DEMO_DIR/plot.tcl" /home/ga/Documents/plot.tcl
    echo "Copied plot.tcl demo from $TK_DEMO_DIR"
else
    echo "WARNING: plot.tcl demo not found, creating from Tk source"
    # Fallback: extract plot.tcl content using tclsh
    cat > /home/ga/Documents/plot.tcl << 'PLOTEOF'
# plot.tcl --
# This demonstration script creates a canvas widget showing a 2-D
# plot with data points that can be dragged with the mouse.

package require Tk

set w .plot
catch {destroy $w}
toplevel $w
wm title $w "Plot Demonstration"
wm iconname $w "Plot"

set c $w.c

label $w.msg -font {Helvetica 12} -wraplength 4i -justify left \
    -text "This window displays a canvas widget containing a simple\
    2-dimensional plot. You can doctor the data by dragging any of\
    the data points to new positions."
pack $w.msg -side top

frame $w.buttons
pack $w.buttons -side bottom -fill x -pady 2m
button $w.buttons.dismiss -text Dismiss -command "destroy $w"
pack $w.buttons.dismiss -side left -expand 1

canvas $c -relief raised -width 450 -height 300
pack $c -side top -fill x

set plotFont {Helvetica 18}

$c create line 100 250 400 250 -width 2
$c create line 100 250 100 50 -width 2
for {set i 0} {$i <= 10} {incr i} {
    set x [expr {100 + ($i*30)}]
    $c create line $x 250 $x 245 -width 2
    $c create text $x 254 -text [expr {10*$i}] -anchor n -font $plotFont
}
for {set i 0} {$i <= 5} {incr i} {
    set y [expr {250 - ($i*40)}]
    $c create line 100 $y 105 $y -width 2
    $c create text 96 $y -text [expr {$i*50}].0 -anchor e -font $plotFont
}

foreach point {
    {12 56} {20 94} {33 98} {40 120} {50 142}
    {60 150} {65 199} {70 194} {80 220} {90 180}
} {
    set x [expr {100 + (3*[lindex $point 0])}]
    set y [expr {250 - (4*[lindex $point 1])/5}]
    set item [$c create oval [expr {$x-6}] [expr {$y-6}] \
        [expr {$x+6}] [expr {$y+6}] -width 1 -outline black \
        -fill SteelBlue2]
    $c addtag point withtag $item
}

$c bind point <Enter> "$c itemconfig current -fill red"
$c bind point <Leave> "$c itemconfig current -fill SteelBlue2"
$c bind point <ButtonPress-1> "plotDown $c %x %y"
$c bind point <ButtonRelease-1> "$c dtag selected"
$c bind point <B1-Motion> "plotMove $c %x %y"

set plot(lastX) 0
set plot(lastY) 0

proc plotDown {w x y} {
    global plot
    $w dtag selected
    $w addtag selected withtag current
    $w raise current
    set plot(lastX) $x
    set plot(lastY) $y
}

proc plotMove {w x y} {
    global plot
    $w move selected [expr {$x-$plot(lastX)}] [expr {$y-$plot(lastY)}]
    set plot(lastX) $x
    set plot(lastY) $y
}
PLOTEOF
fi

# Set ownership
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Desktop

# Suppress gedit first-run welcome screen
mkdir -p /home/ga/.local/share/gedit
su - ga -c "dbus-launch gsettings set org.gnome.gedit.preferences.ui statusbar-visible true 2>/dev/null" || true

# Warm-up launch of wish to ensure Tk works with the display
echo "Performing Tk warm-up test..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wish8.6 -e 'after 2000 {destroy .}' &" 2>/dev/null || true
sleep 4
pkill -f "wish8.6" 2>/dev/null || true
sleep 1

echo "=== Tcl/Tk setup complete ==="
echo "Data files in /home/ga/Documents/:"
ls -la /home/ga/Documents/
