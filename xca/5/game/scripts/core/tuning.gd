class_name Tuning
extends Resource
## Every number the design names. Change a value in
## [code]res://assets/tuning/default_tuning.tres[/code], never in code.
##
## Hitboxes, radii and speeds live here. Art never decides them.

const DEFAULT_PATH: String = "res://assets/tuning/default_tuning.tres"

static var _default: Tuning

@export_group("Match")
## Characters per team.
@export_range(1, 6, 1) var team_size: int = 3
## Throws each attacker gets in the topple phase.
@export_range(1, 5, 1) var throws_per_attacker: int = 1
## Round wins needed to win the match.
@export_range(1, 9, 1) var rounds_to_win: int = 3
## Team the human controls. The other team is all bots.
@export_range(0, 1, 1) var human_team: int = 0
## Bot skill from 0 (easy) to 1 (hard).
@export_range(0.0, 1.0, 0.05) var bot_difficulty: float = 0.5

@export_group("Team colours")
## Colour of the human's team on characters, thrown sandals, HUD pips and role markers. Reads 7.7:1 on the arena floor.
@export var friendly_color: Color = Color("40bfff")
## Colour of the other team. Reads 5.0:1 on the arena floor and stays apart from blue under red-green colour blindness.
@export var enemy_color: Color = Color("ff5230")
## Colour of a sandal nobody holds: the stack and loose sandals.
@export var neutral_sandal_color: Color = Color("f4d58d")

@export_group("Arena")
## Centre of the arena and of the stack spot, in world pixels.
@export var arena_centre: Vector2 = Vector2(640.0, 360.0)
## Half of the playable width and height.
@export var arena_half_extents: Vector2 = Vector2(540.0, 300.0)
## Thickness of each wall.
@export_range(10.0, 200.0, 1.0, "suffix:px") var wall_thickness: float = 60.0

@export_group("Throw ring")
## Radius of the ring attackers stand on. A throw flies exactly this far, so a throw aimed at the stack lands on it.
@export_range(150.0, 290.0, 1.0, "suffix:px") var throw_radius: float = 260.0
## Angle between two queued attackers on the throw ring.
@export_range(10.0, 60.0, 1.0, "degrees") var throw_ring_spacing_degrees: float = 24.0

## Distance a full-power manual throw flies. It is longer than the throw ring, so a full-power throw aimed at the stack passes through it.
@export_range(150.0, 600.0, 1.0, "suffix:px") var max_throw_range: float = 340.0
## Lowest power a manual throw flies at, so a short drag still leaves the hand fast enough to count as a flight.
@export_range(0.05, 0.5, 0.01) var min_throw_power: float = 0.2

@export_group("Orbit")
## Radius of the ring the defenders circle on in the topple phase.
@export_range(60.0, 200.0, 1.0, "suffix:px") var orbit_radius: float = 100.0
## Angular speed of the defender ring.
@export_range(0.2, 3.0, 0.05, "suffix:rad/s") var orbit_speed: float = 1.0
## The share of orbit time an attacker needs a clean lane to the stack. Checked by the world test.
@export_range(0.3, 0.95, 0.01) var min_clean_lane_ratio: float = 0.6

@export_group("Stack")
## A stack sandal moved farther than this from its spot topples the stack.
@export_range(5.0, 200.0, 1.0, "suffix:px") var topple_distance: float = 40.0
## Gap between touching stack sandals.
@export_range(0.0, 20.0, 0.5, "suffix:px") var stack_gap: float = 2.0
## Radius of the ring the three pyramid bases stand on. Neighbours touch at about 1.15 times the sandal radius.
@export_range(10.0, 60.0, 0.5, "suffix:px") var pyramid_base_radius: float = 16.8
## Angle from vertical at which each standing sandal leans toward the centre, so the tips meet at one apex.
@export_range(5.0, 60.0, 1.0, "suffix:deg") var pyramid_lean_degrees: float = 25.0
## Sandals in the stack. The teepee layout needs exactly 3, all equal, 120 degrees apart.
@export_range(3, 3, 1) var stack_size: int = 3

@export_group("Pyramid build")
## Radius around the centre spot where sandals count as delivered and where a build can run.
@export_range(40.0, 200.0, 1.0, "suffix:px") var build_zone_radius: float = 90.0
## Seconds one build step takes for a bot at full skill. The human answers a timed prompt instead.
@export_range(0.3, 5.0, 0.05, "suffix:s") var build_step_seconds: float = 1.2
## Seconds a missed prompt costs before the same step prompts again.
@export_range(0.0, 3.0, 0.05, "suffix:s") var miss_penalty_seconds: float = 0.8
## Seconds a complete pyramid must stand before the attackers win the round.
@export_range(0.0, 3.0, 0.05, "suffix:s") var build_stable_seconds: float = 0.5
## Seconds of scatter phase before the defenders win the round.
@export_range(10.0, 300.0, 1.0, "suffix:s") var scatter_time_limit: float = 60.0
## Seconds either side of the meeting time in which a tap prompt counts as a hit.
@export_range(0.1, 1.0, 0.01, "suffix:s") var qte_window_seconds: float = 0.3
## Seconds a tap prompt ring shrinks before it meets the target ring.
@export_range(0.5, 3.0, 0.05, "suffix:s") var qte_tap_seconds: float = 1.1
## Seconds a swipe prompt waits before it counts as a miss.
@export_range(0.5, 5.0, 0.05, "suffix:s") var qte_swipe_seconds: float = 1.8
## A swipe prompt answers to a drag at least this long, in CSS pixels.
@export_range(10.0, 120.0, 1.0, "suffix:px") var qte_swipe_min_css_px: float = 40.0
## True: the human build is the balance minigame. False: the tap and swipe prompts.
@export var build_balance_enabled: bool = true
## The sandal is steady while the lean stays under this share of the full lean.
@export_range(0.1, 0.9, 0.01) var balance_safe_band: float = 0.35
## Seconds the sandal must stay steady to lock a build step.
@export_range(0.2, 3.0, 0.05, "suffix:s") var balance_hold_seconds: float = 0.9
## Sideways push on the lean per second on the first step. Later steps push a little harder.
@export_range(0.0, 2.0, 0.01) var balance_wobble: float = 0.45
## Seconds at the start of a step before the wobble begins.
@export_range(0.0, 2.0, 0.05, "suffix:s") var balance_grace_seconds: float = 0.6
## How fast a leaning sandal falls further. Higher is less stable.
@export_range(0.0, 3.0, 0.05) var balance_instability: float = 0.9
## Lean change per second at full player input.
@export_range(0.5, 6.0, 0.1) var balance_control: float = 2.2
## Lean a single tap moves toward the centre.
@export_range(0.05, 0.6, 0.01) var balance_tap_nudge: float = 0.25
## Seconds a human stands still in the zone with all three sandals before the build starts alone.
@export_range(0.3, 5.0, 0.1, "suffix:s") var balance_auto_start_seconds: float = 1.5
## Camera zoom while the human builds.
@export_range(1.0, 3.0, 0.05) var build_zoom: float = 1.8
## Bot build time factor at difficulty 0. At difficulty 1 the factor is 1.
@export_range(1.0, 3.0, 0.05) var bot_build_slowdown: float = 1.25

@export_group("Sandal")
## Collision radius of a sandal.
@export_range(4.0, 60.0, 0.5, "suffix:px") var sandal_radius: float = 14.0
## Mass of a sandal.
@export_range(0.05, 5.0, 0.05) var sandal_mass: float = 0.4
## Linear damping. Higher stops a sandal sooner.
@export_range(0.0, 10.0, 0.1) var sandal_damping: float = 2.2
## Angular damping.
@export_range(0.0, 10.0, 0.1) var sandal_angular_damping: float = 3.0
## Bounce off walls and sandals.
@export_range(0.0, 1.0, 0.05) var sandal_bounce: float = 0.4
## Top speed a resting sandal keeps after a flying sandal hits it. A harder hit only nudges it.
@export_range(40.0, 900.0, 10.0, "suffix:px/s") var rest_hit_speed_cap: float = 200.0
## Speed a flying sandal needs to knock a placed teepee sandal loose. A slower touch does nothing.
@export_range(40.0, 900.0, 10.0, "suffix:px/s") var knock_min_speed: float = 450.0
## Below this speed a sandal is no longer in flight.
@export_range(10.0, 400.0, 1.0, "suffix:px/s") var flight_min_speed: float = 120.0
## Throw speed at power 1. A throw at power p flies at this speed times p.
@export_range(50.0, 3000.0, 10.0, "suffix:px/s") var throw_speed_max: float = 900.0
## Power of a pass, from 0 to 1.
@export_range(0.05, 1.0, 0.05) var pass_power: float = 0.75
## Power of a hit thrown at a foe, from 0 to 1. Fixed, so drag length never sets power.
@export_range(0.05, 1.0, 0.05) var hit_power: float = 1.0
## How far a pass bends around an attacker in the way.
@export_range(0.0, 90.0, 1.0, "degrees") var pass_bend_degrees: float = 32.0
## Distance from a pass line at which an attacker counts as in the way.
@export_range(10.0, 150.0, 1.0, "suffix:px") var pass_clearance: float = 46.0
## How fast a pass steers toward its receiver.
@export_range(0.0, 20.0, 0.1) var pass_turn_rate: float = 4.5
## Distance at which a receiver catches a pass.
@export_range(10.0, 100.0, 1.0, "suffix:px") var pass_catch_radius: float = 30.0
## Seconds before a pass stops steering.
@export_range(0.5, 10.0, 0.1, "suffix:s") var pass_max_time: float = 3.0

@export_group("Character")
## Collision radius of a character.
@export_range(6.0, 60.0, 0.5, "suffix:px") var character_radius: float = 18.0
## Walk speed.
@export_range(50.0, 800.0, 5.0, "suffix:px/s") var move_speed: float = 230.0
## Speed multiplier while carrying a sandal.
@export_range(0.1, 1.0, 0.05) var carry_speed_multiplier: float = 0.85
## Radius around the stack spot inside which a bot stops to build and defenders guard.
@export_range(10.0, 200.0, 1.0, "suffix:px") var place_radius: float = 60.0
## Radius around a character that picks up a sandal.
@export_range(10.0, 120.0, 1.0, "suffix:px") var pickup_radius: float = 34.0
## Distance in front of a character where a carried sandal sits.
@export_range(0.0, 80.0, 1.0, "suffix:px") var carry_offset: float = 22.0
## Seconds a thrown sandal ignores its thrower.
@export_range(0.0, 1.0, 0.01, "suffix:s") var throw_collision_grace: float = 0.25
## Impulse that sends a knocked teepee sandal away from the pyramid.
@export_range(0.0, 2000.0, 10.0) var knock_impulse: float = 144.0

@export_group("Guard")
## Width of the guard ring that starts at the edge of the build zone.
@export_range(10.0, 200.0, 1.0, "suffix:px") var guard_ring_width: float = 70.0
## Seconds an attacker is stunned after its guard block.
@export_range(0.1, 3.0, 0.05, "suffix:s") var guard_stun_seconds: float = 1.0
## Seconds after a block during which the same attacker cannot block again.
@export_range(0.5, 15.0, 0.1, "suffix:s") var guard_block_cooldown: float = 4.0
## Share of the speed a blocked sandal keeps when it ricochets off the guard.
@export_range(0.1, 1.0, 0.05) var block_bounce: float = 0.6

@export_group("Dash")
## Dash speed.
@export_range(100.0, 1500.0, 10.0, "suffix:px/s") var dash_speed: float = 620.0
## Dash length in time.
@export_range(0.05, 1.0, 0.01, "suffix:s") var dash_duration: float = 0.18
## Time before the next dash.
@export_range(0.1, 10.0, 0.1, "suffix:s") var dash_cooldown: float = 1.6

@export_group("Round timing")
## Pause on the coin flip.
@export_range(0.0, 5.0, 0.1, "suffix:s") var coin_flip_time: float = 1.2
## Seconds the human attacker has for the throw before the game throws for them.
@export_range(1.0, 30.0, 0.5, "suffix:s") var topple_throw_seconds: float = 6.0
## Seconds every thrown sandal must rest before the topple phase fails.
@export_range(0.1, 5.0, 0.1, "suffix:s") var topple_settle_time: float = 1.0
## Pause after a round before the next one starts.
@export_range(0.0, 5.0, 0.1, "suffix:s") var round_end_delay: float = 1.6

## True to run the 3, 2, 1 countdown after the coin flip and before every round. Tests that need a fast start turn it off.
@export var match_countdown: bool = true
## Seconds each countdown number stays on screen. The voice clips are under 0.8 s, so a step never talks over the next.
@export_range(1.0, 3.0, 0.1, "suffix:s") var countdown_step_time: float = 1.1
## Seconds of the round intro line before the numbers start. The longest intro clip is 1.7 s.
@export_range(0.0, 5.0, 0.1, "suffix:s") var countdown_intro_time: float = 1.8

@export_group("Throw controls")
## Half width of the cone, around the drag bearing, in which a drag can move the lock.
@export_range(5.0, 90.0, 1.0, "degrees") var lock_cone_degrees: float = 40.0
## A new lock must beat the current one by this angle, so the lock does not flicker between two targets.
@export_range(0.0, 30.0, 0.5, "degrees") var lock_hysteresis_degrees: float = 8.0
## A drag shorter than this many CSS pixels counts as a tap. A drag back inside it cancels.
@export_range(4.0, 60.0, 1.0, "suffix:px") var slop_px: float = 16.0
## Size of the fire button across, in CSS pixels. At least 72 keeps it easy to hit.
@export_range(44.0, 140.0, 1.0, "suffix:px") var fire_button_css_px: float = 72.0
## Gap between the fire button and the dash button, in CSS pixels. WCAG 2.5.8 needs at least 24.
@export_range(24.0, 80.0, 1.0, "suffix:px") var fire_dash_gap_css_px: float = 28.0
## Size of the aim stick base across, in CSS pixels.
@export_range(80.0, 220.0, 1.0, "suffix:px") var aim_stick_css_px: float = 132.0
## Seconds of idle before the first-time hint replays.
@export_range(2.0, 30.0, 0.5, "suffix:s") var hint_replay_seconds: float = 8.0
## Times the first-time hint replays before it stops for good.
@export_range(0, 10, 1) var hint_replay_limit: int = 3
## Milliseconds of vibration when the lock changes. Android Chrome only.
@export_range(0, 100, 1, "suffix:ms") var haptic_lock_ms: int = 10
## Milliseconds of vibration when a throw fires. Android Chrome only.
@export_range(0, 200, 1, "suffix:ms") var haptic_fire_ms: int = 25
## Colour of the world preview line and rings for the stack target.
@export var preview_stack_color: Color = Color("f4d58d")

@export_group("Game feel")
## Freeze length when a pass sandal hits an attacker.
@export_range(0.0, 0.5, 0.01, "suffix:s") var hit_stop_duration: float = 0.06
## Time scale during the last-throw slow-mo.
@export_range(0.05, 1.0, 0.05) var slow_motion_scale: float = 0.25
## Real seconds the last-throw slow-mo lasts.
@export_range(0.0, 3.0, 0.05, "suffix:s") var slow_motion_duration: float = 0.8


## Returns the shared tuning from [constant DEFAULT_PATH]. Every world node uses this one instance.
static func load_default() -> Tuning:
	if _default == null:
		_default = load(DEFAULT_PATH) as Tuning
		if _default == null:
			push_warning("Tuning: %s missing, using code defaults." % DEFAULT_PATH)
			_default = Tuning.new()
	return _default
