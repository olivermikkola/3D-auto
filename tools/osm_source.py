"""Parse official OSM API XML responses into elements for osm_import."""
from pathlib import Path
import hashlib
import xml.etree.ElementTree as ET


def load_xml(paths):
    paths = [Path(p) for p in paths]
    nodes = {}
    ways_raw = []
    relations_raw = []
    inputs = []

    for path in paths:
        data = path.read_bytes()
        inputs.append({
            "name": path.name,
            "path": str(path.resolve()),
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })
        root = ET.fromstring(data)
        if root.tag != "osm":
            raise ValueError(f"expected OSM XML root in {path}")
        for n in root.findall("node"):
            nid = int(n.attrib["id"])
            lat = float(n.attrib["lat"])
            lon = float(n.attrib["lon"])
            tags = {t.attrib["k"]: t.attrib["v"] for t in n.findall("tag")}
            nodes[nid] = (lat, lon, tags)
        for w in root.findall("way"):
            wid = int(w.attrib["id"])
            nds = [int(nd.attrib["ref"]) for nd in w.findall("nd")]
            tags = {t.attrib["k"]: t.attrib["v"] for t in w.findall("tag")}
            ways_raw.append((wid, nds, tags))
        for r in root.findall("relation"):
            rid = int(r.attrib["id"])
            tags = {t.attrib["k"]: t.attrib["v"] for t in r.findall("tag")}
            members = [{
                "type": m.attrib.get("type"),
                "ref": int(m.attrib.get("ref", 0)),
                "role": m.attrib.get("role", ""),
            } for m in r.findall("member")]
            relations_raw.append((rid, members, tags))

    elements = []
    seen = set()

    for wid, nds, tags in ways_raw:
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

    # Multipolygons and buildings represented as relations.
    for rid, members, tags in relations_raw:
        key = ("relation", rid)
        if key in seen:
            continue
        seen.add(key)
        expanded_members = []
        for m in members:
            ref = m["ref"]
            if m["type"] == "way":
                way_match = next((w for w in ways_raw if w[0] == ref), None)
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
