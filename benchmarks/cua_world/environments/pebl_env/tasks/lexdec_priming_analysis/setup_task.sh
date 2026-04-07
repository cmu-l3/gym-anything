#!/bin/bash
echo "=== Setting up lexdec_priming_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate realistic, publication-quality synthetic data simulating the English Lexicon Project
# and the Semantic Priming Project, saving the strict ground truth out-of-bounds for the verifier.
python3 << 'PYEOF'
import csv
import random
import math
import json
import os

random.seed(42)

# Dependency-free approximation of the inverse standard normal CDF for d-prime ground-truth
def norm_ppf(p):
    if p < 0.00001: return -4.265
    if p > 0.99999: return 4.265
    a1, a2, a3, a4, a5, a6 = -3.969683028665376e+01,  2.209460984245205e+02, -2.759285104469687e+02,  1.383577518672690e+02, -3.066479806614716e+01,  2.506628277459239e+00
    b1, b2, b3, b4, b5 = -5.447609879822406e+01,  1.615858368580409e+02, -1.556989798598866e+02,  6.680131188771972e+01, -1.328068155288572e+01
    c1, c2, c3, c4, c5, c6 = -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00,  4.374664141464968e+00,  2.938163982698783e+00
    d1, d2, d3, d4 = 7.784695709041462e-03,  3.224671290700398e-01,  2.445134137142996e+00,  3.754408661907416e+00
    p_low = 0.02425
    p_high = 1 - p_low
    if p < p_low:
        q = math.sqrt(-2*math.log(p))
        return (((((c1*q+c2)*q+c3)*q+c4)*q+c5)*q+c6) / ((((d1*q+d2)*q+d3)*q+d4)*q+1)
    elif p <= p_high:
        q = p - 0.5
        r = q*q
        return (((((a1*r+a2)*r+a3)*r+a4)*r+a5)*r+a6)*q / (((((b1*r+b2)*r+b3)*r+b4)*r+b5)*r+1)
    else:
        q = math.sqrt(-2*math.log(1-p))
        return -(((((c1*q+c2)*q+c3)*q+c4)*q+c5)*q+c6) / ((((d1*q+d2)*q+d3)*q+d4)*q+1)

participants = [f'sub-{i:02d}' for i in range(1, 21)] + ['sub-99']
trials_per_condition = 30
conditions = ['related_word', 'unrelated_word', 'related_nonword', 'unrelated_nonword']

data = []
gt = {'participants': {}, 'group_means': {}}

words_pool = ["APPLE", "CHAIR", "HOUSE", "WATER", "LIGHT", "RIVER", "TRAIN", "PAPER", "MUSIC", "PLANT",
              "DOCTOR", "NURSE", "BREAD", "BUTTER", "CAT", "DOG", "SALT", "PEPPER", "KING", "QUEEN"]
nonwords_pool = ["BLINT", "FROSP", "GLAMP", "SNARF", "TWEAL", "CRONK", "VLEEP", "SPROD", "ZORB", "FLIG",
                 "PRONT", "TRISP", "SLIRM", "CHURB", "KLEEP", "BLORF", "SMEEL", "FRUND", "KROSP", "PLIMP"]

for p in participants:
    is_fake = (p == 'sub-99')
    p_data = []
    
    base_rt = random.gauss(600, 50)
    priming = random.gauss(40, 10)
    lexicality = random.gauss(80, 20)
    
    hr_prob = 0.95 if not is_fake else 0.50
    cr_prob = 0.90 if not is_fake else 0.50
    
    trial_num = 1
    
    for cond in conditions:
        for _ in range(trials_per_condition):
            if cond == 'related_word':
                target_type = 'word'
                prime_relation = 'related'
                expected_rt = base_rt - priming/2
            elif cond == 'unrelated_word':
                target_type = 'word'
                prime_relation = 'unrelated'
                expected_rt = base_rt + priming/2
            elif cond == 'related_nonword':
                target_type = 'nonword'
                prime_relation = 'related'
                expected_rt = base_rt + lexicality
            else:
                target_type = 'nonword'
                prime_relation = 'unrelated'
                expected_rt = base_rt + lexicality
                
            if is_fake:
                # Contaminated participant logic (random guessing)
                rt = random.gauss(500, 60)
                is_correct = 1 if random.random() < 0.5 else 0
            else:
                # Real participants: Skewed log-normal distributions for human RT mapping
                sigma = 0.15
                mu = math.log(expected_rt) - (sigma**2)/2
                rt = random.lognormvariate(mu, sigma)
                
                prob = hr_prob if target_type == 'word' else cr_prob
                is_correct = 1 if random.random() < prob else 0
                
            response = target_type if is_correct else ('nonword' if target_type == 'word' else 'word')
            
            p_data.append({
                'participant_id': p,
                'trial': trial_num,
                'prime': random.choice(words_pool),
                'target': random.choice(words_pool) if target_type == 'word' else random.choice(nonwords_pool),
                'prime_relation': prime_relation,
                'target_type': target_type,
                'response': response,
                'correct': is_correct,
                'rt_ms': round(rt, 1) if is_correct else 0
            })
            trial_num += 1
            
    random.shuffle(p_data)
    data.extend(p_data)
    
    if not is_fake:
        # Calculate ground truth exacts
        uw_rts = [row['rt_ms'] for row in p_data if row['target_type']=='word' and row['prime_relation']=='unrelated' and row['correct']==1]
        rw_rts = [row['rt_ms'] for row in p_data if row['target_type']=='word' and row['prime_relation']=='related' and row['correct']==1]
        nw_rts = [row['rt_ms'] for row in p_data if row['target_type']=='nonword' and row['correct']==1]
        w_rts = [row['rt_ms'] for row in p_data if row['target_type']=='word' and row['correct']==1]
        
        uw_mean = sum(uw_rts)/len(uw_rts) if uw_rts else 0
        rw_mean = sum(rw_rts)/len(rw_rts) if rw_rts else 0
        nw_mean = sum(nw_rts)/len(nw_rts) if nw_rts else 0
        w_mean = sum(w_rts)/len(w_rts) if w_rts else 0
        
        priming_effect = uw_mean - rw_mean
        lex_effect = nw_mean - w_mean
        
        word_trials = [row for row in p_data if row['target_type']=='word']
        nonword_trials = [row for row in p_data if row['target_type']=='nonword']
        
        hits = sum(1 for row in word_trials if row['response']=='word')
        fas = sum(1 for row in nonword_trials if row['response']=='word')
        
        n_w = len(word_trials)
        n_nw = len(nonword_trials)
        
        hr = hits / n_w if n_w else 0
        far = fas / n_nw if n_nw else 0
        
        # Standard corrections
        if hr == 1: hr = 1 - 1/(2*n_w)
        if hr == 0: hr = 1/(2*n_w)
        if far == 1: far = 1 - 1/(2*n_nw)
        if far == 0: far = 1/(2*n_nw)
        
        d_prime = norm_ppf(hr) - norm_ppf(far)
        
        gt['participants'][p] = {
            'priming_effect_ms': round(priming_effect, 2),
            'lexicality_effect_ms': round(lex_effect, 2),
            'd_prime': round(d_prime, 3),
            'mean_rt_related_word_ms': round(rw_mean, 2),
            'mean_rt_unrelated_word_ms': round(uw_mean, 2),
            'mean_rt_nonword_ms': round(nw_mean, 2)
        }

p_keys = list(gt['participants'].keys())
gt['group_means']['mean_priming_effect_ms'] = sum(gt['participants'][p]['priming_effect_ms'] for p in p_keys) / len(p_keys)
gt['group_means']['mean_d_prime'] = sum(gt['participants'][p]['d_prime'] for p in p_keys) / len(p_keys)
gt['group_means']['mean_lexicality_effect_ms'] = sum(gt['participants'][p]['lexicality_effect_ms'] for p in p_keys) / len(p_keys)

os.makedirs('/var/lib/pebl/ground_truth', exist_ok=True)
with open('/var/lib/pebl/ground_truth/priming_ground_truth.json', 'w') as f:
    json.dump(gt, f)

os.makedirs('/home/ga/pebl/data', exist_ok=True)
with open('/home/ga/pebl/data/lexdec_priming_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant_id', 'trial', 'prime', 'target', 'prime_relation', 'target_type', 'response', 'correct', 'rt_ms'])
    writer.writeheader()
    writer.writerows(data)
PYEOF

chown ga:ga /home/ga/pebl/data/lexdec_priming_data.csv

# Record task start time (For strict anti-gaming timing checks)
date +%s > /tmp/task_start_time.txt

# Get ga user's DBUS session address to launch terminal properly
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal with instructions loaded
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Lexical Decision Semantic Priming Analysis ===; echo; echo Data file: ~/pebl/data/lexdec_priming_data.csv; echo Output target: ~/pebl/analysis/priming_report.json; echo; bash' > /tmp/lexdec_terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Initial Screenshot Context
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== lexdec_priming_analysis setup complete ==="