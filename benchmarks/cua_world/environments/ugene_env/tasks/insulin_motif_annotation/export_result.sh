#!/bin/bash
echo "=== Exporting insulin_motif_annotation results ==="

# Capture final screenshot for evidence
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Run evaluation parsing using Python
python3 << 'PYEOF'
import sys, re, json

result = {
    "gb_exists": False,
    "gb_valid": False,
    "report_exists": False,
    "report_content": "",
    "annotations": {
        "TATA_box": 0,
        "E_box": 0,
        "GC_box": 0,
        "polyA_signal": 0,
        "CArG_box": 0
    },
    "valid_annotations": {
        "TATA_box": 0,
        "E_box": 0,
        "GC_box": 0,
        "polyA_signal": 0,
        "CArG_box": 0
    },
    "original_seq_len": 0,
    "error": None
}

motifs_to_check = ["TATA_box", "E_box", "GC_box", "polyA_signal", "CArG_box"]
gb_path = "/home/ga/UGENE_Data/results/insulin_motifs_annotated.gb"

try:
    with open(gb_path, 'r') as f:
        content = f.read()
        result["gb_exists"] = True
        
        if "LOCUS" in content and "ORIGIN" in content:
            result["gb_valid"] = True
            
            # Extract sequence from ORIGIN block
            origin_match = re.search(r'ORIGIN\s+(.*?)\/\/', content, re.DOTALL)
            if origin_match:
                seq = re.sub(r'[\d\s\n]', '', origin_match.group(1)).upper()
                result["original_seq_len"] = len(seq)
                
                # Extract FEATURES block
                features_section = re.search(r'FEATURES\s+Location/Qualifiers(.*?)(?=ORIGIN)', content, re.DOTALL)
                if features_section:
                    feat_text = features_section.group(1)
                    
                    # Split into individual features
                    feats = re.split(r'\n {5}(?=\w)', "\n" + feat_text)
                    for feat in feats:
                        if not feat.strip(): continue
                        
                        match = re.search(r'^(\S+)\s+(.+)', feat, re.DOTALL)
                        if not match: continue
                        feat_key = match.group(1)
                        rest = match.group(2)
                        
                        # Parse coordinates
                        loc_match = re.match(r'((?:complement\()?(\d+)\.\.(\d+)\)?)', rest)
                        if not loc_match: continue
                        start = int(loc_match.group(2))
                        end = int(loc_match.group(3))
                        
                        # Check if feature key or qualifiers contain a target motif name
                        found_motif = None
                        for m in motifs_to_check:
                            if m == feat_key or f'"{m}"' in rest or f'={m}' in rest or f'name "{m}"' in rest:
                                found_motif = m
                                break
                        
                        if found_motif:
                            result["annotations"][found_motif] += 1
                            if 1 <= start <= end <= len(seq):
                                subseq = seq[start-1:end]
                                def rc(s):
                                    return s.translate(str.maketrans("ACGT", "TGCA"))[::-1]
                                
                                matched = False
                                if found_motif == "TATA_box" and (subseq == "TATAAA" or rc(subseq) == "TATAAA"): matched = True
                                elif found_motif == "GC_box" and (subseq == "GGGCGG" or rc(subseq) == "GGGCGG"): matched = True
                                elif found_motif == "polyA_signal" and (subseq == "AATAAA" or rc(subseq) == "AATAAA"): matched = True
                                elif found_motif == "E_box" and (re.match(r'^CA[ACGT]{2}TG$', subseq) or re.match(r'^CA[ACGT]{2}TG$', rc(subseq))): matched = True
                                elif found_motif == "CArG_box" and (re.match(r'^CC[AT]{6}GG$', subseq) or re.match(r'^CC[AT]{6}GG$', rc(subseq))): matched = True
                                
                                if matched:
                                    # Increment only if sequence actually matches the motif specification
                                    result["valid_annotations"][found_motif] += 1

except FileNotFoundError:
    pass
except Exception as e:
    result["error"] = str(e)

# Read the summary report
report_path = "/home/ga/UGENE_Data/results/motif_report.txt"
try:
    with open(report_path, 'r') as f:
        result["report_exists"] = True
        result["report_content"] = f.read()
except FileNotFoundError:
    pass

# Write to standard JSON path for verifier access
with open("/tmp/insulin_motif_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export completed successfully.")
PYEOF

echo "Result JSON stored in /tmp/insulin_motif_result.json"
echo "=== Export complete ==="