"""Author the harbour's timber fishing boat variants in Blender, then export to Godot.

Run Blender --background --python tools/map/build_fishing_boats.py from this checkout.
The origin is the walkable deck. The hull's station table is mirrored in generate.gd.
"""
from mathutils import Vector
from pathlib import Path
import bpy

OUT = Path(__file__).resolve().parents[2] / "the-last-fire-mage/game/map/props/fishing_boats"
# Longitudinal station, half beam at the sheer, height above the working deck.
STATIONS = [(-2.60, 0.04, 0.62), (-2.36, 0.37, 0.45), (-1.89, 0.68, 0.31),
            (-1.23, 0.97, 0.23), (-0.45, 1.11, 0.20), (0.46, 1.12, 0.22),
            (1.28, 0.99, 0.28), (1.95, 0.78, 0.36), (2.36, 0.62, 0.43)]
PAINT = {"teal": (.035, .30, .29), "rust": (.47, .10, .043), "plum": (.22, .08, .25)}


def mat(name, colour):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*colour, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Roughness"].default_value = .86
    m.roughness = .86
    return m


def mesh(name, points, faces, material):
    data = bpy.data.meshes.new(name)
    data.from_pydata(points, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def beam(name, a, b, width, depth, material):
    start, end = Vector(a), Vector(b)
    delta = end - start
    bpy.ops.mesh.primitive_cube_add(size=1, location=(start + end) * .5)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = width, depth, delta.length
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = delta.to_track_quat('Z', 'Y')
    obj.data.materials.append(material)


def strip(name, rows, material):
    n = len(rows[0])
    mesh(name, sum(rows, []),
         [(r*n+i, r*n+i+1, (r+1)*n+i+1, (r+1)*n+i)
          for r in range(len(rows)-1) for i in range(n-1)], material)


def build(variant):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    keel = mat("Tarred keel", (.070, .046, .036))
    paint = mat("Painted strake", PAINT[variant])
    stripe = mat("Faded cream band", (.69, .51, .29))
    gunwale = mat("Oiled oak", (.21, .099, .051))
    inner = mat("Inside oak", (.27, .164, .092))
    boards = [mat(f"Deck board {i}", c) for i, c in enumerate(
        [(.40,.27,.147), (.33,.20,.11), (.36,.23,.126), (.44,.30,.17)])]
    # Blender +Y becomes Godot -Z on glTF export.
    def p(x, z, h):
        return (x, -z, h)
    for side in [-1, 1]:
        strips = []
        for fullness, low, sheer in [(0.055, -1.99, .20), (.49, -1.74, .20), (.82, -1.30, .22),
                                      (.94, -.92, .24), (.99, -.41, .53), (1, 0, 1)]:
            strips.append([p(side*w*fullness, z*(.86+.14*fullness), low+h*sheer)
                           for z,w,h in STATIONS])
        if side == 1:
            strips = [row[::-1] for row in strips]
        for i,m in enumerate([keel, keel, paint, stripe, paint]):
            strip(f"Carvel planking {side} {i}", strips[i:i+2], m)
        sheer = [p(side*w, z, h) for z,w,h in STATIONS]
        inset = [p(side*w*.91, z, h-.065) for z,w,h in STATIONS]
        deck = [p(side*w*.93, z, -.015) for z,w,h in STATIONS]
        strip("Inner lining", [deck, inset] if side == 1 else [deck[::-1], inset[::-1]], inner)
        for a,b in zip(sheer, sheer[1:]):
            beam("Rounded gunwale", a, b, .068, .073, gunwale)
        for z,w,h in STATIONS[2:-1:2]:
            beam("Steam bent rib", p(side*w*.90,z,.015), p(side*w*.96,z,h-.04), .052, .040, gunwale)
    for i,((za,wa,_),(zb,wb,_)) in enumerate(zip(STATIONS,STATIONS[1:])):
        for j in range(9):
            a, b = (j/9*2-1)*.94, ((j+1)/9*2-1)*.94
            mesh("Long deck plank", [p(a*wa,za,0), p(a*wb,zb,0), p(b*wb,zb,0), p(b*wa,za,0)],
                 [(0,1,2,3)], boards[(j*3+1)%4])
    z,w,h = STATIONS[-1]
    mesh("Raked stern transom", [p(-w,z,h),p(w,z,h),p(w*.27,z*.88,-1.73),p(-w*.27,z*.88,-1.73)],
         [(0,1,2,3)], paint)
    beam("Stern cap", p(-w,z,h), p(w,z,h), .085,.10,gunwale)
    beam("Stem", p(0,-2.22,-1.54), p(0,-2.64,.68), .09,.12,gunwale)
    beam("Rudder stock", p(0,2.28,-1.43), p(0,2.46,.65), .095,.12,gunwale)
    mesh("Rudder blade", [p(.02,2.28,-1.43),p(.02,2.62,-1.61),p(.02,2.57,-.72),p(.02,2.39,-.58)],
         [(0,1,2,3)], gunwale)
    beam("Tiller", p(0,2.45,.59), p(.19,1.74,.43), .075,.06,gunwale)
    for zz,ww in [(-1.74,.62),(1.58,.75)]:
        beam("Thwart", p(-ww,zz,.16), p(ww,zz,.16), .27,.085,gunwale)
    # Mesh surfaces are exported double-sided. Combine by material to keep the asset lightweight.
    for m in list(bpy.data.materials):
        objs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.data.materials[0] == m]
        if not objs:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        objs[0].name = m.name
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"fishing_boat_{variant}.glb"), export_format='GLB',
                              export_yup=True, export_cameras=False, export_lights=False)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for variant in PAINT:
        build(variant)
