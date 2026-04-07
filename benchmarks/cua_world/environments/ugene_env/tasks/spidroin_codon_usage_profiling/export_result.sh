#!/bin/bash
echo "=== Exporting task results ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, re

res = {
    "fasta_exists": False,
    "fasta_valid": False,
    "protein_length": 0,
    "gly_ala_fraction": 0.0,
    "codon_table_exists": False,
    "codon_table_has_64": False,
    "report_exists": False,
    "report_lines_found": 0,
    "reported_length": None,
    "reported_abundant_aa": None,
    "reported_gly_codon": None,
    "reported_ala_codon": None
}

fasta_path = "/home/ga/UGENE_Data/spidroin/results/masp1_protein.fasta"
if os.path.exists(fasta_path):
    res["fasta_exists"] = True
    with open(fasta_path) as f:
        content = f.read().strip()
        if content.startswith(">"):
            res["fasta_valid"] = True
            seq = "".join(content.split("\n")[1:])
            seq = re.sub(r'[^A-Za-z]', '', seq).upper()
            res["protein_length"] = len(seq)
            if len(seq) > 0:
                g_count = seq.count('G')
                a_count = seq.count('A')
                res["gly_ala_fraction"] = (g_count + a_count) / len(seq)

for ext in [".csv", ".txt", ".tsv"]:
    codon_path = f"/home/ga/UGENE_Data/spidroin/results/masp1_codon_usage{ext}"
    if os.path.exists(codon_path):
        res["codon_table_exists"] = True
        with open(codon_path) as f:
            text = f.read()
            codons_found = len(set(re.findall(r'\b[ACGTUacgtu]{3}\b', text)))
            if codons_found >= 60:
                res["codon_table_has_64"] = True
        break

report_path = "/home/ga/UGENE_Data/spidroin/results/masp1_analysis_report.txt"
if os.path.exists(report_path):
    res["report_exists"] = True
    with open(report_path) as f:
        text = f.read()
        
    m_len = re.search(r'Protein length:\s*(\d+)', text, re.IGNORECASE)
    if m_len:
        res["reported_length"] = int(m_len.group(1))
        res["report_lines_found"] += 1
        
    m_aa = re.search(r'Most abundant amino acid:\s*([A-Za-z]+)', text, re.IGNORECASE)
    if m_aa:
        res["reported_abundant_aa"] = m_aa.group(1)
        res["report_lines_found"] += 1
        
    m_gly = re.search(r'Most frequent Glycine codon:\s*([ACGTUacgtu]{3})', text, re.IGNORECASE)
    if m_gly:
        res["reported_gly_codon"] = m_gly.group(1).upper()
        res["report_lines_found"] += 1
        
    m_ala = re.search(r'Most frequent Alanine codon:\s*([ACGTUacgtu]{3})', text, re.IGNORECASE)
    if m_ala:
        res["reported_ala_codon"] = m_ala.group(1).upper()
        res["report_lines_found"] += 1

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result JSON written"
cat /tmp/task_result.json
echo "=== Export complete ==="