#!/usr/bin/env python3
"""Convert USGS QuakeML to SeisComP XML format."""
import sys
from xml.etree import ElementTree as ET
import seiscomp.datamodel as scdm
import seiscomp.core as sccore
import seiscomp.io as scio

def convert(input_path, output_path):
    ns = '{http://quakeml.org/xmlns/bed/1.2}'
    tree = ET.parse(input_path)
    root = tree.getroot()

    ep_elem = root.find(f'{ns}eventParameters')
    if ep_elem is None:
        ep_elem = root.find('{http://quakeml.org/xmlns/quakeml/1.2}eventParameters')
    if ep_elem is None:
        for child in root:
            if 'eventParameters' in child.tag:
                ep_elem = child
                break

    ep = scdm.EventParameters()

    for evt_elem in ep_elem.findall(f'{ns}event'):
        origin_elem = evt_elem.find(f'{ns}origin')
        mag_elem = evt_elem.find(f'{ns}magnitude')

        time_val = origin_elem.find(f'{ns}time/{ns}value').text
        lat = float(origin_elem.find(f'{ns}latitude/{ns}value').text)
        lon = float(origin_elem.find(f'{ns}longitude/{ns}value').text)
        depth_m = float(origin_elem.find(f'{ns}depth/{ns}value').text)
        depth_km = depth_m / 1000.0

        mag_val = float(mag_elem.find(f'{ns}mag/{ns}value').text)
        mag_type = mag_elem.find(f'{ns}type').text

        # Create Origin
        o = scdm.Origin.Create()
        o.setCreationInfo(scdm.CreationInfo())
        o.creationInfo().setAgencyID('USGS')
        ot = sccore.Time()
        ot.fromString(time_val.replace('Z', ''), '%FT%T.%f')
        o.setTime(scdm.TimeQuantity(ot))
        o.setLatitude(scdm.RealQuantity(lat))
        o.setLongitude(scdm.RealQuantity(lon))
        o.setDepth(scdm.RealQuantity(depth_km))
        o.setEvaluationMode(scdm.MANUAL)
        ep.add(o)

        # Create Magnitude
        m = scdm.Magnitude.Create()
        m.setCreationInfo(scdm.CreationInfo())
        m.creationInfo().setAgencyID('USGS')
        m.setMagnitude(scdm.RealQuantity(mag_val))
        m.setType(mag_type)
        m.setOriginID(o.publicID())
        o.add(m)

        # Create Event
        e = scdm.Event.Create()
        e.setCreationInfo(scdm.CreationInfo())
        e.creationInfo().setAgencyID('USGS')
        e.setPreferredOriginID(o.publicID())
        e.setPreferredMagnitudeID(m.publicID())

        # Add description if available
        desc_elem = evt_elem.find(f'{ns}description')
        if desc_elem is not None:
            text_elem = desc_elem.find(f'{ns}text')
            if text_elem is not None:
                desc = scdm.EventDescription()
                desc.setText(text_elem.text)
                desc.setType(scdm.EARTHQUAKE_NAME)
                e.add(desc)

        # Add OriginReference to link event to origin
        oref = scdm.OriginReference()
        oref.setOriginID(o.publicID())
        e.add(oref)

        ep.add(e)

    ar = scio.XMLArchive()
    ar.create(output_path)
    ar.setFormattedOutput(True)
    ar.writeObject(ep)
    ar.close()
    print(f'Converted {input_path} -> {output_path}')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <input_quakeml> <output_scml>')
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
