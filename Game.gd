extends Node2D
## Pitch Invader: World Cup Craze — Godot 4.x 版
## 单脚本实现：世界绘制(_draw) + 逻辑(_process) + 代码构建 UI。
## 像素风沿用，叠加 Godot 的相机缩放/震屏、辉光环境、粒子化纸屑等润色。

# ----------------------------------------------------------------------------
# 世界 / 几何
# ----------------------------------------------------------------------------
const WORLD := Vector2(2200, 1400)
const FIELD_MARGIN := 110.0
var FX0 := FIELD_MARGIN
var FY0 := FIELD_MARGIN
var FX1 := WORLD.x - FIELD_MARGIN
var FY1 := WORLD.y - FIELD_MARGIN
var FW := FX1 - FX0
var FH := FY1 - FY0
# 相机缩放改由 Config.gd 的 camera_zoom 控制（值越大画面越大）
const STAND_DEPTH := 260.0

# ----------------------------------------------------------------------------
# 可调参数（对应 JS 版 TUNE，便于后续平衡）
# ----------------------------------------------------------------------------
# 所有可调参数来自 Config.gd（GameConfig），在 _ready 里初始化，运行时可被调试修改
var TUNE: Dictionary = {}

# ----------------------------------------------------------------------------
# 像素精灵模板（与 JS 版一致）
# ----------------------------------------------------------------------------
const BODY := [
	"  hhhh  ",
	" hkkkkh ",
	" hkkkkh ",
	" kkkkkk ",
	"  kkkk  ",
	"  1111  ",
	" 111111 ",
	" 111111 ",
]
const LEGS_STAND := ["  1  1  ", "  2  2  ", "  2  2  ", "  bb bb "]
const LEGS_A := [" 1   1  ", " 2   2  ", " 2    2 ", " bb   bb"]
const LEGS_B := ["  1   1 ", "  2   2 ", " 2    2 ", "bb   bb "]

var SPRITES := {}   # name -> {"stand":tex,"a":tex,"b":tex}
const ANIM_STRIDE := 8.0

# ----------------------------------------------------------------------------
# 游戏状态
# ----------------------------------------------------------------------------
enum St { MENU, PLAY, UPGRADE, OVER }
var state: int = St.MENU

var score := 0
var elapsed := 0.0           # 帧数（dt≈1/帧）
var photographed := 0
var next_upgrade_at := 1000
var god_mode := false

# 玩家
var p_pos := Vector2.ZERO
var p_vel := Vector2.ZERO
var p_radius := 14.0
var p_face := Vector2(0, -1)
var p_stamina := 100.0
var p_stamina_max := 100.0
var p_exhausted := false
var p_exhaust_timer := 0.0
var p_rolling := false
var p_roll_timer := 0.0
var p_roll_dir := Vector2(1, 0)
var p_roll_cd := 0.0
var p_combo := 0
var p_combo_timer := 0.0
var p_riot := 0.0
var p_anim := "stand"
var p_phase := 0.0

var upgrades := {"stamina_max": 100.0, "speed_mult": 1.0, "roll_cost": 5.0, "photo_radius": 1.0}
var up_levels := {"stamina_max": 0, "speed_mult": 0, "roll_cost": 0, "photo_radius": 0}

# 实体列表（用字典存储，轻量）
var players: Array = []      # 球员
var security: Array = []     # 保安
var riot_npcs: Array = []
var confetti: Array = []
var flashes: Array = []      # 看台闪光灯

var player_id := 1
const MAX_PLAYERS := 14
const MAX_STARS := 2
var star_cd := 0.0
const TEAM_DEFS := [
	{"name": "ARG", "color": "#75AADB", "star": 10},
	{"name": "POR", "color": "#cc1122", "star": 7},
]
# 普通球员号码池（排除球星专属的 10 和 7，保证全场只有一个 10、一个 7）
const NON_STAR_NUMS := [2, 3, 4, 5, 6, 8, 9, 11]

var sec_spawn_timer := 0.0
const LUNGE_RANGE := 70.0
const LUNGE_CHARGE := 26.0
const LUNGE_DUR := 16.0
const LUNGE_RECOVER := 38.0   # 飞扑后定在原地的时间，结束后换角度包抄
const LUNGE_SPEED := 2.6
const LUNGE_CD_AFTER := 70.0

var riot_active := false
var riot_timer := 0.0

# ---------- 吉祥物 mini-boss（存活 1/2/3 分钟陆续登场）----------
var mascots: Array = []
var mascot_spawn_idx := 0
const MASCOT_DEFS := [
	{"type": "moose",  "label": "红麋鹿", "name_col": "#ff7a4a", "jersey": "#d23b2a", "fur": "#c98a5a", "boot": "#3a2a1a"},
	{"type": "jaguar", "label": "绿猎豹", "name_col": "#6ee07a", "jersey": "#2e8b3d", "fur": "#e0a838", "boot": "#222222"},
	{"type": "eagle",  "label": "蓝鹰",   "name_col": "#74a0ff", "jersey": "#2546c8", "fur": "#f4f4f4", "boot": "#444444"},
]
const MASCOT_TIMES := [3600.0, 7200.0, 10800.0]  # 1/2/3 分钟（帧）
const MASCOT_AIM := 32.0       # 冲锋前的瞄准预警（约 0.5s）
const MASCOT_REST := 300.0     # 贯穿后在边线休息 5 秒
const MASCOT_RADIUS := 26.0    # 普通保安(13)的两倍
const MASCOT_SCATTER := 60.0   # 冲锋时冲散保安的半径

# 表现层
var shake := 0.0
var flash_alpha := 0.0
var gold_flash := 0.0
var danger := 0.0

# 解说/文本均来自 Config.gd（GameConfig）
var chants: Array = []
var chant_timer := 0.0
var crowd_dots: Array = []

# 输入
var joy_vec := Vector2.ZERO
var sprint_held := false
var roll_pressed := false

# 节点引用
var cam: Camera2D
var ui: CanvasLayer
var shutter_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer
var cheer_player: AudioStreamPlayer
var lbl_score: Label
var lbl_info: Label
var lbl_levels: Label
var lbl_comment: Label
var bar_stam_fill: ColorRect
var bar_riot_fill: ColorRect
var flash_rect: ColorRect
var gold_rect: ColorRect
var danger_rect: TextureRect
var panel_start: Control
var panel_upgrade: Control
var panel_over: Control
var lbl_over_title: Label
var lbl_over_stats: Label
var upgrade_box: VBoxContainer
var comment_timer := 0.0
var font: Font

# ============================================================================
func _ready() -> void:
	randomize()
	TUNE = GameConfig.default_tune()
	font = _load_cjk_font()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_sprites()
	_build_crowd_dots()
	_setup_camera()
	_setup_environment()
	_build_ui()
	_setup_audio()
	god_mode = GameConfig.DEBUG.god_mode
	set_process(true)
	if GameConfig.DEBUG.start_immediately:
		_start_game()

# 加载内置的像素中文字体（Zpix）。直接读原始字节构建 FontFile，绕开 Godot 导入系统，
# 确保打包进 web 构建（cjkfont.dat 由 export_presets 的 include_filter 强制包含）。
func _load_cjk_font() -> Font:
	var path := "res://cjkfont.dat"
	if FileAccess.file_exists(path):
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa != null:
			var bytes := fa.get_buffer(fa.get_length())
			fa.close()
			if bytes.size() > 1000:
				var f := FontFile.new()
				f.data = bytes
				f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
				f.hinting = TextServer.HINTING_NONE
				f.force_autohinter = false
				return f
	return ThemeDB.fallback_font

# ----------------------------------------------------------------------------
# 像素精灵生成
# ----------------------------------------------------------------------------
func _make_sprite(pal: Dictionary, legs: Array) -> ImageTexture:
	var tmpl := BODY + legs
	var rows := tmpl.size()
	var cols := (tmpl[0] as String).length()
	var img := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for r in rows:
		var line: String = tmpl[r]
		for c in cols:
			var ch := line[c]
			if ch == " ":
				continue
			img.set_pixel(c, r, pal.get(ch, Color.WHITE))
	return ImageTexture.create_from_image(img)

func _char_set(pal: Dictionary) -> Dictionary:
	return {
		"stand": _make_sprite(pal, LEGS_STAND),
		"a": _make_sprite(pal, LEGS_A),
		"b": _make_sprite(pal, LEGS_B),
	}

func _build_sprites() -> void:
	SPRITES["fan"] = _char_set({"h": Color("#5d4037"), "k": Color("#ffccaa"), "1": Color("#ffd700"), "2": Color("#1565c0"), "b": Color("#222222")})
	SPRITES["argCommon"] = _char_set({"h": Color("#3b3b3b"), "k": Color("#e0b08c"), "1": Color("#75AADB"), "2": Color("#ffffff"), "b": Color("#111111")})
	SPRITES["argStar"] = _char_set({"h": Color("#222222"), "k": Color("#caa07a"), "1": Color("#75AADB"), "2": Color("#ffd700"), "b": Color("#111111")})
	SPRITES["porCommon"] = _char_set({"h": Color("#2b2b2b"), "k": Color("#e0b08c"), "1": Color("#cc1122"), "2": Color("#0a6e31"), "b": Color("#111111")})
	SPRITES["porStar"] = _char_set({"h": Color("#1a1a1a"), "k": Color("#caa07a"), "1": Color("#cc1122"), "2": Color("#ffd700"), "b": Color("#111111")})
	SPRITES["guard"] = _char_set({"h": Color("#000000"), "k": Color("#caa07a"), "1": Color("#222831"), "2": Color("#11151a"), "b": Color("#000000")})
	SPRITES["guardElite"] = _char_set({"h": Color("#1a0033"), "k": Color("#caa07a"), "1": Color("#4a148c"), "2": Color("#7b1fa2"), "b": Color("#000000")})
	SPRITES["riot"] = _char_set({"h": Color("#333333"), "k": Color("#ffccaa"), "1": Color("#69f0ae"), "2": Color("#2e7d32"), "b": Color("#111111")})
	# 吉祥物改为程序化矢量绘制（见 _draw_mascots），不再用人形精灵

func _build_crowd_dots() -> void:
	var cols := ["#75AADB", "#ffffff", "#cc1122", "#0a6e31", "#ffd700", "#ff7043"]
	var spacing := 16.0
	for row in range(4):
		var x := -STAND_DEPTH
		while x < WORLD.x + STAND_DEPTH:
			crowd_dots.append({"p": Vector2(x, -34 - row * 18), "c": Color(cols[randi() % cols.size()]), "ph": randf() * TAU})
			crowd_dots.append({"p": Vector2(x, WORLD.y + 34 + row * 18), "c": Color(cols[randi() % cols.size()]), "ph": randf() * TAU})
			x += spacing
		var y := 0.0
		while y < WORLD.y:
			crowd_dots.append({"p": Vector2(-34 - row * 18, y), "c": Color(cols[randi() % cols.size()]), "ph": randf() * TAU})
			crowd_dots.append({"p": Vector2(WORLD.x + 34 + row * 18, y), "c": Color(cols[randi() % cols.size()]), "ph": randf() * TAU})
			y += spacing

# ----------------------------------------------------------------------------
# 相机 + 辉光环境
# ----------------------------------------------------------------------------
func _setup_camera() -> void:
	cam = Camera2D.new()
	var z: float = float(TUNE.camera_zoom)
	cam.zoom = Vector2(z, z)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 12.0
	cam.position = WORLD / 2.0
	add_child(cam)
	cam.make_current()

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.9
	we.environment = env
	add_child(we)

# ----------------------------------------------------------------------------
# 音效：程序化合成相机"咔嚓"快门声（无需音频素材）
# ----------------------------------------------------------------------------
func _setup_audio() -> void:
	# 相机快门（合影时）——优先用真实音频，缺失时回退到合成音。音量改这一行↓
	shutter_player = AudioStreamPlayer.new()
	var cam_s: AudioStream = _load_audio_dat("res://camera.wav.dat", "wav")
	shutter_player.stream = cam_s if cam_s != null else _make_shutter_wav()
	shutter_player.volume_db = -4.0
	shutter_player.max_polyphony = 5  # 连拍时允许叠加
	add_child(shutter_player)

	# 背景音乐 BGM（循环）。音量改这一行↓
	bgm_player = AudioStreamPlayer.new()
	var bgm_s: AudioStream = _load_audio_dat("res://bgm.ogg.dat", "ogg")
	if bgm_s != null:
		_set_loop(bgm_s, true)
		bgm_player.stream = bgm_s
	else:
		bgm_player.stream = _make_chant_bgm()
	bgm_player.volume_db = -8.0
	add_child(bgm_player)

	# 人群欢呼（循环背景氛围声）。音量改这一行↓
	cheer_player = AudioStreamPlayer.new()
	var cheer_s: AudioStream = _load_audio_dat("res://cheer.mp3.dat", "mp3")
	if cheer_s != null:
		_set_loop(cheer_s, true)
		cheer_player.stream = cheer_s
	cheer_player.volume_db = -10.0
	add_child(cheer_player)

# 从打包的原始字节文件加载音频（绕开导入系统，确保 web 构建一定包含）
func _load_audio_dat(path: String, kind: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var bytes := fa.get_buffer(fa.get_length())
	fa.close()
	if bytes.size() < 32:
		return null
	match kind:
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			var m := AudioStreamMP3.new()
			m.data = bytes
			return m
		"wav":
			return _wav_from_bytes(bytes)
	return null

# 手动解析标准 PCM WAV（只用基础 PackedByteArray API，任何 4.x 都可靠）
func _wav_from_bytes(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	var channels := 1
	var sample_rate := 44100
	var bits := 16
	var pcm := PackedByteArray()
	var pos := 12  # 跳过 "RIFF"<size>"WAVE"
	while pos + 8 <= bytes.size():
		var cid: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var csize: int = bytes.decode_u32(pos + 4)
		var body := pos + 8
		if cid == "fmt ":
			channels = bytes.decode_u16(body + 2)
			sample_rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif cid == "data":
			pcm = bytes.slice(body, min(body + csize, bytes.size()))
		pos = body + csize + (csize & 1)  # 块按偶数对齐
	if pcm.size() == 0:
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sample_rate
	w.stereo = channels >= 2
	w.data = pcm
	return w

func _set_loop(s: AudioStream, on: bool) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = on
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = on
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED

# 程序化合成一段循环的球场口号动机（人群"oh-oh-oh"+底噪），魔性洗脑
func _make_chant_bgm() -> AudioStreamWAV:
	var rate := 22050
	# (频率Hz, 时长秒)，0 = 休止。一段上头的弹跳口号 + 收尾
	var melody := [
		[392.00, 0.26], [392.00, 0.26], [440.00, 0.26], [392.00, 0.26],
		[329.63, 0.26], [392.00, 0.26], [261.63, 0.42], [0.0, 0.20],
		[392.00, 0.26], [440.00, 0.26], [523.25, 0.30], [440.00, 0.26],
		[392.00, 0.26], [329.63, 0.26], [261.63, 0.42], [0.0, 0.28],
	]
	var total := 0.0
	for seg in melody:
		total += float(seg[1])
	var n := int(total * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var idx := 0
	for seg in melody:
		var f: float = float(seg[0])
		var seglen: int = int(float(seg[1]) * rate)
		for j in range(seglen):
			if idx >= n:
				break
			var sample := 0.0
			if f > 0.0:
				var tt := float(j) / float(seglen)
				var env: float = sin(PI * tt)        # 拱形包络，像一声"oh"
				var ph := float(j) / float(rate)
				sample += sin(TAU * f * ph)
				sample += 0.5 * sin(TAU * f * 1.005 * ph)  # 轻微失谐 = 合唱/人群感
				sample += 0.4 * sin(TAU * f * 0.5 * ph)    # 低八度增厚
				sample = sample * env * 0.16
			sample += (randf() * 2.0 - 1.0) * 0.01         # 人群底噪（已减半）
			var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
			data[idx * 2] = v & 0xFF
			data[idx * 2 + 1] = (v >> 8) & 0xFF
			idx += 1
	if idx * 2 < data.size():
		data.resize(idx * 2)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = idx
	return wav

func _play_bgm() -> void:
	if GameConfig.DEBUG.mute_audio:
		return
	if bgm_player != null and not bgm_player.playing:
		bgm_player.play()
	if cheer_player != null and cheer_player.stream != null and not cheer_player.playing:
		cheer_player.play()

func _make_shutter_wav() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.13
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var env := 0.0
		# 第一声"咔"
		if t < 0.045:
			env = exp(-t / 0.012)
		# 第二声"嚓"（稍晚、稍轻）
		if t >= 0.06 and t < 0.12:
			env = max(env, 0.8 * exp(-(t - 0.06) / 0.018))
		var sample := (randf() * 2.0 - 1.0) * env * 0.6
		var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

func _play_shutter() -> void:
	if shutter_player != null and not GameConfig.DEBUG.mute_audio:
		shutter_player.play()

# ============================================================================
# 主循环
# ============================================================================
func _process(delta: float) -> void:
	var dt: float = min(2.0, delta * 60.0)
	if state == St.PLAY:
		elapsed += dt
		_update_player(dt)
		_update_players(dt)
		_refill_players(dt)
		_update_security(dt)
		_update_riot(dt)
		_update_mascots(dt)
		_update_confetti(dt)
		_update_flashes(dt)
		_update_chants(dt)
		_update_danger()
		cam.position = p_pos
		if shake > 0:
			cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
			shake = max(0.0, shake - 0.6 * dt)
		else:
			cam.offset = Vector2.ZERO
		if flash_alpha > 0: flash_alpha = max(0.0, flash_alpha - 0.05 * dt)
		if gold_flash > 0: gold_flash = max(0.0, gold_flash - 0.04 * dt)
		if p_combo_timer > 0:
			p_combo_timer -= dt
			if p_combo_timer <= 0: p_combo = 0
		_update_hud()
	if comment_timer > 0:
		comment_timer -= delta
		if comment_timer <= 0:
			lbl_comment.modulate.a = max(0.0, lbl_comment.modulate.a - delta * 3.0)
	queue_redraw()

# ----------------------------------------------------------------------------
# 输入
# ----------------------------------------------------------------------------
func _move_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if v.length() > 0:
		return v.normalized()
	if joy_vec.length() > 0.15:
		return joy_vec
	return Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			roll_pressed = true

func _wants_sprint() -> bool:
	return sprint_held or Input.is_key_pressed(KEY_SHIFT)

# ----------------------------------------------------------------------------
# 玩家更新
# ----------------------------------------------------------------------------
func _update_player(dt: float) -> void:
	var move := _move_vector()
	var want_sprint := _wants_sprint() and move.length() > 0 and not p_exhausted and p_stamina > 0
	var want_roll: bool = roll_pressed and not p_rolling and p_roll_cd <= 0 and p_stamina >= upgrades.roll_cost
	roll_pressed = false
	if move.length() > 0: p_face = move

	if p_rolling:
		p_roll_timer -= dt
		p_vel = p_roll_dir * float(TUNE.roll_speed)
		p_pos = _clamp_world_v(p_pos + p_vel * dt, p_radius)
		if p_roll_timer <= 0:
			p_rolling = false
			p_roll_cd = 20.0
			p_vel *= 0.5
	elif want_roll:
		p_rolling = true
		p_roll_timer = float(TUNE.roll_duration)
		p_roll_dir = move if move.length() > 0 else p_face
		p_stamina -= upgrades.roll_cost
	else:
		var speed: float = TUNE.player_base_speed * upgrades.speed_mult
		if p_exhausted:
			speed *= 0.4
		elif want_sprint:
			speed *= TUNE.sprint_mult
			p_stamina -= 0.4 * dt
		var target := move * speed
		p_vel += (target - p_vel) * TUNE.player_accel * dt
		p_pos = _clamp_world_v(p_pos + p_vel * dt, p_radius)

	_step_anim_player(p_vel.length(), dt)
	if p_roll_cd > 0: p_roll_cd -= dt
	if p_stamina <= 0 and not p_exhausted:
		p_exhausted = true
		p_exhaust_timer = 120.0
	if p_exhausted:
		p_exhaust_timer -= dt
		if p_exhaust_timer <= 0:
			p_exhausted = false
			p_stamina = 20.0
	if not want_sprint and not p_rolling and p_stamina < upgrades.stamina_max and not p_exhausted:
		p_stamina += 0.45 * dt
	p_stamina = clampf(p_stamina, 0.0, upgrades.stamina_max)

func _clamp_world_v(pos: Vector2, r: float) -> Vector2:
	return Vector2(clampf(pos.x, r, WORLD.x - r), clampf(pos.y, r, WORLD.y - r))

func _clamp_field_v(pos: Vector2, r: float) -> Vector2:
	return Vector2(clampf(pos.x, FX0 + r, FX1 - r), clampf(pos.y, FY0 + r, FY1 - r))

func _step_anim_player(speed: float, dt: float) -> void:
	if speed < 0.15:
		p_anim = "stand"
		return
	p_phase += speed * dt
	p_anim = "a" if int(p_phase / ANIM_STRIDE) % 2 == 0 else "b"

func _step_anim(e: Dictionary, speed: float, dt: float) -> void:
	if speed < 0.15:
		e.anim = "stand"
		return
	e.phase += speed * dt
	e.anim = "a" if int(e.phase / ANIM_STRIDE) % 2 == 0 else "b"

# ----------------------------------------------------------------------------
# 球员（足球运动员）
# ----------------------------------------------------------------------------
func _rand_field_edge() -> Vector2:
	var edge := randi() % 4
	var m := 20.0
	match edge:
		0: return Vector2(FX0 + m + randf() * (FW - 2 * m), FY0 + m)
		1: return Vector2(FX0 + m + randf() * (FW - 2 * m), FY1 - m)
		2: return Vector2(FX0 + m, FY0 + m + randf() * (FH - 2 * m))
		_: return Vector2(FX1 - m, FY0 + m + randf() * (FH - 2 * m))

func _nearest_edge_dir(p: Vector2) -> Vector2:
	var dl := p.x; var dr := WORLD.x - p.x; var du := p.y; var db := WORLD.y - p.y
	var mn: float = min(min(dl, dr), min(du, db))
	if mn == dl: return Vector2(-1, 0)
	if mn == dr: return Vector2(1, 0)
	if mn == du: return Vector2(0, -1)
	return Vector2(0, 1)

func _make_footballer(is_star: bool, team: Dictionary, at_edge: bool) -> Dictionary:
	var pos := _rand_field_edge() if at_edge else Vector2(FX0 + 60 + randf() * (FW - 120), FY0 + 60 + randf() * (FH - 120))
	var smax: float = TUNE.star_stamina if is_star else TUNE.common_stamina
	var num: int = int(team.star) if is_star else int(NON_STAR_NUMS[randi() % NON_STAR_NUMS.size()])
	var fp := {
		"id": player_id, "team": team.name, "color": Color(team.color),
		"number": num,
		"is_star": is_star, "pos": pos, "vel": Vector2.ZERO,
		"dir": Vector2(randf() - 0.5, randf() - 0.5).normalized(),
		"wander": randf() * 60.0, "photographed": false, "leaving": false,
		"fleeing": false, "progress": 0.0, "being_photo": false,
		"chased": false, "chase_timer": 0.0,
		"flee_radius": 175.0 if is_star else 100.0,
		"stamina": smax, "exhausted": false, "exhaust_timer": 0.0,
		"anim": "stand", "phase": 0.0,
	}
	player_id += 1
	return fp

func _random_team() -> Dictionary:
	return TEAM_DEFS[randi() % TEAM_DEFS.size()]

# 该队是否已有在场球星（用于保证每队最多一名球星）
func _team_has_star(team_name: String) -> bool:
	for fp in players:
		if fp.is_star and not fp.leaving and fp.team == team_name:
			return true
	return false

func _spawn_players() -> void:
	players.clear()
	player_id = 1
	star_cd = 0.0
	# 两队各一名球星：阿根廷 10 号、葡萄牙 7 号
	players.append(_make_footballer(true, TEAM_DEFS[0], false))
	players.append(_make_footballer(true, TEAM_DEFS[1], false))
	for i in range(MAX_PLAYERS - 2):
		players.append(_make_footballer(false, _random_team(), false))

func _refill_players(dt: float) -> void:
	if star_cd > 0: star_cd -= dt
	var alive := 0
	for fp in players:
		if not fp.leaving: alive += 1
	if alive < MAX_PLAYERS:
		# 若某队球星缺席且冷却结束，补回该队球星；否则补普通球员
		var missing: Dictionary = {}
		if star_cd <= 0:
			for t in TEAM_DEFS:
				if not _team_has_star(t.name):
					missing = t
					break
		if not missing.is_empty():
			players.append(_make_footballer(true, missing, true))
			star_cd = 360.0
		else:
			players.append(_make_footballer(false, _random_team(), true))

func _update_players(dt: float) -> void:
	var photo_range: float = 50.0 * upgrades.photo_radius
	for i in range(players.size() - 1, -1, -1):
		var fp: Dictionary = players[i]
		if fp.leaving:
			fp.vel += (fp.dir * 3.6 - fp.vel) * 0.2 * dt
			fp.pos += fp.vel * dt
			_step_anim(fp, fp.vel.length(), dt)
			if fp.pos.x < -40 or fp.pos.x > WORLD.x + 40 or fp.pos.y < -40 or fp.pos.y > WORLD.y + 40:
				players.remove_at(i)
			continue

		var smax: float = TUNE.star_stamina if fp.is_star else TUNE.common_stamina
		if fp.stamina > smax: fp.stamina = smax
		var base_speed: float = TUNE.star_speed if fp.is_star else TUNE.common_speed
		var dist: float = fp.pos.distance_to(p_pos)
		var grabbed: bool = dist < photo_range * 0.8 and not p_rolling
		var want_flee: bool = not grabbed and not p_rolling and dist < fp.flee_radius and fp.stamina > 0 and not fp.exhausted

		var ddir := Vector2.ZERO
		var dspeed := 0.0
		if grabbed:
			fp.fleeing = false
		elif want_flee:
			fp.fleeing = true
			fp.chased = true
			fp.chase_timer = 90.0
			ddir = (fp.pos - p_pos).normalized()
			# 避墙：靠近边界时把逃跑方向往场内拨，避免被卡在墙角任人宰割
			var avoid := Vector2.ZERO
			var wm := 90.0
			if fp.pos.x < FX0 + wm: avoid.x += 1.0
			elif fp.pos.x > FX1 - wm: avoid.x -= 1.0
			if fp.pos.y < FY0 + wm: avoid.y += 1.0
			elif fp.pos.y > FY1 - wm: avoid.y -= 1.0
			if avoid != Vector2.ZERO:
				ddir = (ddir + avoid.normalized() * 1.4).normalized()
			dspeed = base_speed * 1.5
			fp.stamina -= (0.8 if fp.is_star else 1.1) * dt
			if fp.stamina <= 0:
				fp.stamina = 0
				fp.exhausted = true
				fp.exhaust_timer = 70.0
		else:
			fp.fleeing = false
			fp.wander -= dt
			if fp.wander <= 0:
				fp.dir = Vector2(randf() - 0.5, randf() - 0.5).normalized()
				fp.wander = 60.0 + randf() * 90.0
			ddir = fp.dir
			dspeed = base_speed * (0.18 if fp.exhausted else 0.45)
		if ddir.length() > 0: fp.dir = ddir

		if fp.exhausted:
			fp.exhaust_timer -= dt
			if fp.exhaust_timer <= 0:
				fp.exhausted = false
				fp.stamina = smax * 0.4
		elif not want_flee:
			fp.stamina = min(smax, fp.stamina + 0.5 * dt)

		var target := ddir * dspeed
		fp.vel += (target - fp.vel) * TUNE.fb_accel * dt
		fp.pos = _clamp_field_v(fp.pos + fp.vel * dt, 12.0)
		_step_anim(fp, fp.vel.length(), dt)

		if fp.chase_timer > 0: fp.chase_timer -= dt
		else: fp.chased = false

		var in_range: bool = grabbed or (dist < photo_range and not fp.fleeing)
		if in_range:
			fp.being_photo = true
			fp.progress += (1.3 if grabbed else 1.0) * dt
			if fp.progress >= 60:
				_complete_photo(fp)
		else:
			fp.being_photo = false
			fp.progress = max(0.0, fp.progress - dt * 2.0)

func _complete_photo(fp: Dictionary) -> void:
	fp.photographed = true
	fp.leaving = true
	fp.being_photo = false
	fp.fleeing = false
	fp.dir = _nearest_edge_dir(fp.pos)
	photographed += 1
	var base: int = 400 if fp.is_star else 150
	var mult := 2 if fp.chased else 1
	score += base * mult
	_spawn_confetti(fp.pos)
	flash_alpha = 1.0 if fp.is_star else 0.7
	if fp.is_star: gold_flash = 1.0
	shake = 10.0
	_play_shutter()  # 咔嚓快门声
	var lines: Array = GameConfig.STAR_PHOTO_LINES if fp.is_star else GameConfig.PHOTO_LINES
	_say(lines[randi() % lines.size()], Color("#ffd700") if fp.is_star else Color.WHITE)
	p_combo += 1
	p_combo_timer = 180.0
	p_riot = min(100.0, p_riot + (35.0 if fp.is_star else 18.0))
	if p_riot >= 100 and not riot_active:
		_trigger_riot()
		p_riot = 0
	if photographed % GameConfig.MILESTONE_EVERY == 0:
		_say(GameConfig.MILESTONE_TEMPLATE % photographed, Color("#ffd700"))
	_check_upgrade()

func _check_upgrade() -> void:
	if score >= next_upgrade_at:
		_show_upgrade()
		next_upgrade_at = int(round(next_upgrade_at * 1.7 / 100.0) * 100)

# ----------------------------------------------------------------------------
# 保安
# ----------------------------------------------------------------------------
func _spawn_security(elite: bool) -> void:
	var edge := randi() % 4
	var pos: Vector2
	match edge:
		0: pos = Vector2(randf() * WORLD.x, 0)
		1: pos = Vector2(randf() * WORLD.x, WORLD.y)
		2: pos = Vector2(0, randf() * WORLD.y)
		_: pos = Vector2(WORLD.x, randf() * WORLD.y)
	security.append({
		"pos": pos, "vel": Vector2.ZERO, "elite": elite, "radius": 13.0,
		"state": "chase", "timer": 0.0, "lunge_dir": Vector2.ZERO, "lunge_cd": 0.0,
		"flank": randf_range(-1.0, 1.0),  # 包抄偏移：让每个保安从不同角度逼近
		"distract_target": null,           # 被狂热粉丝吸引的目标（仅最近 5 个会被赋值）
		"anim": "stand", "phase": 0.0,
	})

func _update_security(dt: float) -> void:
	sec_spawn_timer -= dt
	var speed_bonus := int((upgrades.speed_mult - 1.0) * 8)
	var target_count: int = int(TUNE.base_security) + int(elapsed / 15.0) + int(score / 1000.0) + speed_bonus + int(photographed / 6.0)
	if security.size() < min(target_count, int(TUNE.max_security)) and sec_spawn_timer <= 0:
		_spawn_security(elapsed > 60 and randf() < 0.3)
		# 生成间隔乘以 config 里的倍率（>1 = 刷得更慢）
		sec_spawn_timer = max(30.0, 90.0 - floor(elapsed / 10.0) - floor(photographed / 4.0)) * float(TUNE.sec_spawn_interval_mult)

	# 狂热粉丝（暴动）只吸引最近的 5 个保安，其余继续追玩家
	for s in security:
		s.distract_target = null
	if riot_active and riot_npcs.size() > 0:
		var cands: Array = []
		for s in security:
			if s.state != "chase": continue
			var nd := INF
			var nn = null
			for r in riot_npcs:
				var d: float = s.pos.distance_to(r.pos)
				if d < nd: nd = d; nn = r
			if nn != null and nd < 320.0:
				cands.append({"s": s, "npc": nn, "d": nd})
		cands.sort_custom(func(a, b): return a.d < b.d)
		for i in range(min(5, cands.size())):
			var entry: Dictionary = cands[i]
			var g: Dictionary = entry.s
			g.distract_target = entry.npc

	# 保安速度只吸收主角“移速增幅”的一半：主角 +10% → 保安 +5%
	var pcur: float = TUNE.player_base_speed * (1.0 + (upgrades.speed_mult - 1.0) * 0.5)
	for s in security:
		if s.lunge_cd > 0: s.lunge_cd -= dt
		var chasing_decoy := false
		if s.state == "charge":
			s.timer -= dt
			s.vel *= 0.8
			if s.timer <= 0:
				s.state = "lunge"
				s.timer = LUNGE_DUR
				s.lunge_dir = (p_pos + p_vel * 6.0 - s.pos).normalized()
		elif s.state == "lunge":
			s.timer -= dt
			var ratio: float = TUNE.sec_ratio_elite if s.elite else TUNE.sec_ratio
			s.vel = s.lunge_dir * pcur * ratio * LUNGE_SPEED
			if s.timer <= 0:
				s.state = "recover"
				s.timer = LUNGE_RECOVER
		elif s.state == "recover":
			# 飞扑后定在原地一下（更明确的停顿），结束后换角度包抄
			s.timer -= dt
			s.vel *= 0.6
			if s.timer <= 0:
				s.state = "chase"
				s.lunge_cd = LUNGE_CD_AFTER
				s.flank = randf_range(-1.0, 1.0)
		else:
			var target := p_pos
			if s.distract_target != null:
				target = s.distract_target.pos
				chasing_decoy = true
			# 包抄：远距离时瞄准玩家身侧偏移点（分散成弧形围堵），贴近时收回直扑
			if not chasing_decoy:
				var to_p: Vector2 = p_pos - s.pos
				var fscale: float = clampf(to_p.length() / 220.0, 0.0, 1.0)
				target = p_pos + to_p.orthogonal().normalized() * s.flank * 75.0 * fscale
			var dir: Vector2 = (target - s.pos).normalized()
			if s.elite and not chasing_decoy:
				dir = (p_pos + p_vel * 8.0 - s.pos).normalized()
			var ratio: float = TUNE.sec_ratio_elite if s.elite else TUNE.sec_ratio
			var accel: float = TUNE.security_accel_elite if s.elite else TUNE.security_accel
			# 分离力：保安互相排斥，避免挤在一条路上让玩家一次甩开整团
			var sep := Vector2.ZERO
			var sep_radius: float = TUNE.sec_separation_radius
			for o in security:
				if is_same(o, s): continue
				var dd: Vector2 = s.pos - o.pos
				var dl: float = dd.length()
				if dl < sep_radius and dl > 0.01:
					sep += (dd / dl) * (1.0 - dl / sep_radius)
			var target_vel: Vector2 = dir * pcur * ratio + sep * (pcur * float(TUNE.sec_separation_force))
			s.vel += (target_vel - s.vel) * accel * dt
			var dpl: float = s.pos.distance_to(p_pos)
			if not chasing_decoy and not p_rolling and dpl < LUNGE_RANGE and s.lunge_cd <= 0:
				s.state = "charge"
				s.timer = LUNGE_CHARGE
				s.vel *= 0.3
		s.pos = _clamp_world_v(s.pos + s.vel * dt, s.radius)
		_step_anim(s, s.vel.length(), dt)
		if not chasing_decoy and not p_rolling and not god_mode:
			if s.pos.distance_to(p_pos) < s.radius + p_radius:
				_game_over()
				return

# ----------------------------------------------------------------------------
# 暴动
# ----------------------------------------------------------------------------
func _trigger_riot() -> void:
	riot_active = true
	riot_timer = 480.0
	var n := 3 + randi() % 3
	for i in range(n):
		riot_npcs.append({
			"pos": Vector2(randf() * WORLD.x, randf() * WORLD.y), "vel": Vector2.ZERO,
			"dir": Vector2(randf() - 0.5, randf() - 0.5).normalized(), "wander": 0.0,
			"spd": 2.6 + randf() * 1.8,
			"anim": "stand", "phase": 0.0,
		})

func _update_riot(dt: float) -> void:
	if not riot_active: return
	riot_timer -= dt
	for r in riot_npcs:
		r.wander -= dt
		# 狂暴的观众：高频变向 + 随机变速，毫无规律地乱窜
		if r.wander <= 0:
			r.dir = Vector2(randf() - 0.5, randf() - 0.5).normalized()
			r.wander = 6.0 + randf() * 18.0
			r.spd = 2.4 + randf() * 2.4
		# 额外的小抖动，让轨迹更癫
		var jitter := Vector2(randf() - 0.5, randf() - 0.5) * 0.6
		var move_dir: Vector2 = (r.dir + jitter).normalized()
		r.pos = _clamp_world_v(r.pos + move_dir * float(r.spd) * dt, 10.0)
		r.dir = move_dir
		_step_anim(r, float(r.spd), dt)
	if riot_timer <= 0:
		riot_active = false
		riot_npcs.clear()

# ----------------------------------------------------------------------------
# 吉祥物 mini-boss：边线直线冲锋（玩家2倍速、体型2倍），贯穿后休息10秒再冲
# ----------------------------------------------------------------------------
func _spawn_mascot(def: Dictionary) -> void:
	# 从某条边线随机一点登场
	var edge := randi() % 4
	var pos: Vector2
	match edge:
		0: pos = Vector2(randf() * WORLD.x, 0)
		1: pos = Vector2(randf() * WORLD.x, WORLD.y)
		2: pos = Vector2(0, randf() * WORLD.y)
		_: pos = Vector2(WORLD.x, randf() * WORLD.y)
	var m := {
		"type": def.type, "label": def.label,
		"name_col": Color(def.name_col), "jersey": Color(def.jersey),
		"fur": Color(def.fur), "boot": Color(def.boot),
		"pos": pos, "dir": Vector2.ZERO, "speed": 0.0,
		"state": "aim", "timer": MASCOT_AIM, "phase": randf() * TAU,
	}
	mascots.append(m)

func _launch_mascot_charge(m: Dictionary) -> void:
	m.dir = (p_pos - m.pos).normalized()       # 锁定玩家当前瞬时位置
	if m.dir.length() < 0.01:
		m.dir = Vector2(0, -1)
	m.speed = TUNE.player_base_speed * upgrades.speed_mult * float(TUNE.mascot_speed_mult)  # 主角速度 × 倍率
	m.state = "charge"

func _update_mascots(dt: float) -> void:
	# 到点登场（1/2/3 分钟）
	while mascot_spawn_idx < MASCOT_DEFS.size() and elapsed >= MASCOT_TIMES[mascot_spawn_idx]:
		var def: Dictionary = MASCOT_DEFS[mascot_spawn_idx]
		_spawn_mascot(def)
		_say("【吉祥物登场】%s 冲入球场！" % def.label, Color(def.name_col))
		shake = 12.0
		mascot_spawn_idx += 1
	var sec_base: float = TUNE.player_base_speed * upgrades.speed_mult
	for m in mascots:
		match m.state:
			"aim":
				m.timer -= dt
				if m.timer <= 0:
					_launch_mascot_charge(m)
			"charge":
				m.pos += m.dir * m.speed * dt
				# 冲散沿途保安：把附近保安猛地弹开并短暂踉跄
				for s in security:
					if s.pos.distance_to(m.pos) < MASCOT_SCATTER:
						var away: Vector2 = (s.pos - m.pos)
						if away.length() < 0.01: away = Vector2(randf() - 0.5, randf() - 0.5)
						s.vel = away.normalized() * sec_base * 5.0
						s.state = "recover"
						s.timer = 28.0
				# 贯穿出界 → 夹到边线、休息
				if m.pos.x < -70 or m.pos.x > WORLD.x + 70 or m.pos.y < -70 or m.pos.y > WORLD.y + 70:
					m.pos = Vector2(clampf(m.pos.x, 0, WORLD.x), clampf(m.pos.y, 0, WORLD.y))
					m.state = "rest"
					m.timer = MASCOT_REST
				elif not p_rolling and not god_mode and m.pos.distance_to(p_pos) < MASCOT_RADIUS + p_radius:
					_game_over()
					return
			"rest":
				m.timer -= dt
				if m.timer <= 0:
					m.state = "aim"
					m.timer = MASCOT_AIM

# ----------------------------------------------------------------------------
# 粒子 / 表现
# ----------------------------------------------------------------------------
func _spawn_confetti(pos: Vector2) -> void:
	var cols := ["#ff5252", "#ffd740", "#69f0ae", "#40c4ff", "#e040fb"]
	for i in range(24):
		confetti.append({
			"pos": pos, "vel": Vector2((randf() - 0.5) * 6, (randf() - 1.5) * 6),
			"color": Color(cols[randi() % cols.size()]), "life": 60.0 + randf() * 30.0,
			"rot": randf() * TAU, "vr": (randf() - 0.5) * 0.3,
		})

func _update_confetti(dt: float) -> void:
	for i in range(confetti.size() - 1, -1, -1):
		var c: Dictionary = confetti[i]
		c.pos += c.vel * dt
		c.vel.y += 0.15 * dt
		c.rot += c.vr * dt
		c.life -= dt
		if c.life <= 0: confetti.remove_at(i)

func _update_flashes(dt: float) -> void:
	if randf() < 0.5:
		var top := randf() < 0.5
		flashes.append({"pos": Vector2(randf() * WORLD.x, (20.0 if top else WORLD.y - 40) + randf() * 30), "life": 10.0})
	for i in range(flashes.size() - 1, -1, -1):
		flashes[i].life -= dt
		if flashes[i].life <= 0: flashes.remove_at(i)

func _update_chants(dt: float) -> void:
	chant_timer -= dt
	if chant_timer <= 0:
		chant_timer = 90.0 + randf() * 120.0
		var top := randf() < 0.5
		chants.append({"pos": Vector2(randf() * WORLD.x, -40.0 if top else WORLD.y + 50), "text": GameConfig.CHANT_TEXTS[randi() % GameConfig.CHANT_TEXTS.size()], "life": 90.0})
	for i in range(chants.size() - 1, -1, -1):
		chants[i].life -= dt
		chants[i].pos.y -= dt * 0.3
		if chants[i].life <= 0: chants.remove_at(i)

func _update_danger() -> void:
	var mn := INF
	for s in security:
		var d: float = s.pos.distance_to(p_pos)
		if d < mn: mn = d
	danger = clampf(1.0 - (mn - 30.0) / 180.0, 0.0, 1.0)
	danger_rect.modulate.a = danger * 0.9

# ============================================================================
# 绘制（世界坐标，相机负责变换）
# ============================================================================
func _draw() -> void:
	if state == St.MENU:
		_draw_pitch()
		return
	_draw_pitch()
	_draw_footballers()
	_draw_riot()
	_draw_security()
	_draw_mascots()
	_draw_player()
	_draw_confetti()

func _draw_sprite(tex: ImageTexture, pos: Vector2, w: float, h: float, flip: bool, bob: float, mod: Color = Color.WHITE) -> void:
	draw_set_transform(pos, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	draw_texture_rect(tex, Rect2(-w / 2.0, -h * 0.62 + bob, w, h), false, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _hop(e) -> float:
	var anim: String = e.anim if e is Dictionary else p_anim
	var phase: float = e.phase if e is Dictionary else p_phase
	if anim == "stand": return 0.0
	return -abs(sin(phase * 0.35)) * 3.2

func _draw_pitch() -> void:
	# 看台底
	draw_rect(Rect2(-STAND_DEPTH, -STAND_DEPTH, WORLD.x + STAND_DEPTH * 2, WORLD.y + STAND_DEPTH * 2), Color("#33312e"))
	for i in range(4):
		var d := STAND_DEPTH - i * (STAND_DEPTH / 4.0)
		var col := Color(0.27, 0.25, 0.22, 0.6) if i % 2 == 0 else Color(0.2, 0.18, 0.16, 0.6)
		draw_rect(Rect2(-d, -d, WORLD.x + d * 2, WORLD.y + d * 2), col)
	# 观众点阵（律动 + 闪烁）
	var t := Time.get_ticks_msec()
	for dot in crowd_dots:
		var bob := sin(t * 0.006 + dot.ph) * 2.0
		var fl := 0.65 + 0.35 * sin(t * 0.012 + dot.ph * 1.7)
		var c: Color = dot.c
		c.a = fl
		draw_rect(Rect2(dot.p.x - 2, dot.p.y - 2 + bob, 4, 5), c)
	# 助威字幕
	for ch in chants:
		var a: float = clampf(ch.life / 90.0, 0.0, 1.0)
		draw_string(font, ch.pos, ch.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 33, Color(1, 1, 1, a))
	# 跑道（外圈可走动草地，深色）
	draw_rect(Rect2(0, 0, WORLD.x, WORLD.y), Color("#246627"))
	# 球场草坪 + 条纹
	draw_rect(Rect2(FX0, FY0, FW, FH), Color("#2e7d32"))
	var sw := 100.0
	var x := FX0
	var idx := 0
	while x < FX1:
		if idx % 2 == 0:
			draw_rect(Rect2(x, FY0, min(sw, FX1 - x), FH), Color(1, 1, 1, 0.045))
		x += sw
		idx += 1
	_draw_field_lines()
	# 看台闪光灯
	for f in flashes:
		draw_circle(f.pos, 4, Color(1, 1, 1, 0.5 * (f.life / 10.0)))

func _draw_field_lines() -> void:
	var lw := 3.0
	var col := Color(1, 1, 1, 0.85)
	var cx := WORLD.x / 2.0
	var cy := WORLD.y / 2.0
	draw_rect(Rect2(FX0, FY0, FW, FH), col, false, lw)
	draw_line(Vector2(cx, FY0), Vector2(cx, FY1), col, lw)
	var cr: float = min(FW, FH) * 0.12
	draw_arc(Vector2(cx, cy), cr, 0, TAU, 48, col, lw)
	draw_circle(Vector2(cx, cy), 4, col)
	var pd := FW * 0.15; var ph := FH * 0.55       # 大禁区
	var gd := FW * 0.05; var gh := FH * 0.28        # 小禁区
	var spot_d := FW * 0.10                          # 点球点距门线
	var arc_r: float = min(FW, FH) * 0.12            # 罚球弧半径（与中圈同尺度）
	for side in [{"gx": FX0, "s": 1.0}, {"gx": FX1, "s": -1.0}]:
		var gx: float = side.gx; var s: float = side.s
		draw_rect(Rect2(gx if s > 0 else gx - pd, cy - ph / 2, pd, ph), col, false, lw)
		draw_rect(Rect2(gx if s > 0 else gx - gd, cy - gh / 2, gd, gh), col, false, lw)
		var sp := Vector2(gx + s * spot_d, cy)
		draw_circle(sp, 4, col)
		# 罚球弧：以点球点为圆心，只画禁区前沿线之外那一段（弧的端点正好落在禁区线上）
		var arg: float = clampf((pd - spot_d) / arc_r, -1.0, 1.0)
		var half: float = acos(arg)
		var ca: float = 0.0 if s > 0 else PI       # 左门弧朝右(向场内)，右门弧朝左
		draw_arc(sp, arc_r, ca - half, ca + half, 24, col, lw)
		var goal_d := 24.0; var goal_h := FH * 0.13
		draw_rect(Rect2(gx - goal_d if s > 0 else gx, cy - goal_h / 2, goal_d, goal_h), Color(1, 1, 1, 0.95), false, lw)
	var ccr := 24.0
	for c in [[FX0, FY0, 0.0, PI / 2], [FX1, FY0, PI / 2, PI], [FX1, FY1, PI, PI * 1.5], [FX0, FY1, PI * 1.5, TAU]]:
		draw_arc(Vector2(c[0], c[1]), ccr, c[2], c[3], 12, col, lw)

func _draw_footballers() -> void:
	for fp in players:
		var key: String
		if fp.team == "ARG":
			key = "argStar" if fp.is_star else "argCommon"
		else:
			key = "porStar" if fp.is_star else "porCommon"
		var w: float = 30.0 if fp.is_star else 24.0
		var h: float = 44.0 if fp.is_star else 36.0
		var bob := _hop(fp)
		var mod := Color(1, 1, 1, 0.7) if fp.leaving else Color.WHITE
		_draw_sprite(SPRITES[key][fp.anim], fp.pos, w, h, fp.dir.x < -0.1, bob, mod)
		draw_string(font, fp.pos + Vector2(-5, -2 + bob), str(fp.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		if fp.is_star:
			draw_arc(fp.pos + Vector2(0, -4 + bob), 20, 0, TAU, 20, Color("#ffd700"), 2.0)
		# 体力槽
		if not fp.leaving:
			var smax: float = TUNE.star_stamina if fp.is_star else TUNE.common_stamina
			if fp.fleeing or fp.exhausted or fp.stamina < smax - 0.5:
				_draw_mini_bar(fp.pos + Vector2(0, -(30.0 if fp.is_star else 24.0)), fp.stamina / smax, 34.0 if fp.is_star else 20.0, fp.exhausted)
		if fp.being_photo:
			draw_arc(fp.pos + Vector2(0, -4), 25, -PI / 2, -PI / 2 + (fp.progress / 60.0) * TAU, 24, Color("#00e5ff"), 3.0)

func _draw_mini_bar(pos: Vector2, frac: float, w: float, exhausted: bool) -> void:
	var h := 4.0
	draw_rect(Rect2(pos.x - w / 2, pos.y, w, h), Color(0, 0, 0, 0.5))
	var col: Color
	if exhausted: col = Color("#888888")
	elif frac < 0.3: col = Color("#ff5252")
	elif frac < 0.6: col = Color("#ffc107")
	else: col = Color("#4caf50")
	draw_rect(Rect2(pos.x - w / 2, pos.y, w * max(0.0, frac), h), col)

func _draw_security() -> void:
	for s in security:
		var scale := 1.0
		var alpha := 1.0
		if s.state == "charge":
			var t := Time.get_ticks_msec()
			draw_arc(s.pos + Vector2(0, -14), 16, 0, TAU, 20, Color(1, 0.16, 0.16, 0.4 + 0.4 * sin(t * 0.02)), 3.0)
			scale = 0.9
		elif s.state == "lunge":
			scale = 1.18
		elif s.state == "recover":
			alpha = 0.55
		var key: String = "guardElite" if s.elite else "guard"
		var bob := _hop(s) if s.state == "chase" else 0.0
		_draw_sprite(SPRITES[key][s.anim], s.pos, 26 * scale, 38 * scale, s.vel.x < -0.1, bob, Color(1, 1, 1, alpha))
		if s.elite:
			draw_string(font, s.pos + Vector2(-6, -32), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd700"))

func _draw_riot() -> void:
	for r in riot_npcs:
		_draw_sprite(SPRITES["riot"][r.anim], r.pos, 22, 34, r.dir.x < -0.1, _hop(r))

func _draw_mascots() -> void:
	var t := Time.get_ticks_msec()
	for m in mascots:
		var c: Vector2 = m.pos
		var jersey: Color = m.jersey
		var fur: Color = m.fur
		var boot: Color = m.boot
		var dark := Color(fur.r * 0.55, fur.g * 0.55, fur.b * 0.55)
		# 预警 / 休息提示
		if m.state == "aim":
			var aimdir: Vector2 = (p_pos - m.pos).normalized()
			var pulse := 0.45 + 0.4 * sin(t * 0.03)
			draw_line(c + Vector2(0, -28), c + Vector2(0, -28) + aimdir * 1100.0, Color(1.0, 0.2, 0.2, pulse), 5.0)
			draw_arc(c, MASCOT_RADIUS + 10.0, 0, TAU, 26, Color(1, 0.3, 0.3, pulse), 3.0)
		elif m.state == "rest":
			draw_arc(c, MASCOT_RADIUS + 6.0, 0, TAU, 26, Color(0.75, 0.75, 0.75, 0.35), 2.0)
		# 落地软阴影
		draw_circle(c + Vector2(0, -3), 20, Color(0, 0, 0, 0.16))
		var bob: float = -abs(sin(t * 0.02 + float(m.phase))) * 4.0 if m.state == "charge" else 0.0
		var off := Vector2(0, bob)
		# 腿
		for sgn in [-1.0, 1.0]:
			draw_line(c + Vector2(sgn * 8, -17) + off, c + Vector2(sgn * 8, -3), boot, 7.0)
		# 身体（球衣）
		var body: Vector2 = c + Vector2(0, -32) + off
		draw_circle(body, 18, jersey)
		# 手
		for sgn in [-1.0, 1.0]:
			draw_circle(body + Vector2(sgn * 17, 1), 6.5, fur)
		# 头
		var head: Vector2 = c + Vector2(0, -57) + off
		var hr := 21.0
		# —— 头部后方特征（角 / 耳）——
		match m.type:
			"moose":
				var ac := Color("#efe2c2")
				for sgn in [-1.0, 1.0]:
					var b0 := head + Vector2(sgn * 7, -hr * 0.7)
					var b1 := b0 + Vector2(sgn * 12, -10)
					draw_line(b0, b1, ac, 4.0)
					draw_line(b1, b1 + Vector2(sgn * 11, -3), ac, 4.0)
					draw_line(b1, b1 + Vector2(sgn * 3, -12), ac, 4.0)
					draw_line(b1 + Vector2(sgn * 6, -2), b1 + Vector2(sgn * 13, -9), ac, 4.0)
			"jaguar":
				for sgn in [-1.0, 1.0]:
					var ear := PackedVector2Array([
						head + Vector2(sgn * 9, -hr * 0.75),
						head + Vector2(sgn * 20, -hr * 1.05),
						head + Vector2(sgn * 20, -hr * 0.55)])
					draw_colored_polygon(ear, fur)
					draw_circle(head + Vector2(sgn * 16, -hr * 0.8), 3.0, Color("#7a4a8a"))
			"eagle":
				# 头冠羽毛
				draw_colored_polygon(PackedVector2Array([
					head + Vector2(-6, -hr * 0.9), head + Vector2(6, -hr * 0.9), head + Vector2(0, -hr * 1.4)]), fur)
		# 头主体
		draw_circle(head, hr, fur)
		# 大眼睛（萌）：白底 + 朝玩家看的瞳孔
		var look: Vector2 = (p_pos - head).normalized() * 2.4
		for sgn in [-1.0, 1.0]:
			var eye := head + Vector2(sgn * 8, -2)
			draw_circle(eye, 6.6, Color.WHITE)
			draw_circle(eye + look, 3.4, Color(0.08, 0.08, 0.08))
			draw_circle(eye + look + Vector2(-1, -1), 1.1, Color.WHITE)  # 高光
		# —— 头部前方特征（鼻 / 喙 / 斑点）——
		match m.type:
			"moose":
				draw_circle(head + Vector2(0, hr * 0.55), 6.0, Color("#8a5a3a"))  # 大鼻头
			"jaguar":
				draw_colored_polygon(PackedVector2Array([
					head + Vector2(-3, hr * 0.5), head + Vector2(3, hr * 0.5), head + Vector2(0, hr * 0.72)]), Color("#5a3a2a"))
				for sp in [Vector2(-12, -8), Vector2(11, -6), Vector2(-9, 6), Vector2(10, 7)]:
					draw_circle(head + sp * 0.9, 2.0, dark)
			"eagle":
				draw_colored_polygon(PackedVector2Array([
					head + Vector2(-6, hr * 0.35), head + Vector2(6, hr * 0.35), head + Vector2(0, hr * 0.8)]), Color("#ffb83a"))
		# 名字（头顶上方）
		draw_string(font, c + Vector2(-34, -100), m.label, HORIZONTAL_ALIGNMENT_CENTER, 68, 18, m.name_col)

func _draw_player() -> void:
	_draw_sprite(SPRITES["fan"][p_anim], p_pos, 28, 42, p_face.x < -0.1, 0.0 if p_rolling else _hop(self))
	# 头顶体力槽
	var w := 40.0; var h := 5.0
	var y := p_pos.y - (p_radius + 16)
	draw_rect(Rect2(p_pos.x - w / 2, y, w, h), Color(0, 0, 0, 0.5))
	var col := Color("#888888") if p_exhausted else Color("#4caf50")
	draw_rect(Rect2(p_pos.x - w / 2, y, w * (p_stamina / upgrades.stamina_max), h), col)

func _draw_confetti() -> void:
	for c in confetti:
		draw_set_transform(c.pos, c.rot, Vector2.ONE)
		draw_rect(Rect2(-3, -5, 6, 10), c.color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ============================================================================
# UI（代码构建）
# ============================================================================
func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	if font: l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	# 分数 + 信息（顶部居中）
	lbl_score = _mk_label("0", 30, Color("#ffd700"))
	lbl_score.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_score.position.y = 8
	ui.add_child(lbl_score)

	lbl_info = _mk_label("存活 00:00  已合影 0", 14, Color(1, 1, 1, 0.9))
	lbl_info.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_info.position.y = 46
	ui.add_child(lbl_info)

	# 升级等级（右上）
	lbl_levels = _mk_label("", 12, Color("#ffd700"))
	lbl_levels.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_levels.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_levels.position = Vector2(-12, 8)
	lbl_levels.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui.add_child(lbl_levels)

	# 解说
	lbl_comment = _mk_label("", 33, Color.WHITE)
	lbl_comment.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_comment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_comment.position.y = 96
	lbl_comment.modulate.a = 0
	ui.add_child(lbl_comment)

	# 体力槽 + 狂热槽（底部居中）
	bar_stam_fill = _mk_bar(Color("#4caf50"), 30, 13, "体力")
	bar_riot_fill = _mk_bar(Color("#ff8800"), 14, 9, "狂热")

	# 闪光 / 金光 全屏
	flash_rect = _full_rect(Color(1, 1, 1, 1)); flash_rect.modulate.a = 0
	gold_rect = _full_rect(Color("#ffd700")); gold_rect.modulate.a = 0
	# 危机：中间透明、四周泛红的暗角（vignette），而非整屏全红
	danger_rect = TextureRect.new()
	danger_rect.texture = _make_vignette_tex()
	danger_rect.stretch_mode = TextureRect.STRETCH_SCALE
	danger_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	danger_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	danger_rect.modulate.a = 0
	ui.add_child(danger_rect)

	_build_touch_controls()
	_build_panels()

func _mk_bar(fill_color: Color, bottom: int, h: int, label_text: String) -> ColorRect:
	var w := 200.0
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.anchor_left = 0.5; bg.anchor_right = 0.5; bg.anchor_top = 1.0; bg.anchor_bottom = 1.0
	bg.offset_left = -w / 2; bg.offset_right = w / 2
	bg.offset_top = -float(bottom + h); bg.offset_bottom = -float(bottom)
	ui.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.offset_left = 0; fill.offset_top = 0; fill.offset_right = w; fill.offset_bottom = h
	bg.add_child(fill)
	var lab := _mk_label(label_text, 11, Color(0.8, 1, 0.93))
	lab.position = Vector2(-36, -2)
	bg.add_child(lab)
	return fill

func _full_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(r)
	return r

# 生成"中间透明、四周泛红"的暗角贴图（矩形等值线，贴合屏幕边缘）
func _make_vignette_tex() -> ImageTexture:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := (sz - 1) / 2.0
	for y in range(sz):
		for x in range(sz):
			var dx: float = abs(x - c) / c
			var dy: float = abs(y - c) / c
			var d: float = max(dx, dy)             # 0=中心, 1=边缘
			var a: float = smoothstep(0.45, 1.0, d)  # 中心 45% 透明，越靠边越红
			img.set_pixel(x, y, Color(0.85, 0.0, 0.0, a))
	return ImageTexture.create_from_image(img)

func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, ore: float, ob: float) -> void:
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = ore; c.offset_bottom = ob

func _build_touch_controls() -> void:
	# 控件尺寸按屏幕高度的比例计算（适配高分屏，避免在高 DPI 手机上变得很小）
	var vh: float = get_viewport_rect().size.y
	if vh <= 0: vh = 720.0
	var joy_d: float = clampf(vh * 0.38, 220.0, 380.0)
	var knob_d: float = joy_d * 0.46
	var btn_d: float = clampf(vh * 0.27, 150.0, 280.0)
	var edge: float = clampf(vh * 0.06, 28.0, 80.0)
	var gap: float = edge * 0.7
	var fsize: int = int(btn_d * 0.26)

	# 虚拟摇杆（左下）
	var joy := Control.new()
	_place(joy, 0, 1, 0, 1, edge, -(edge + joy_d), edge + joy_d, -edge)
	joy.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(joy)
	var joy_bg := _circle_panel(joy_d, Color(1, 1, 1, 0.18))
	joy.add_child(joy_bg)
	var knob := _circle_panel(knob_d, Color(1, 1, 1, 0.55))
	knob.position = (Vector2(joy_d, joy_d) - Vector2(knob_d, knob_d)) / 2.0
	joy.add_child(knob)
	joy.gui_input.connect(func(e): _joy_input(e, joy, knob))

	# 翻滚（最右下角）
	var rl := _circle_button("翻滚", Color(0.31, 0.59, 1, 0.55), fsize)
	_place(rl, 1, 1, 1, 1, -(edge + btn_d), -(edge + btn_d), -edge, -edge)
	ui.add_child(rl)
	rl.button_down.connect(func(): roll_pressed = true)

	# 冲刺（在翻滚左侧）
	var sp := _circle_button("冲刺", Color(1, 0.31, 0.31, 0.55), fsize)
	_place(sp, 1, 1, 1, 1, -(edge + btn_d * 2 + gap), -(edge + btn_d), -(edge + btn_d + gap), -edge)
	ui.add_child(sp)
	sp.button_down.connect(func(): sprint_held = true)
	sp.button_up.connect(func(): sprint_held = false)

func _circle_panel(d: float, col: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(d / 2); sb.corner_radius_top_right = int(d / 2)
	sb.corner_radius_bottom_left = int(d / 2); sb.corner_radius_bottom_right = int(d / 2)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _circle_button(text: String, col: Color, fsize: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(300)  # 足够大→Godot 自动夹成半径=半边长，得到圆形
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", fsize)
	if font: b.add_theme_font_override("font", font)
	return b

func _joy_input(e: InputEvent, joy: Control, knob: Panel) -> void:
	var center: Vector2 = joy.size / 2.0
	var rest: Vector2 = (joy.size - knob.size) / 2.0   # 摇杆中心位（随尺寸自适应）
	var max_r: float = joy.size.x * 0.34
	var active := false
	var local := Vector2.ZERO
	if e is InputEventScreenTouch:
		if not e.pressed:
			joy_vec = Vector2.ZERO; knob.position = rest; return
		local = e.position - center; active = true
	elif e is InputEventScreenDrag:
		local = e.position - center; active = true
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if not e.pressed:
			joy_vec = Vector2.ZERO; knob.position = rest; return
		local = e.position - center; active = true
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		local = e.position - center; active = true
	if active:
		if local.length() > max_r:
			local = local.normalized() * max_r
		knob.position = rest + local
		joy_vec = local / max_r

# ----------------------------------------------------------------------------
# 面板（开始 / 升级 / 结束）
# ----------------------------------------------------------------------------
func _build_panels() -> void:
	panel_start = _overlay()
	var v := _center_box()
	panel_start.add_child(v)
	v.add_child(_mk_label("Pitch Invader: World Cup Craze", 30, Color("#ffd700")))
	# 加粗强调行（Zpix 像素字体无独立粗体，用更大字号 + 更粗描边模拟"加粗"）
	var emph := _mk_label("挑战更多的合影！更多的疯狂！", 24, Color("#ffd700"))
	emph.add_theme_constant_override("outline_size", 7)
	emph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(emph)
	var desc := _mk_label("冲入决赛球场，疯狂和球员合影刷分！球员源源不断登场，撑到被保安逮捕为止。\n大牌球星(10/7号)会逃跑，贴脸抓住强制合影得双倍分。\nWASD移动，Shift冲刺，Space翻滚；移动端用左摇杆+右按钮。", 15, Color(1, 1, 1, 0.85))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(620, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var btn := _menu_button("开始冲场")
	v.add_child(btn)
	btn.pressed.connect(_start_game)

	panel_upgrade = _overlay()
	panel_upgrade.visible = false
	var uv := _center_box()
	panel_upgrade.add_child(uv)
	uv.add_child(_mk_label("升级时刻！", 26, Color("#ffd700")))
	upgrade_box = VBoxContainer.new()
	upgrade_box.add_theme_constant_override("separation", 12)
	uv.add_child(upgrade_box)

	panel_over = _overlay()
	panel_over.visible = false
	var ov := _center_box()
	panel_over.add_child(ov)
	lbl_over_title = _mk_label("被保安逮捕了！", 34, Color("#ffd700"))
	ov.add_child(lbl_over_title)
	lbl_over_stats = _mk_label("", 18, Color.WHITE)
	lbl_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.add_child(lbl_over_stats)
	var rb := _menu_button("再次冲场")
	ov.add_child(rb)
	rb.pressed.connect(_start_game)

func _overlay() -> Control:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 0.8)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(c)
	return c

func _center_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	# 居中：用全屏容器
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return v

func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 56)
	b.add_theme_font_size_override("font_size", 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#4caf50")
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sb2: StyleBoxFlat = sb.duplicate()
	sb2.bg_color = Color("#66bb6a")
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_color_override("font_color", Color.WHITE)
	if font: b.add_theme_font_override("font", font)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

# ----------------------------------------------------------------------------
# 升级面板逻辑
# ----------------------------------------------------------------------------
func _show_upgrade() -> void:
	state = St.UPGRADE
	panel_upgrade.visible = true
	for c in upgrade_box.get_children():
		c.queue_free()
	var choices := [
		{"label": "体力上限 +30", "key": "stamina_max"},
		{"label": "移速/冲刺速度 +15%", "key": "speed_mult"},
		{"label": "翻滚消耗 -1", "key": "roll_cost"},
		{"label": "合影判定半径 +20%", "key": "photo_radius"},
	]
	choices.shuffle()
	for i in range(2):
		var ch: Dictionary = choices[i]
		var b := _menu_button(ch.label)
		b.custom_minimum_size = Vector2(300, 52)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1b5e20")
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color("#4caf50")
		b.add_theme_stylebox_override("normal", sb)
		var key: String = ch.key
		b.pressed.connect(func(): _apply_upgrade(key))
		upgrade_box.add_child(b)

func _apply_upgrade(key: String) -> void:
	match key:
		"stamina_max":
			upgrades.stamina_max += 30; p_stamina = upgrades.stamina_max
		"speed_mult":
			upgrades.speed_mult += 0.15
		"roll_cost":
			upgrades.roll_cost = max(1.0, upgrades.roll_cost - 1)
		"photo_radius":
			upgrades.photo_radius += 0.2
	up_levels[key] += 1
	gold_flash = 0.6
	_say("永久强化已生效！", Color("#ffd700"))
	panel_upgrade.visible = false
	state = St.PLAY
	_update_levels()

func _update_levels() -> void:
	lbl_levels.text = "体力 Lv%d  移速 Lv%d\n翻滚 Lv%d  视野 Lv%d" % [up_levels.stamina_max, up_levels.speed_mult, up_levels.roll_cost, up_levels.photo_radius]

# ----------------------------------------------------------------------------
# 解说
# ----------------------------------------------------------------------------
func _say(text: String, color: Color) -> void:
	lbl_comment.text = text
	lbl_comment.add_theme_color_override("font_color", color)
	lbl_comment.modulate.a = 1.0
	comment_timer = 2.4

# ----------------------------------------------------------------------------
# 流程控制
# ----------------------------------------------------------------------------
func _start_game() -> void:
	score = 0; elapsed = 0; photographed = 0; next_upgrade_at = 1000
	upgrades = {"stamina_max": 100.0, "speed_mult": 1.0, "roll_cost": float(TUNE.roll_cost), "photo_radius": 1.0}
	up_levels = {"stamina_max": 0, "speed_mult": 0, "roll_cost": 0, "photo_radius": 0}
	p_pos = Vector2(WORLD.x / 2, FY1 - 6)
	p_vel = Vector2.ZERO
	p_face = Vector2(0, -1)
	p_stamina = 100; p_exhausted = false; p_rolling = false; p_roll_cd = 0
	p_combo = 0; p_combo_timer = 0; p_riot = 0
	p_anim = "stand"; p_phase = 0
	_spawn_players()
	security.clear()
	for i in range(int(TUNE.base_security)): _spawn_security(false)
	riot_npcs.clear(); riot_active = false
	mascots.clear(); mascot_spawn_idx = 0
	confetti.clear(); flashes.clear(); chants.clear()
	shake = 0; flash_alpha = 0; gold_flash = 0
	cam.position = p_pos
	cam.reset_smoothing()
	panel_start.visible = false
	panel_over.visible = false
	panel_upgrade.visible = false
	_update_levels()
	state = St.PLAY
	_play_bgm()  # 首次开始时启动循环 BGM（此时已有用户点击手势，可解锁网页音频）
	_say(GameConfig.OPENING_LINE, Color.WHITE)

func _game_over() -> void:
	state = St.OVER
	lbl_over_title.text = GameConfig.ARREST_TITLE_TEMPLATE % security.size()
	lbl_over_stats.text = "得分：%d\n合影人数：%d\n存活时间：%s" % [score, photographed, _fmt_time(elapsed)]
	panel_over.visible = true

func _fmt_time(frames: float) -> String:
	var total := int(frames / 60.0)
	return "%02d:%02d" % [total / 60, total % 60]

func _update_hud() -> void:
	lbl_score.text = str(score)
	lbl_info.text = "存活 %s   已合影 %d" % [_fmt_time(elapsed), photographed]
	flash_rect.modulate.a = flash_alpha
	gold_rect.modulate.a = gold_flash
	var sw: float = (bar_stam_fill.get_parent() as Control).size.x
	bar_stam_fill.size = Vector2(sw * clampf(p_stamina / upgrades.stamina_max, 0, 1), bar_stam_fill.size.y)
	bar_stam_fill.color = Color("#888888") if p_exhausted else (Color("#ff5252") if p_stamina < 25 else Color("#4caf50"))
	var rw: float = (bar_riot_fill.get_parent() as Control).size.x
	bar_riot_fill.size = Vector2(rw * clampf(p_riot / 100.0, 0, 1), bar_riot_fill.size.y)
