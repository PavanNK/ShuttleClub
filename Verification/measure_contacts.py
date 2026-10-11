"""Measure actual debug contact evidence; does not generate or alter gameplay."""
import json
import math
from pathlib import Path
import re
import sys

pattern = re.compile(
    r"STRING CONTACT: (player|milo), cork SIMD3<Float>\(([^)]+)\), "
    r"strings SIMD3<Float>\(([^)]+)\), fraction ([^\s]+)"
)
report = {}
for filename in sys.argv[1:]:
    events = []
    for match in pattern.finditer(Path(filename).read_text()):
        side, cork, strings, fraction = match.groups()
        cork = [float(value) for value in cork.split(",")]
        strings = [float(value) for value in strings.split(",")]
        events.append({"side": side, "cork": cork, "strings": strings,
                       "gap_metres": math.dist(cork, strings), "fraction": float(fraction)})
    report[Path(filename).name] = {
        "scope": "Full process output; capture and process intervals are not exactly identical.",
        "player_contacts": sum(e["side"] == "player" for e in events),
        "milo_contacts": sum(e["side"] == "milo" for e in events),
        "maximum_gap_metres": max((e["gap_metres"] for e in events), default=None),
        "within_cork_radius_plus_6_micrometres": all(e["gap_metres"] <= 0.040006 for e in events) if events else None,
        "events": events,
    }
print(json.dumps(report, indent=2))
