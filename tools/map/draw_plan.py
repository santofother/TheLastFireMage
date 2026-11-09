"""Draw a review SVG from the same metre-scale layout used by Godot."""
from html import escape
from pathlib import Path
import argparse
import json
import math

HERE = Path(__file__).resolve().parent
PLAN = json.loads((HERE / "layout.json").read_text())
SCALE = 5.15


def sample(rows, z):
    for i, (a, b) in enumerate(zip(rows, rows[1:])):
        if z <= b[0] or i == len(rows) - 2:
            t = max(0, min(1, (z - a[0]) / (b[0] - a[0])))
            return [u + (v - u) * t for u, v in zip(a[1:], b[1:])]
    raise ValueError("No layout rows")


def edges(band, z):
    lanes = [sample(rows, z) for rows in PLAN["streets"]]
    outside = [sample(rows, z)[0] for rows in PLAN["edges"]]
    left = [outside[0]] + [x + w / 2 for x, _, w in lanes]
    right = [x - w / 2 for x, _, w in lanes] + [outside[1]]
    return left[band], right[band]


def xy(x, z):
    return 70 + (x + 36) * SCALE, 140 + (z + 67) * SCALE


def points(coords):
    return " ".join(f"{a:.2f},{b:.2f}" for a, b in (xy(x, z) for x, z in coords))


def polygon(coords, fill, stroke="none", width=.8, label=None):
    title = f"<title>{escape(label)}</title>" if label else ""
    return f'<polygon points="{points(coords)}" fill="{fill}" stroke="{stroke}" stroke-width="{width}">{title}</polygon>'


def line(coords, color, width, dash=""):
    return (f'<polyline points="{points(coords)}" fill="none" stroke="{color}" stroke-width="{width}" '
            f'stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="{dash}"/>')


def label(x, y, content, kind="note", attrs=""):
    return f'<text x="{x:.1f}" y="{y:.1f}" class="{kind}" {attrs}>{escape(content)}</text>'


def pin(x, z, text):
    a, b = xy(x, z)
    return (f'<circle cx="{a:.1f}" cy="{b:.1f}" r="10" fill="#483a58" stroke="#fff8ed" stroke-width="1.5"/>'
            + label(a, b + .5, text, "pin", 'text-anchor="middle" dominant-baseline="central"'))


def draw():
    out = ['''<svg xmlns="http://www.w3.org/2000/svg" width="940" height="934" viewBox="0 0 940 934" role="img" aria-labelledby="title description">
<title id="title">Salmara village — Party walls</title>
<desc id="description">A plan drawn from the playable town data, with adjoining houses, narrow winding alleys, staggered rock stairs and the arched waterfront.</desc>
<style>
text{font-family:system-ui,sans-serif;fill:#302a2b}.tag{font-size:11px;letter-spacing:3px;font-weight:700;fill:#80594d}.title{font-family:Georgia,serif;font-size:43px}.sub{font-size:14px;fill:#655852}.heading{font-family:Georgia,serif;font-size:22px}.note{font-size:14px;fill:#554843}.small{font-size:11px;letter-spacing:1px;fill:#655852}.pin{font-size:11px;font-weight:800;fill:#fff8ed}.maplabel{font-size:10px;font-weight:750;letter-spacing:1px;fill:#47382d}
</style>
<rect width="940" height="934" fill="#f8f2e7"/>
<rect x="46" y="126" width="430" height="751" rx="9" fill="#d4e3dc" stroke="#b8c8bf"/>
<path d="M510 127v751" stroke="#dbccba"/>
''']
    out += [label(46, 33, "THE LAST FIRE MAGE  /  LAYOUT A · V7", "tag"),
            label(45, 79, "Salmara: Party walls", "title"),
            label(47, 105, "Playtest plan drawn from the Godot level  ·  north is uphill", "sub")]
    out.append(polygon([(-24,-53),(-15,-60.2),(17,-61.6),(25,-53)], "#cab79b", "#756452"))
    for rows in PLAN["streets"]:
        out.append(polygon([(x-w/2,z) for z,x,_,w in rows] + [(x+w/2,z) for z,x,_,w in rows[::-1]], "#f3dfba"))
    for _, band, z, width, _ in PLAN["cuts"]:
        left, *_ = sample(PLAN["streets"][band-1], z)
        right, *_ = sample(PLAN["streets"][band], z)
        out.append(polygon([(left,z-width/2),(right,z-width/2),(right,z+width/2),(left,z+width/2)], "#b3a18d"))
        for i in range(1,11):
            x = left + (right-left)*i/11
            out.append(line([(x,z-width*.38),(x,z+width*.38)], "#776556", .7))
    roof_colours = {"rose":"#b66f59","peach":"#ce8c6a","lime":"#dca979","ochre":"#d79761",
                    "honey":"#bf8157","cream":"#d4a177"}
    knots = sorted({row[0] for rows in PLAN["streets"] + PLAN["edges"] for row in rows})
    for band, district in enumerate(PLAN["districts"]):
        for lot in district["lots"]:
            name,z0,z1,floors,side,_,paint,roof,*_ = lot
            zs = [z0] + [z for z in knots if z0 < z < z1] + [z1]
            pairs = [edges(band,z) for z in zs]
            shape = [(p[0],z) for p,z in zip(pairs,zs)] + [(p[1],z) for p,z in zip(pairs[::-1],zs[::-1])]
            out.append(polygon(shape, roof_colours[paint] if floors else "#93a173", "#795c4d", .8,
                               f"{name}: {floors} floors" if floors else name))
            if floors and roof != "flat":
                out.append(line([((left+right)*.5,z) for (left,right),z in zip(pairs,zs)], "#fff0d8", .7, "2 2"))
            if floors:
                p = xy(sum(edges(band,(z0+z1)/2)) / 2, (z0+z1)/2)
                out.append(label(*p, str(floors), "maplabel", 'text-anchor="middle" dominant-baseline="central"'))
    data = PLAN["waterfront"]
    lo, hi, _, front = data["quay"]
    left, right, end = data["pier"]
    out.append(polygon([(x,front) for x,*_ in data["beach"]] +
                       [(x,water+(toe-water)*.23) for x,_,water,toe in data["beach"][::-1]], "#d8b982", "#f4dfb1", 1.8))
    out.append(line([(x,shoulder) for x,shoulder,*_ in data["beach"]], "#b69968", .9))
    out.append(polygon([(lo,32),(hi,32),(hi,front),(right,front),(right,end),
                        (left,end),(left,front),(lo,front)], "#c8b8a0", "#816f5b", 1.25))
    out.append(label(*xy(-19,37.4), "QUAY", "maplabel"))
    out.append(label(*xy(-23,54.9), "CRESCENT", "maplabel"))
    for name,x,z,_,yaw,paint in data["boats"]:
        a,b = xy(x,z)
        colour = {"rust":"#9d6249","teal":"#48776f","plum":"#795a6b"}[paint]
        out.append(f'<path transform="translate({a:.2f} {b:.2f}) rotate({-math.degrees(yaw):.2f})" '
                   f'd="M0 -13Q8 -6 5 7L3 12H-3L-5 7Q-8 -6 0 -13Z" fill="{colour}" stroke="#fff0d8" stroke-width="1">'
                   f'<title>{escape(name)}</title></path>')
    out.extend([pin(-6.3,19.4,"1"),pin(-8.1,-17.75,"2"),pin(6.3,-14.7,"3"),pin(-15.4,61.6,"4")])
    x = 533
    out += [label(x, 162, "01  /  THE STREET FABRIC", "tag"),
                label(x, 192, "Houses make the street", "heading"),
                label(x, 221, "Party walls join homes into continuous rows."),
                label(x, 243, "Footprints, roof directions and floor heights vary."),
                label(x, 265, "Numbers show storeys; green marks garden courts."),
                label(x, 310, "02  /  TWO WAYS UP", "tag"),
                label(x, 340, "Winding lanes and rock stairs", "heading"),
                label(x, 369, "1   The spine climbs gently, with a local dip."),
                label(x, 391, "2   Limekiln Stair climbs along the stone cut."),
                label(x, 413, "3   Potters Cut climbs to the upper lane."),
                label(x, 435, "The two stair cuts meet the spine at different bends."),
                label(x, 480, "03  /  AT THE WATER", "tag"),
                label(x, 510, "A broader crescent", "heading"),
                label(x, 539, "4   Sand grades from dry shoulder to shallow water."),
                label(x, 561, "The arched pier stays. Four new fishing boats"),
                label(x, 583, "sit at separate positions around the harbour."),
                label(x, 628, "04  /  PLAYTEST PRIORITIES", "tag"),
                label(x, 658, "Check scale and chase routes", "heading"),
                label(x, 687, "1 m villagers · 1.4 m mage"),
                label(x, 709, "Try tight turns, both cuts and the loft windows."),
                label(x, 731, "Furniture, lighting fixtures and planting come later.")]
    out += [f'<path d="M70 841h{10*SCALE:.1f}" stroke="#47382d" stroke-width="2"/>',
            label(70, 860, "10 m", "small"), label(46, 903, "VILLAGE GREYBOX  /  PLAN FOR PLAYTEST", "small"), "</svg>"]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(draw(), encoding="utf-8")
