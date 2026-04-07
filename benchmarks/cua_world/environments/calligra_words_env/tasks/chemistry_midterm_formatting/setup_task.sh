#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Chemistry Midterm Formatting Task ==="

# Record task start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/chem1311_midterm.odt

# ------------------------------------------------------------------
# Create the unformatted Chemistry Midterm report using odfpy
# ALL content is plain P elements — no heading styles, no bold, no tables
# ------------------------------------------------------------------
cat << 'PYEOF' > /tmp/create_midterm.py
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Header Block ──
add_paragraph("CHEM 1311 – General Chemistry I")
add_paragraph("Midterm Examination")
add_paragraph("Fall 2024")
add_paragraph("Dr. Sarah Chen")
add_paragraph("Department of Chemistry, State University")
add_paragraph("")

# ── Student Info Fields ──
add_paragraph("Name: ")
add_paragraph("Student ID: ")
add_paragraph("Section Number: ")
add_paragraph("Date: ")
add_paragraph("")

# ── Honor Pledge ──
add_paragraph("Honor Pledge: I affirm that I will not give or receive any unauthorized help on this exam, and that all work will be my own.")
add_paragraph("Signature: ")
add_paragraph("")

# ── Instructions ──
add_paragraph("Instructions")
add_paragraph("1. You have 75 minutes to complete this exam.")
add_paragraph("2. A non-programmable calculator is permitted.")
add_paragraph("3. A periodic table is provided on the last page.")
add_paragraph("4. Show all work for calculation problems to receive partial credit.")
add_paragraph("")

# ── Point Distribution ──
add_paragraph("Point Allocation:")
add_paragraph("Part I: 10 MC questions @ 3 pts each = 30 pts")
add_paragraph("Part II: 5 Short Answer @ 6 pts each = 30 pts")
add_paragraph("Part III: 4 Calculation Problems @ 10 pts each = 40 pts")
add_paragraph("Total = 100 pts")
add_paragraph("")

# ── Part I ──
add_paragraph("Part I: Multiple Choice")
add_paragraph("1. Which of the following correctly describes the ground state electron configuration of a neutral copper atom?")
add_paragraph("A) [Ar] 4s2 3d9")
add_paragraph("B) [Ar] 4s1 3d10")
add_paragraph("C) [Kr] 5s1 4d10")
add_paragraph("D) [Ar] 4s2 4p6")
add_paragraph("")

add_paragraph("2. According to VSEPR theory, what is the molecular geometry of SF4?")
add_paragraph("A) Tetrahedral")
add_paragraph("B) Square planar")
add_paragraph("C) Seesaw")
add_paragraph("D) Octahedral")
add_paragraph("")

add_paragraph("3. Which element has the highest electronegativity?")
add_paragraph("A) Fluorine")
add_paragraph("B) Oxygen")
add_paragraph("C) Chlorine")
add_paragraph("D) Nitrogen")
add_paragraph("")

add_paragraph("4. The ideal gas law assumes that gas particles:")
add_paragraph("A) Have significant intermolecular forces")
add_paragraph("B) Occupy a significant volume")
add_paragraph("C) Have elastic collisions")
add_paragraph("D) Move in curved paths")
add_paragraph("")

add_paragraph("5. Which intermolecular force is primarily responsible for the high boiling point of water?")
add_paragraph("A) London dispersion forces")
add_paragraph("B) Dipole-dipole interactions")
add_paragraph("C) Hydrogen bonding")
add_paragraph("D) Ion-dipole interactions")
add_paragraph("")

add_paragraph("6. What is the oxidation state of sulfur in H2SO4?")
add_paragraph("A) +2")
add_paragraph("B) +4")
add_paragraph("C) +6")
add_paragraph("D) -2")
add_paragraph("")

add_paragraph("7. According to Le Chatelier's principle, what happens to an exothermic reaction at equilibrium if the temperature is increased?")
add_paragraph("A) Shifts right")
add_paragraph("B) Shifts left")
add_paragraph("C) No change")
add_paragraph("D) Keq increases")
add_paragraph("")

add_paragraph("8. What type of orbital hybridization is present in the carbon atoms of ethene (C2H4)?")
add_paragraph("A) sp")
add_paragraph("B) sp2")
add_paragraph("C) sp3")
add_paragraph("D) dsp3")
add_paragraph("")

add_paragraph("9. Which of the following is an intensive property?")
add_paragraph("A) Mass")
add_paragraph("B) Volume")
add_paragraph("C) Density")
add_paragraph("D) Heat capacity")
add_paragraph("")

add_paragraph("10. A strong acid in aqueous solution:")
add_paragraph("A) Partially dissociates")
add_paragraph("B) Completely dissociates")
add_paragraph("C) Acts as a base")
add_paragraph("D) Forms a buffer")
add_paragraph("")

# ── Part II ──
add_paragraph("Part II: Short Answer")
add_paragraph("11. Briefly explain the difference between a sigma bond and a pi bond in terms of orbital overlap.")
add_paragraph("12. State Le Chatelier's principle in your own words.")
add_paragraph("13. Explain why the first ionization energy of oxygen is slightly lower than that of nitrogen, despite the general trend across a period.")
add_paragraph("14. Describe the process of sp3 hybridization in a carbon atom.")
add_paragraph("15. Why do atomic radii decrease across a period from left to right?")
add_paragraph("")

# ── Part III ──
add_paragraph("Part III: Calculation Problems")
add_paragraph("16. Stoichiometry: Iron(III) oxide reacts with carbon monoxide to produce iron and carbon dioxide. If 50.0 g of Fe2O3 reacts with excess CO, what mass of Fe is produced? (Show all work)")
add_paragraph("17. Gas Laws: A 5.00 L flask contains 0.250 moles of an ideal gas at 298 K. Calculate the pressure inside the flask in atmospheres.")
add_paragraph("18. Solution Concentration: Calculate the molarity of a solution prepared by dissolving 25.5 g of NaCl in enough water to make 500.0 mL of solution.")
add_paragraph("19. Thermochemistry: Using the standard enthalpies of formation provided in the reference table, calculate the standard enthalpy of reaction (Hess's Law) for the combustion of methane.")
add_paragraph("")

# ── Constants ──
add_paragraph("Physical Constants Reference")
add_paragraph("Constant | Value | Unit")
add_paragraph("Ideal Gas Constant (R) | 8.314 | J/(mol K)")
add_paragraph("Ideal Gas Constant (R) | 0.08206 | L atm/(mol K)")
add_paragraph("Avogadro's Number (NA) | 6.022 x 10^23 | mol^-1")
add_paragraph("Planck's Constant (h) | 6.626 x 10^-34 | J s")
add_paragraph("Speed of Light (c) | 2.998 x 10^8 | m/s")
add_paragraph("Standard Pressure | 1.00 | atm = 101.3 kPa")
add_paragraph("Specific Heat of Water | 4.184 | J/(g °C)")

doc.save("/home/ga/Documents/chem1311_midterm.odt")
PYEOF

python3 /tmp/create_midterm.py
chown ga:ga /home/ga/Documents/chem1311_midterm.odt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/chem1311_midterm.odt >/tmp/calligra.log 2>&1 < /dev/null &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "chem1311_midterm.odt"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "chem1311_midterm.odt" | awk '{print $1}')
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a "$WID"
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="