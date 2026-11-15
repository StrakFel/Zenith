extends Node
## Autoload "AudioManager": one place for background music and the audio buses.
##   * Two music tracks (Assets/Audio): "calm" (menus, briefings, rocket designer, results) and "action" (launch and active
##     mission phases). Scenes do not start music themselves - the manager asks the current scene for `music_mood()` and
##     crossfades. The music never restarts on scene changes (the autoload lives across all scenes).
##   * Loops are seamless: shortly before the end the track is crossfaded into itself (no mp3 padding gap).
##   * Buses: Music and SFX under Master. Settings: music_volume, sfx_volume, music_on (saved by GameState).
##   * Pause: the music keeps playing but is ducked.

const TRACKS := {
	"calm": "res://Assets/Audio/music_calm.mp3",
	"action": "res://Assets/Audio/music_action.mp3",
}
const FADE := 1.2            # seconds, mood change
const START_FADE := 0.35     # seconds, first start of the music (almost immediate)
const LOOP_FADE := 2.5       # seconds, loop crossfade
const SILENT := -60.0
const DUCK_DB := -9.0

var mood := ""
var _players: Array[AudioStreamPlayer] = []
var _active: AudioStreamPlayer
var _streams: Dictionary = {}
var _tweens: Dictionary = {}
var _poll := 0.0
var _duck := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = SILENT
		add_child(p)
		_players.append(p)
	_active = _players[0]
	for id in TRACKS:
		_stream(id)                 # preload both tracks now: no disk / decode hiccup at the first scene change
	GameState.settings_changed.connect(apply_settings)
	apply_settings()
	set_mood("calm")                # the music starts right away (the menu is calm); scenes may change the mood later


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var i := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, &"Master")


func _stream(id: String) -> AudioStreamMP3:
	if not _streams.has(id):
		var s := load(str(TRACKS[id])) as AudioStreamMP3
		if s != null:
			s.loop = false        # looping is done by the crossfade below
		_streams[id] = s
	return _streams[id]


## Volumes and the music switch from Settings.
func apply_settings() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	var mv := float(GameState.settings.get("music_volume", 1.0))
	var sv := float(GameState.settings.get("sfx_volume", 0.8))
	AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(mv, 0.0001)) + _duck)
	AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sv, 0.0001)))
	var on := bool(GameState.settings.get("music_on", true))
	AudioServer.set_bus_mute(mi, not on)
	if on and mood != "" and not _active.playing:
		var m := mood
		mood = ""
		set_mood(m)
	elif not on:
		for p in _players:
			p.stop()
		mood = mood            # remembered: music resumes in the same mood when switched on again


## "calm" or "action". Crossfades; asking for the current mood does nothing (so nothing restarts).
func set_mood(m: String) -> void:
	if not TRACKS.has(m):
		return
	if m == mood and _active.playing:
		return
	mood = m
	if not bool(GameState.settings.get("music_on", true)):
		return
	_crossfade(m, FADE)


func _crossfade(id: String, secs: float) -> void:
	var st := _stream(id)
	if st == null:
		return
	var old := _active
	var first := not old.playing
	var nxt: AudioStreamPlayer = _players[1] if old == _players[0] else _players[0]
	_kill_tween(nxt)
	nxt.stream = st
	nxt.volume_db = SILENT
	nxt.play(0.0)
	_fade(nxt, true, START_FADE if first else secs)
	if old.playing:
		_fade(old, false, secs, true)
	_active = nxt


## Equal-power fade (amplitude = sqrt): no dip in the middle of a crossfade, audible from the first moment.
func _fade(p: AudioStreamPlayer, fade_in: bool, secs: float, stop_after: bool = false) -> void:
	_kill_tween(p)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var a := sqrt(t) if fade_in else sqrt(1.0 - t)
		p.volume_db = linear_to_db(maxf(a, 0.0001)), 0.0, 1.0, secs)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw


func _kill_tween(p: AudioStreamPlayer) -> void:
	var tw: Tween = _tweens.get(p)
	if tw != null and tw.is_valid():
		tw.kill()


func _process(delta: float) -> void:
	# pause ducking (music keeps going, just quieter)
	var want := DUCK_DB if get_tree().paused else 0.0
	if not is_equal_approx(_duck, want):
		_duck = move_toward(_duck, want, 40.0 * delta)
		var mv := float(GameState.settings.get("music_volume", 1.0))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(mv, 0.0001)) + _duck)
	# seamless loop: crossfade the track into itself shortly before it ends
	if _active.playing and _active.stream != null:
		var left := _active.stream.get_length() - _active.get_playback_position()
		if left < LOOP_FADE and left > 0.0:
			_crossfade(mood, LOOP_FADE)
	# which mood does the current scene want?
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.25
		set_mood(_scene_mood())


func _scene_mood() -> String:
	var sc := get_tree().current_scene
	if sc != null and sc.has_method("music_mood"):
		return str(sc.call("music_mood"))
	return "calm"
