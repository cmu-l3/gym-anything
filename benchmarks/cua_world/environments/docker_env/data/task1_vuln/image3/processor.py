"""
AcmeCorp Data Processing Utility
Processes CSV exports and generates summary reports.
"""
import sys
import json
import datetime

def process_data(records):
    """Process a list of records and return summary statistics."""
    if not records:
        return {"count": 0, "summary": {}}

    numeric_fields = [k for k, v in records[0].items()
                      if isinstance(v, (int, float))]
    summary = {}
    for field in numeric_fields:
        values = [r[field] for r in records if field in r]
        summary[field] = {
            "min": min(values),
            "max": max(values),
            "avg": sum(values) / len(values),
            "count": len(values),
        }

    return {"count": len(records), "summary": summary,
            "processed_at": datetime.datetime.utcnow().isoformat()}


def main():
    sample_records = [
        {"id": i, "value": i * 2.5, "score": 100 - i}
        for i in range(1, 51)
    ]
    result = process_data(sample_records)
    print(json.dumps(result, indent=2))
    print("Processing complete.", file=sys.stderr)


if __name__ == "__main__":
    main()
