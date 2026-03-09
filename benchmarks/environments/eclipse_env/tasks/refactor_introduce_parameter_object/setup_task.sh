#!/bin/bash
set -e
echo "=== Setting up Refactor Parameter Object Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
SOURCE_DIR="/home/ga/Documents/FlightSystem"
# Ensure clean state
rm -rf "$SOURCE_DIR"
rm -rf "/home/ga/eclipse-workspace/FlightSystem"

# Create project directory structure
mkdir -p "$SOURCE_DIR/src/com/flysky/model"
mkdir -p "$SOURCE_DIR/src/com/flysky/service"
mkdir -p "$SOURCE_DIR/src/com/flysky/app"
mkdir -p "$SOURCE_DIR/bin"

# 1. Create .project file (Standard Java Project)
cat > "$SOURCE_DIR/.project" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>FlightSystem</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
XML

# 2. Create .classpath file
cat > "$SOURCE_DIR/.classpath" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
XML

# 3. Create Passenger.java (Model)
cat > "$SOURCE_DIR/src/com/flysky/model/Passenger.java" << 'JAVA'
package com.flysky.model;

public class Passenger {
    private String id;
    private String name;

    public Passenger(String id, String name) {
        this.id = id;
        this.name = name;
    }

    public String getId() { return id; }
    public String getName() { return name; }
}
JAVA

# 4. Create BookingService.java (The target for refactoring)
cat > "$SOURCE_DIR/src/com/flysky/service/BookingService.java" << 'JAVA'
package com.flysky.service;

import java.time.LocalDate;
import com.flysky.model.Passenger;

public class BookingService {

    /**
     * Creates a new flight booking.
     * 
     * Refactoring Task: Group the seat-related parameters (row, letter, window, aisle, exitRow)
     * into a new class named 'SeatDetails'.
     */
    public void createBooking(String passengerId, 
                              String flightNumber, 
                              LocalDate flightDate,
                              String seatRow,      
                              char seatLetter,     
                              boolean window,      
                              boolean aisle,       
                              boolean exitRow) {   
        
        System.out.printf("Booking created for passenger %s on flight %s (%s)%n", 
                passengerId, flightNumber, flightDate);
        
        System.out.printf("Seat Assignment: %s%s [Window: %b, Aisle: %b, Exit: %b]%n", 
                seatRow, seatLetter, window, aisle, exitRow);
    }
}
JAVA

# 5. Create BookingApp.java (The Caller)
cat > "$SOURCE_DIR/src/com/flysky/app/BookingApp.java" << 'JAVA'
package com.flysky.app;

import java.time.LocalDate;
import com.flysky.service.BookingService;

public class BookingApp {
    public static void main(String[] args) {
        BookingService service = new BookingService();
        
        // This call needs to be updated automatically by the refactoring
        service.createBooking(
            "P998877", 
            "FS-101", 
            LocalDate.of(2023, 12, 25),
            "12",   // seatRow
            'A',    // seatLetter
            true,   // window
            false,  // aisle
            false   // exitRow
        );
        
        service.createBooking(
            "P112233", 
            "FS-202", 
            LocalDate.now(),
            "44",   // seatRow
            'D',    // seatLetter
            false,  // window
            true,   // aisle
            true    // exitRow
        );
    }
}
JAVA

# Set permissions
chown -R ga:ga "$SOURCE_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Eclipse is running
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs
dismiss_dialogs 3
close_welcome_tab

# Focus window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project created at $SOURCE_DIR"