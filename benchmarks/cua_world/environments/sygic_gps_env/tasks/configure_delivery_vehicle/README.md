# Configure Delivery Vehicle

## Overview
A delivery driver configures Sygic GPS Navigation for commercial delivery operations: creating a Van vehicle profile with correct specs and adjusting route planning settings for efficient delivery routing.

## Domain Context
Delivery and courier companies require drivers to configure GPS apps with the correct vehicle type (for accurate routing that avoids low bridges/narrow roads), shortest-distance routing (to minimize mileage), toll road access (company reimburses tolls), and arrive-in-direction (so the driver pulls up on the correct side of the street).

## Goal / End State
- A new vehicle profile named "Delivery Van" exists with type=Van, fuel=Diesel, year=2022, emission=Euro6
- The Delivery Van profile is selected as the active vehicle
- Route computation is set to "Shortest route"
- Toll roads are allowed (avoid toll roads = off)
- Arrive-in-direction is enabled

## Verification Strategy
Six criteria (100 points total):
1. **Vehicle name** (20 pts): Profile named "Delivery Van" exists in the vehicles database
2. **Vehicle type** (15 pts): Type is VAN
3. **Vehicle details** (15 pts): Fuel=DIESEL, year=2022, emission=EURO6
4. **Active profile** (20 pts): Delivery Van is selected as the active vehicle profile
5. **Route compute** (15 pts): Set to "Shortest" (value "0" in shared_prefs)
6. **Route settings** (15 pts): Toll avoidance OFF, arrive-in-direction ON

Gate: If no new vehicle profile was created, score = 0.

## Data Sources
- Vehicle database: `/data/data/com.sygic.aura/databases/vehicles-database` (SQLite, `vehicle` table)
- Preferences: `/data/data/com.sygic.aura/shared_prefs/com.sygic.aura_preferences.xml`
- Selected vehicle: `/data/data/com.sygic.aura/shared_prefs/base_persistence_preferences.xml`

## Edge Cases
- Agent might rename the existing "Vehicle 1" instead of creating a new profile
- Agent might create the profile but forget to select it as active
- Route settings and vehicle creation are in different parts of the app
