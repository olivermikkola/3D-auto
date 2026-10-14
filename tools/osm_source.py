"""Parse official OSM API XML responses into elements for osm_import."""
from pathlib import Path
import hashlib
import xml.etree.ElementTree as ET


def load_xml(paths):
    paths = [Path(p) for p in paths]
    nodes = {}
    ways_raw = {}
    relations_raw = []
    inputs = []

    for path in paths:
        inputs.append({
            "name": path.name,
            "path": str(path.resolve()),
            "bytes": path.stat().st_size,
        })
        for event, elem in ET.iterparse(path, events=("end",)):
            tag_name = elem.tag
            if tag_name == "node":
                nid = int(elem.attrib["id"])
                lat = float(elem.attrib["lat"])
                lon = float(elem.attrib["lon"])
                tags = {t.attrib["k"]: t.attrib["v"] for t in elem.findall("tag")}
                nodes[nid] = (lat, lon, tags)
                elem.clear()
            elif tag_name == "way":
                wid = int(elem.attrib["id"])
                nds = [int(nd.attrib["ref"]) for nd in elem.findall("nd")]
                tags = {t.attrib["k"]: t.attrib["v"] for t in elem.findall("tag")}
                ways_raw[wid] = (wid, nds, tags)
                elem.clear()
            elif tag_name == "relation":
                rid = int(elem.attrib["id"])
                tags = {t.attrib["k"]: t.attrib["v"] for t in elem.findall("tag")}
                members = [{
                    "type": m.attrib.get("type"),
                    "ref": int(m.attrib.get("ref", 0)),
                    "role": m.attrib.get("role", ""),
                } for m in elem.findall("member")]
                relations_raw.append((rid, members, tags))
                elem.clear()

    elements = []
    seen = set()

    for wid, (wid, nds, tags) in ways_raw.items():
        key = ("way", wid)
        if key in seen:
            continue
        geom = []
        for nid in nds:
            if nid in nodes:
                geom.append({"lat": nodes[nid][0], "lon": nodes[nid][1]})
        if len(geom) < 2:
            continue
        seen.add(key)
        elements.append({
            "type": "way",
            "id": wid,
            "nodes": nds,
            "geometry": geom,
            "tags": tags,
        })

    for nid, (lat, lon, tags) in nodes.items():
        key = ("node", nid)
        if tags and key not in seen:
            seen.add(key)
            elements.append({
                "type": "node",
                "id": nid,
                "lat": lat,
                "lon": lon,
                "tags": tags,
            })

    for rid, members, tags in relations_raw:
        key = ("relation", rid)
        if key in seen:
            continue
        seen.add(key)
        expanded_members = []
        for m in members:
            ref = m["ref"]
            if m["type"] == "way":
                way_match = ways_raw.get(ref)
                if way_match:
                    geom = [
                        {"lat": nodes[nid][0], "lon": nodes[nid][1]}
                        for nid in way_match[1] if nid in nodes
                    ]
                    expanded_members.append({
                        "type": "way",
                        "ref": ref,
                        "role": m["role"],
                        "geometry": geom,
                    })
        elements.append({
            "type": "relation",
            "id": rid,
            "tags": tags,
            "members": expanded_members,
        })

    return {
        "elements": elements,
        "source": {
            "kind": "OSM API XML",
            "inputs": inputs,
            "total_elements": len(elements),
        },
    }
