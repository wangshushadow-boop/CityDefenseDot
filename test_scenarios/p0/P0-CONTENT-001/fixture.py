"""Write an original two-rig glTF sample in metres, with embedded geometry."""
import base64
import json
import struct


def build(path):
    data = bytearray()
    views = []
    accessors = []
    nodes = [{"name": "MountedDemo", "children": []}]
    meshes, skins, tracks = [], [], []

    def attribute(rows, kind, fmt, component, **bounds):
        while len(data) % 4:
            data.append(0)
        offset = len(data)
        for row in rows:
            data.extend(struct.pack("<" + fmt * len(row), *row))
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data) - offset})
        accessors.append(dict(bufferView=len(views) - 1, componentType=component,
                              count=len(rows), type=kind, **bounds))
        return len(accessors) - 1

    def node(name, parent=0, **options):
        index = len(nodes)
        nodes.append({"name": name, **options})
        nodes[parent].setdefault("children", []).append(index)
        return index

    for name, limb, socket, height, width, depth, x in [
        ("Rider", "Arm", "WeaponGrip", 1.8, 0.32, 0.21, -1.0),
        ("Horse", "HorseSpine", "Saddle", 1.55, 0.44, 1.10, 1.0),
    ]:
        group = node(name, translation=[x, 0, 0])
        root = node(name + "Root", group)
        joint = node(limb, root, translation=[0, height / 2, 0])
        node(socket, joint, translation=[width, height / 4, 0])
        vertices = [(sx * width, y, sz * depth) for y in (0, height)
                    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        positions = attribute(vertices, "VEC3", "f", 5126,
                              min=[-width, 0, -depth], max=[width, height, depth])
        joints = attribute([(int(i >= 4), 0, 0, 0) for i in range(8)],
                           "VEC4", "B", 5121)
        weights = attribute([(1, 0, 0, 0)] * 8, "VEC4", "f", 5126)
        indices = [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1,
                   1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0]
        faces = attribute([(i,) for i in indices], "SCALAR", "H", 5123)
        meshes.append({"name": name + "Body", "primitives": [{
            "attributes": {"POSITION": positions, "JOINTS_0": joints, "WEIGHTS_0": weights},
            "indices": faces}]})
        # glTF inverse bind matrices use column-major order in mesh-local space.
        matrices = [(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, y, 0, 1)
                    for y in (0, -height / 2)]
        skins.append({"skeleton": root, "joints": [root, joint],
                      "inverseBindMatrices": attribute(matrices, "MAT4", "f", 5126)})
        node(name + "Skin", group, mesh=len(meshes) - 1, skin=len(skins) - 1)
        tracks.append({"sampler": 0, "target": {"node": joint, "path": "rotation"}})

    node("Spawn_A", translation=[-3, 0, 0])
    node("Gate_A", translation=[3, 0, 0])
    times = attribute([(0,), (0.5,), (1,)], "SCALAR", "f", 5126, min=[0], max=[1])
    motion = attribute([(0, 0, 0, 1), (0, 0, 0.6, 0.8), (0, 0, 0, 1)],
                       "VEC4", "f", 5126)
    uri = "data:application/octet-stream;base64," + base64.b64encode(data).decode("ascii")
    model = {"asset": {"version": "2.0", "generator": "recollection P0 fixture.py"},
             "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
             "skins": skins, "buffers": [{"uri": uri, "byteLength": len(data)}],
             "bufferViews": views, "accessors": accessors, "animations": [{
                 "name": "Strike", "samplers": [{"input": times, "output": motion}],
                 "channels": tracks}]}
    path.write_text(json.dumps(model, separators=(",", ":")), encoding="utf-8")

