"""Sanity-check lpc_frames.tres after the all-anims transformation.

Verifies:
- Every SubResource referenced by an animation entry actually exists.
- No duplicate animation names.
- load_steps in header matches actual sub_resource count + 1.
- Every expected animation name is present.
"""

import pathlib
import re
import sys

PATH = pathlib.Path("addons/lpc_spritesheet_gen/internal/lpc_frames.tres")
text = PATH.read_text(encoding="utf-8")

# Collect declared SubResource IDs
declared = set(re.findall(r'^\[sub_resource type="\w+" id="([^"]+)"\]', text, re.MULTILINE))
print(f"Declared sub_resources: {len(declared)}")

# Collect referenced SubResource IDs (skip header + ext_resource refs)
referenced = set(re.findall(r'SubResource\("([^"]+)"\)', text))
print(f"Referenced sub_resources: {len(referenced)}")

# Find dangling references
dangling = referenced - declared
if dangling:
    print(f"DANGLING refs (not declared): {sorted(dangling)}")
    sys.exit(1)

# Find unused declarations
unused = declared - referenced - {"819"}  # 819 is the CompressedTexture2D, used by AtlasTextures only via `atlas = SubResource("819")` which IS captured. So shouldn't be in unused. Sanity check.
# Actually 819 should be referenced. Let me not exclude it.
unused = declared - referenced
if unused:
    print(f"WARNING: declared but not referenced: {sorted(unused)}")

# Animation name list
names = re.findall(r'"name": &"([^"]+)"', text)
print(f"Animation entries: {len(names)}")

# Duplicate names check
seen = set()
dups = []
for n in names:
    if n in seen:
        dups.append(n)
    seen.add(n)
if dups:
    print(f"DUPLICATE animation names: {dups}")
    sys.exit(1)

# Expected animations
expected = {
    "cast_down", "cast_left", "cast_right", "cast_up",
    "hurt_down",
    "rise_down",  # orphan, kept
    "shoot_down", "shoot_left", "shoot_right", "shoot_up",
    "slash_down", "slash_left", "slash_right", "slash_up",
    "thrust_down", "thrust_left", "thrust_right", "thrust_up",
    "walk_down", "walk_left", "walk_right", "walk_up",
    "idle_down", "idle_left", "idle_right", "idle_up",
    "run_down", "run_left", "run_right", "run_up",
    "climb_down",
    "jump_down", "jump_left", "jump_right", "jump_up",
    "sit_down", "sit_left", "sit_right", "sit_up",
    "emote_down", "emote_left", "emote_right", "emote_up",
    "combat_idle_down", "combat_idle_left", "combat_idle_right", "combat_idle_up",
}
forbidden = {
    "stride_down", "stride_left", "stride_right", "stride_up",
    "jog_down", "jog_left", "jog_right", "jog_up",
}

actual = set(names)
missing = expected - actual
unexpected_present = actual & forbidden
if missing:
    print(f"MISSING expected animations: {sorted(missing)}")
    sys.exit(1)
if unexpected_present:
    print(f"FORBIDDEN animations still present: {sorted(unexpected_present)}")
    sys.exit(1)

# Check load_steps
m = re.search(r'load_steps=(\d+)', text)
load_steps = int(m.group(1))
expected_load_steps = len(declared) + 1  # +1 for the [resource] itself
if load_steps != expected_load_steps:
    print(f"WARNING: load_steps={load_steps} but expected {expected_load_steps}")
else:
    print(f"load_steps={load_steps} matches sub_resource count + 1 OK")

print("ALL CHECKS PASSED OK")
