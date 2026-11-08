#!/usr/bin/env bash
# Runs character_test.gd in a scratch project with the contract fakes for world classes.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
game="$(cd "$here/.." && pwd)"
godot="${GODOT:-godot}"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/scripts/core" "$scratch/scripts/characters" "$scratch/ui/touch" "$scratch/tests" "$scratch/scenes" "$scratch/assets"
printf 'config_version=5\n\n[application]\nconfig/name="character-test"\nconfig/features=PackedStringArray("4.6")\n\n[physics]\n\n2d/default_gravity=0.0\n' > "$scratch/project.godot"
for name in tuning sandal stack arena; do
	cp "$here/fakes/$name.gd.txt" "$scratch/scripts/$name.gd"
done
cp "$game"/scripts/core/{entity_visual,visual_set,skin_ref,settings_ref,audio_ref}.gd "$scratch/scripts/core/"
mkdir -p "$scratch/scripts/fx" "$scratch/scripts/heroes"
cp "$game"/scripts/heroes/hero_def.gd "$scratch/scripts/heroes/"
cp "$game"/scripts/fx/fx_ref.gd "$scratch/scripts/fx/"
cp "$game"/scripts/characters/*.gd "$scratch/scripts/characters/"
cp "$game"/ui/touch/{virtual_joystick,dash_button,touch_style}.gd "$scratch/ui/touch/"
cp -r "$game/scenes/character.tscn" "$game/scenes/visuals" "$scratch/scenes/"
cp -r "$game/assets/icons" "$scratch/assets/"
cp "$here/character_test.gd" "$scratch/tests/"
sed -i 's|res://scripts/characters/|res://scripts/characters/|' "$scratch/scenes/character.tscn"
"$godot" --headless --path "$scratch" --import >/dev/null 2>&1 || true
"$godot" --headless --path "$scratch" --script res://tests/character_test.gd
