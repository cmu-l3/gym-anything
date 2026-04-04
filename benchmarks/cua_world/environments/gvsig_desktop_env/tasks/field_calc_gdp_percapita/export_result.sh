#!/bin/bash
echo "=== Exporting field_calc_gdp_percapita result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF' > /tmp/field_calc_gdp_percapita_result.json
import json, sys, os
try:
    from osgeo import ogr

    shp = '/home/ga/gvsig_exports/countries_gdp_percapita.shp'
    src = '/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp'

    result = {
        'file_exists': os.path.isfile(shp),
        'feature_count': None,
        'source_feature_count': None,
        'has_gdp_pcap_field': False,
        'fields': [],
        'nonzero_gdp_pcap_count': 0,
        'negative_gdp_pcap_count': 0,
        'sample_values': {},
        'error': None,
    }

    ds_src = ogr.Open(src)
    if ds_src:
        lyr_src = ds_src.GetLayer()
        result['source_feature_count'] = lyr_src.GetFeatureCount()
        ds_src = None

    if not result['file_exists']:
        print(json.dumps(result))
        sys.exit(0)

    ds = ogr.Open(shp)
    if ds is None:
        result['error'] = 'ogr.Open returned None'
        print(json.dumps(result))
        sys.exit(0)

    lyr = ds.GetLayer()
    result['feature_count'] = lyr.GetFeatureCount()

    defn = lyr.GetLayerDefn()
    fields = [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())]
    result['fields'] = fields[:30]
    fields_upper = [f.upper() for f in fields]
    result['has_gdp_pcap_field'] = 'GDP_PCAP' in fields_upper

    if result['has_gdp_pcap_field']:
        # Find the exact field name (case may vary)
        field_name = fields[fields_upper.index('GDP_PCAP')]
        nonzero = 0
        negative = 0
        sample = {}
        for feat in lyr:
            name = feat.GetField('NAME') or feat.GetField('name') or ''
            val = feat.GetField(field_name)
            if val is not None:
                if val > 0:
                    nonzero += 1
                if val < 0:
                    negative += 1
                if name in ('United States', 'Germany', 'China', 'Brazil', 'Nigeria'):
                    sample[name] = val
        result['nonzero_gdp_pcap_count'] = nonzero
        result['negative_gdp_pcap_count'] = negative
        result['sample_values'] = sample
        lyr.ResetReading()

    ds = None
    print(json.dumps(result))

except Exception as e:
    import traceback
    print(json.dumps({'error': str(e), 'tb': traceback.format_exc()}))
PYEOF

chmod 666 /tmp/field_calc_gdp_percapita_result.json 2>/dev/null || true
echo "Result JSON:"
cat /tmp/field_calc_gdp_percapita_result.json
echo ""
echo "=== Export Complete ==="
