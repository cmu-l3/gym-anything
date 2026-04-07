#!/bin/bash
echo "=== Setting up build_master_detail_explorer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Python script to generate 15 real medication tiddlers
cat << 'EOF' > /tmp/gen_meds.py
import os

tiddlers_dir = "/home/ga/mywiki/tiddlers"
os.makedirs(tiddlers_dir, exist_ok=True)

meds = [
    ("Lisinopril", "ACE Inhibitor", "Hypertension, Heart failure", "Dry cough, Dizziness, Hyperkalemia", "Lisinopril competitively inhibits angiotensin-converting enzyme (ACE), preventing the conversion of angiotensin I to angiotensin II, a potent vasoconstrictor."),
    ("Metformin", "Biguanide", "Type 2 Diabetes Mellitus", "Gastrointestinal upset, Lactic acidosis", "Metformin decreases hepatic glucose production, decreases intestinal absorption of glucose, and improves insulin sensitivity by increasing peripheral glucose uptake and utilization."),
    ("Atorvastatin", "HMG-CoA Reductase Inhibitor (Statin)", "Hyperlipidemia, Cardiovascular disease prevention", "Myalgia, Elevated liver enzymes", "Atorvastatin competitively inhibits HMG-CoA reductase, the rate-limiting enzyme that converts 3-hydroxy-3-methylglutaryl-coenzyme A to mevalonate, a precursor of sterols, including cholesterol."),
    ("Amlodipine", "Calcium Channel Blocker (Dihydropyridine)", "Hypertension, Angina", "Peripheral edema, Flushing", "Amlodipine inhibits calcium ion influx across cell membranes selectively, with a greater effect on vascular smooth muscle cells than on cardiac muscle cells."),
    ("Levothyroxine", "Thyroid Hormone", "Hypothyroidism", "Palpitations, Weight loss, Anxiety", "Synthetic form of thyroxine (T4), an endogenous hormone secreted by the thyroid gland, which is converted to its active metabolite, L-triiodothyronine (T3)."),
    ("Albuterol", "Beta-2 Adrenergic Agonist", "Asthma, COPD", "Tachycardia, Tremor", "Albuterol is a relatively selective beta2-adrenergic bronchodilator. It activates adenyl cyclase, which yields an increase in cyclic AMP, resulting in bronchial smooth muscle relaxation."),
    ("Omeprazole", "Proton Pump Inhibitor", "GERD, Peptic ulcer disease", "Headache, Abdominal pain", "Omeprazole is a proton pump inhibitor that suppresses gastric acid secretion by specific inhibition of the H+/K+-ATPase in the gastric parietal cell."),
    ("Losartan", "Angiotensin II Receptor Blocker (ARB)", "Hypertension, Diabetic nephropathy", "Dizziness, Hyperkalemia", "Losartan is a selective, competitive angiotensin II receptor type 1 (AT1) antagonist, reducing vasoconstriction and aldosterone secretion."),
    ("Gabapentin", "Anticonvulsant / GABA Analog", "Neuropathic pain, Partial seizures", "Somnolence, Dizziness", "Gabapentin is structurally related to the neurotransmitter GABA but does not modify GABAA or GABAB radioligand binding. Its exact mechanism is unknown but involves binding to the alpha-2-delta subunit of voltage-gated calcium channels."),
    ("Hydrochlorothiazide", "Thiazide Diuretic", "Hypertension, Edema", "Hypokalemia, Hyponatremia, Hyperuricemia", "Hydrochlorothiazide inhibits sodium chloride transport in the distal convoluted tubule, causing increased excretion of sodium and water."),
    ("Sertraline", "Selective Serotonin Reuptake Inhibitor (SSRI)", "Major Depressive Disorder, Anxiety", "Insomnia, Nausea, Sexual dysfunction", "Sertraline is a potent and selective inhibitor of neuronal serotonin (5-HT) reuptake and has only very weak effects on norepinephrine and dopamine neuronal reuptake."),
    ("Simvastatin", "HMG-CoA Reductase Inhibitor", "Hyperlipidemia", "Myopathy, Headache", "Simvastatin is a specific inhibitor of 3-hydroxy-3-methylglutaryl-coenzyme A (HMG-CoA) reductase, the enzyme that catalyzes the conversion of HMG-CoA to mevalonate."),
    ("Montelukast", "Leukotriene Receptor Antagonist", "Asthma, Allergic rhinitis", "Headache, Neuropsychiatric events", "Montelukast selectively and competitively binds to the cysteinyl leukotriene receptor (CysLT1), blocking the actions of leukotrienes LTD4, C4, and E4."),
    ("Escitalopram", "Selective Serotonin Reuptake Inhibitor (SSRI)", "Depression, Generalized Anxiety Disorder", "Somnolence, Nausea", "Escitalopram is the S-enantiomer of citalopram. It enhances serotonergic activity in the central nervous system resulting from its inhibition of CNS neuronal reuptake of serotonin (5-HT)."),
    ("Rosuvastatin", "HMG-CoA Reductase Inhibitor", "Hypercholesterolemia", "Myalgia, Abdominal pain", "Rosuvastatin is a selective and competitive inhibitor of HMG-CoA reductase, the rate-limiting enzyme that converts 3-hydroxy-3-methylglutaryl coenzyme A to mevalonate.")
]

for title, dclass, ind, se, text in meds:
    filename = os.path.join(tiddlers_dir, f"{title.replace(' ', '_')}.tid")
    content = f"title: {title}\ntags: Medication\ndrug-class: {dclass}\nindications: {ind}\ncommon-side-effects: {se}\n\n{text}"
    with open(filename, 'w') as f:
        f.write(content)

print(f"Generated {len(meds)} medication tiddlers.")
EOF

# Execute the generation script
python3 /tmp/gen_meds.py
chown -R ga:ga /home/ga/mywiki/tiddlers

# Ensure TiddlyWiki is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Restarting TiddlyWiki server..."
    pkill -f tiddlywiki 2>/dev/null || true
    sleep 2
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Ensure Firefox is open to the correct URL and maximized
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
DISPLAY=:1 xdotool key F5  # Refresh to ensure new tiddlers are loaded
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="