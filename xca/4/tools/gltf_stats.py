#!/usr/bin/env python3
"""Prints triangles, materials and bounding box per glTF file. Usage: gltf_stats.py <dir-or-files...>"""
import json, sys, pathlib

def stats(path):
    data = json.loads(pathlib.Path(path).read_text())
    acc = data["accessors"]
    tris = 0
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for mesh in data.get("meshes", []):
        for prim in mesh["primitives"]:
            if "indices" in prim:
                tris += acc[prim["indices"]]["count"] // 3
            else:
                tris += acc[prim["attributes"]["POSITION"]]["count"] // 3
            pos = acc[prim["attributes"]["POSITION"]]
            for i in range(3):
                lo[i] = min(lo[i], pos["min"][i])
                hi[i] = max(hi[i], pos["max"][i])
    size = [round(hi[i] - lo[i], 2) for i in range(3)]
    return tris, len(data.get("materials", [])), len(data.get("meshes", [])), size

for arg in sys.argv[1:]:
    p = pathlib.Path(arg)
    files = sorted(p.glob("*.gltf")) if p.is_dir() else [p]
    for f in files:
        t, m, n, s = stats(f)
        print(f"{f.stem}\t{t}\t{m}\t{n}\t{s[0]}x{s[1]}x{s[2]}")
