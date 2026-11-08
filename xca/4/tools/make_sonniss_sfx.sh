#!/usr/bin/env bash
# Builds the sound effects in godot/assets/audio from the staged Sonniss candidates.
# Peak levels are set per sound because loudness meters need 400 ms or more and most effects are shorter.
# Full scale effects clipped and buried the loops before, so the loudest shots sit at -3 dBFS.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/godot/audio_candidates"
out="$here/godot/assets/audio"

# name | candidate path | start s | length s | target peak dBFS | extra ffmpeg filter (optional)
specs=(
  "sfx_shot_pistol|pistol/gamemaster-revolver-shot-04|0.02|0.50|-3|"
  "sfx_shot_shotgun|shotgun/wavjunction-shotgun-fire-3|0.42|0.90|-3|"
  "sfx_shot_smg|smg/scorpion-vz61-double|0.06|0.24|-4|"
  "sfx_bat_swing|bat-swing/knife-swing-17|0.00|0.33|-6|"
  "sfx_bat_hit|bat-hit/wood-impact-23|0.00|0.45|-3|"
  "sfx_hit|bat-hit/punch-percussive-heavy-06|0.00|0.18|-5|"
  "sfx_zombie_hurt|bat-hit/wood-beating-flesh-soft-14|0.00|0.40|-6|"
  "sfx_poof|hurt-death/gorification-splat-soft-4|0.00|0.50|-6|"
  "sfx_hurt|hurt-death/bottlerocket-grunt-pain-male-10|0.00|0.46|-5|"
  "sfx_run_over|hurt-death/344-male-in-shock-4|0.00|0.57|-4|"
  "sfx_wave_clear|level-up/g4f-unlock-level-02|0.00|1.30|-7|"
  "sfx_wave_start|explosion/explosion-large-no-tail-03|0.00|1.00|-7|lowpass=f=900"
  "sfx_groan_1|zombie-groan/glitchedtones-groan-pitched-down-6|0.00|1.20|-8|"
  "sfx_groan_2|zombie-groan/glitchedtones-subject-b-groan-8|0.00|1.20|-8|"
  "sfx_groan_3|zombie-groan/smartsoundfx-zombie-idle-04|0.00|1.20|-8|"
  "sfx_ui_click|ui-click/bluezone-click-small-005|0.00|0.25|-8|"
  "sfx_hand_found|hero-select/sonicbat-positive-select-click-008|0.00|0.60|-8|"
  "sfx_hand_lost|ui-click/sonicbat-select-click-014|0.00|0.50|-9|asetrate=44100*0.75,aresample=44100"
  "sfx_calib_step|ui-confirm/chrisalan-confirm-notification-21|0.00|0.29|-8|"
  "sfx_lane_change|grenade-throw/noizboy-whoosh-2-1|0.00|0.25|-10|"
  "sfx_flick|bat-swing/noizboy-whoosh-1-15|0.00|0.37|-9|highpass=f=500"
  "sfx_weapon_cycle|ui-click/sonicbat-select-click-014|0.00|0.40|-8|"
  "sfx_weapon_equip|shotgun/ts-quick-pump|0.10|0.45|-6|"
  "sfx_combo_tick|pickup/fascinated-coin02|0.00|0.25|-9|"
  "sfx_combo_milestone|combo/impact-soundworks-triple-combo-hit|0.00|1.00|-6|"
  "sfx_pickup|pickup/gamemaster-collect-item-14|0.00|0.80|-7|"
  "sfx_camp_reached|level-up/ryk-power-up-level-up-2|0.00|1.40|-7|"
  "sfx_inspect_open|ui-confirm/rescopic-confirm-middle-12|0.00|0.70|-8|"
  "sfx_inspect_close|ui-confirm/rescopic-confirm-middle-12|0.00|0.70|-9|areverse"
  "sfx_clean_sparkle|pickup/ryk-collecting-orb-2|0.00|1.20|-9|"
  "sfx_grime_warning|music-bed/matiasmacsd-experimental-tension-057-bass|0.00|1.00|-8|"
)

encode() {
  local name="$1" file="$2" start="$3" length="$4" peak="$5" extra="$6"
  local filter="atrim=start=${start}:duration=${length},asetpts=PTS-STARTPTS"
  [[ -n "$extra" ]] && filter+=",${extra}"
  local fade_out
  fade_out=$(awk -v l="$length" 'BEGIN { printf "%.3f", (l > 0.2 ? 0.06 : 0.02) }')
  filter+=",afade=t=in:d=0.003,afade=t=out:st=$(awk -v l="$length" -v f="$fade_out" 'BEGIN { printf "%.3f", l - f }'):d=${fade_out}"
  local max
  max=$(ffmpeg -hide_banner -nostats -i "$src/$file.ogg" -af "$filter,volumedetect" -f null - 2>&1 | awk '/max_volume/ { print $5 }')
  local gain
  gain=$(awk -v t="$peak" -v m="$max" 'BEGIN { printf "%.2f", t - m }')
  ffmpeg -hide_banner -loglevel error -y -i "$src/$file.ogg" -af "$filter,volume=${gain}dB" \
    -ac 1 -ar 44100 -c:a libvorbis -q:a 2 "$out/$name.ogg"
  printf '%-22s %6s bytes  gain %6s dB\n' "$name" "$(stat -c %s "$out/$name.ogg")" "$gain"
}

for spec in "${specs[@]}"; do
  IFS='|' read -r name file start length peak extra <<< "$spec"
  encode "$name" "$file" "$start" "$length" "$peak" "$extra"
done

# The scrub loop is a band of wind noise with the tail crossfaded into the head, so it repeats without a click.
ffmpeg -hide_banner -loglevel error -y -i "$src/ambience-wind/soundrangers-wind-blustery-08-loop.ogg" -filter_complex "
  [0:a]highpass=f=1200,lowpass=f=6000,atrim=0:4.5,asetpts=PTS-STARTPTS,asplit=3[a][b][c];
  [a]atrim=0.5:3.5,asetpts=PTS-STARTPTS[body];
  [b]atrim=3.5:4.0,asetpts=PTS-STARTPTS,afade=t=out:d=0.5:curve=qsin[tail];
  [c]atrim=0:0.5,asetpts=PTS-STARTPTS,afade=t=in:d=0.5:curve=qsin[head];
  [tail][head]amix=inputs=2:duration=first:normalize=0[join];
  [body][join]concat=n=2:v=0:a=1,volume=-2dB" -ac 1 -ar 44100 -c:a libvorbis -q:a 2 "$out/sfx_scrub_loop.ogg"
printf '%-22s %6s bytes\n' sfx_scrub_loop "$(stat -c %s "$out/sfx_scrub_loop.ogg")"
