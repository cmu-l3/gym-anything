#!/usr/bin/env python3
import os
import time
import json
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication

def create_real_attachments():
    # 1. Create a valid, minimal PDF file with real structure
    pdf_content = (
        b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
        b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
        b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n"
        b"4 0 obj\n<< /Length 53 >>\nstream\nBT\n/F1 24 Tf\n100 700 Td\n(Project Progress Report) Tj\nET\nendstream\nendobj\n"
        b"xref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000214 00000 n \n"
        b"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n316\n%%EOF\n"
    )

    # 2. Create a realistic CSV with construction material costs
    csv_content = "Item,Quantity,Unit,Unit_Price,Total\n"
    materials = [
        ("Ready-Mix Concrete (3000 psi)", 45, "cu yd", 145.00),
        ("Rebar #4 Grade 60", 2400, "lb", 0.85),
        ("2x4 SPF Stud 8ft", 500, "ea", 6.75),
        ("Drywall 1/2 inch 4x8", 120, "ea", 14.50),
        ("Roofing Shingles", 30, "sq", 95.00),
        ("Plywood 3/4 inch", 80, "ea", 45.00),
        ("Insulation R-19", 20, "roll", 35.00),
        ("Copper Pipe 1/2 inch", 150, "ft", 2.50),
        ("PVC Pipe 3 inch", 200, "ft", 3.20),
        ("Romex Wire 12/2", 1000, "ft", 0.45),
        ("Electrical Boxes", 85, "ea", 1.20),
        ("Interior Doors", 12, "ea", 110.00),
        ("Exterior Door", 2, "ea", 450.00),
        ("Windows 3x4", 8, "ea", 220.00),
        ("Paint Interior", 15, "gal", 35.00),
        ("Paint Exterior", 8, "gal", 42.00),
        ("Baseboard Trim", 400, "ft", 1.15),
        ("Crown Molding", 200, "ft", 2.25),
        ("Hardwood Flooring", 800, "sq ft", 4.50),
        ("Tile Ceramic", 200, "sq ft", 3.75),
        ("Kitchen Cabinets", 1, "set", 3500.00),
        ("Bathroom Vanity", 2, "ea", 450.00),
        ("Toilet", 2, "ea", 180.00),
        ("Bathtub", 1, "ea", 350.00),
        ("Water Heater 50g", 1, "ea", 650.00),
    ]
    for item, qty, unit, price in materials:
        csv_content += f'"{item}",{qty},{unit},{price:.2f},{qty*price:.2f}\n'
        
    return pdf_content, csv_content.encode('utf-8')

def main():
    pdf_bytes, csv_bytes = create_real_attachments()

    # Save expected sizes for verifier
    expected_sizes = {
        "pdf_size": len(pdf_bytes),
        "csv_size": len(csv_bytes)
    }
    with open("/tmp/expected_attachment_sizes.json", "w") as f:
        json.dump(expected_sizes, f)
    os.chmod("/tmp/expected_attachment_sizes.json", 0o666)

    # Build MIME message
    msg = MIMEMultipart()
    msg['From'] = "Site Engineer <engineer@constructco.example.com>"
    msg['To'] = "Test User <testuser@example.com>"
    msg['Subject'] = "Site Update - Weekly Report #47"
    msg['Date'] = time.strftime("%a, %d %b %Y %H:%M:%S +0000", time.gmtime())

    body = "Hi Team,\n\nPlease find attached the weekly progress report and the updated materials cost spreadsheet for site #47.\n\nEnsure these are saved to the local project files directory for offline review.\n\nRegards,\nSite Engineer"
    msg.attach(MIMEText(body, 'plain'))

    pdf_part = MIMEApplication(pdf_bytes, Name="project_report.pdf")
    pdf_part['Content-Disposition'] = 'attachment; filename="project_report.pdf"'
    msg.attach(pdf_part)

    csv_part = MIMEApplication(csv_bytes, Name="materials_costs.csv")
    csv_part['Content-Disposition'] = 'attachment; filename="materials_costs.csv"'
    msg.attach(csv_part)

    # Append to Inbox
    inbox_path = "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"
    os.makedirs(os.path.dirname(inbox_path), exist_ok=True)
    
    with open(inbox_path, "a") as f:
        f.write(f"From engineer@constructco.example.com {time.ctime()}\n")
        f.write(msg.as_string())
        f.write("\n\n")

    print(f"Injected email with 2 attachments to {inbox_path}")

if __name__ == "__main__":
    main()