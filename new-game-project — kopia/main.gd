extends Control

const SAVE_PATH: String = "user://cookie_save.json"
const SOUND_EXTENSIONS: Array = ["wav", "mp3", "ogg"]
const NORMAL_CUTOFF: float = 20500.0

@export_group("Economy")
@export var start_per_click: int = 1
@export var start_upgrade_cost: int = 10
@export var upgrade_cost_multiplier: float = 1.5
@export var start_auto_cost: int = 50
@export var auto_cost_multiplier: float = 1.6
@export var combo_window: float = 0.6
@export var milestone_every: int = 100

@export_group("Texts")
@export var score_text: String = "Cookies: {n}"
@export var per_second_text: String = "per second: {n}"
@export var upgrade_text: String = "Upgrade +1/click (cost: {cost})"
@export var auto_text: String = "Auto-baker +1/sec (cost: {cost})  owned: {owned}"
@export var combo_text: String = "COMBO x{n}"
@export var new_game_text: String = "New Game"
@export var confirm_text: String = "Sure? Click again"

@export_group("Save")
@export var autosave: bool = true
@export var autosave_seconds: float = 5.0

@export_group("Effects")
@export var animate_background: bool = true
@export var background_drift_speed: float = 0.02
@export var glow_pulse: bool = true
@export var combo_rainbow: bool = true
@export var idle_sway_degrees: float = 3.0
@export var shake_strength: float = 1.0
@export var falling_cookies: bool = true
@export var falling_cookie_interval: float = 0.5
@export var hit_stop_on_milestone: bool = true

@export_group("Sounds")
@export var combo_sound_prefix: String = "Epic"
@export var click_sound_prefix: String = "epic"
@export var ui_sound_prefix: String = "UIClick"
@export var click_volume_db: float = -8.0
@export var combo_volume_db: float = -3.0
@export var hover_volume_db: float = 10.0
@export var shop_click_volume_db: float = -6.0
@export var menu_click_volume_db: float = -6.0
@export var click_max_seconds: float = 1.0
@export var combo_max_seconds: float = 3.0
@export var ui_max_seconds: float = 1.0

@export_group("Music")
@export var music_prefix: String = "Cookie_Drift"
@export var music_volume_db: float = -8.0
@export var menu_music_db: float = -6.0
@export var menu_music_cutoff: float = 800.0

var cookies: int = 0
var per_click: int = 1
var upgrade_cost: int = 10
var auto_count: int = 0
var auto_cost: int = 50

var shown_cookies: float = 0.0
var combo: int = 0
var combo_time: float = 0.0
var last_milestone: int = 0
var glow_time: float = 0.0
var auto_accum: float = 0.0
var fall_timer: float = 0.0
var save_timer: float = 0.0
var menu_open: bool = false
var new_armed: bool = false
var new_armed_time: float = 0.0
var hovered: bool = false

var base_position: Vector2
var base_cookie_scale: Vector2 = Vector2.ONE
var base_cookie_rotation: float = 0.0
var base_score_scale: Vector2 = Vector2.ONE
var base_glow_scale: Vector2 = Vector2.ONE
var base_glow_modulate: Color = Color.WHITE
var base_combo_scale: Vector2 = Vector2.ONE
var base_combo_rotation: float = 0.0
var base_combo_modulate: Color = Color.WHITE
var base_panel_scale: Vector2 = Vector2.ONE
var flash_rgb: Color = Color.WHITE
var bg_gradient: Gradient
var base_bg_colors: PackedColorArray = PackedColorArray()

var click_sounds: Array = []
var combo_sounds: Array = []
var hover_sounds: Array = []
var shop_click_sounds: Array = []
var menu_click_sounds: Array = []
var music_stream: AudioStream
var music_player: AudioStreamPlayer
var music_bus: int = -1
var lowpass: AudioEffectLowPassFilter
var muffle_tween: Tween
var bounce_tween: Tween
var shake_tween: Tween

@onready var background: TextureRect = find_child("Background", true, false) as TextureRect
@onready var glow: Control = find_child("Glow", true, false) as Control
@onready var vignette: Node = find_child("Vignette", true, false)
@onready var score_label: Label = find_child("ScoreLabel", true, false) as Label
@onready var cps_label: Label = find_child("PerSecondLabel", true, false) as Label
@onready var cookie_button: TextureButton = find_child("CookieButton", true, false) as TextureButton
@onready var upgrade_button: Button = find_child("UpgradeButton", true, false) as Button
@onready var auto_button: Button = find_child("AutoButton", true, false) as Button
@onready var combo_label: Label = find_child("ComboLabel", true, false) as Label
@onready var flash: ColorRect = find_child("Flash", true, false) as ColorRect
@onready var pause_menu: Control = find_child("PauseMenu", true, false) as Control
@onready var menu_panel: Control = find_child("MenuPanel", true, false) as Control
@onready var resume_button: Button = find_child("ResumeButton", true, false) as Button
@onready var new_button: Button = find_child("NewGameButton", true, false) as Button
@onready var quit_button: Button = find_child("QuitButton", true, false) as Button


func _ready() -> void:
	randomize()
	print("Running scene: ", scene_file_path)
	if cookie_button == null or score_label == null:
		push_error("CookieButton or ScoreLabel not found in the scene")
		set_process(false)
		return
	remember_editor_values()
	load_sounds()
	setup_music()
	reset_state()
	cookie_button.button_down.connect(_on_cookie_pressed)
	cookie_button.mouse_entered.connect(_on_cookie_hover_on)
	cookie_button.mouse_exited.connect(_on_cookie_hover_off)
	cookie_button.resized.connect(_on_cookie_resized)
	_on_cookie_resized()
	if upgrade_button != null:
		upgrade_button.pressed.connect(_on_upgrade_pressed)
	if auto_button != null:
		auto_button.pressed.connect(_on_auto_pressed)
	if resume_button != null:
		resume_button.pressed.connect(close_menu)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)
	if new_button != null:
		new_button.pressed.connect(_on_new_game_pressed)
	for b in [upgrade_button, auto_button, resume_button, new_button, quit_button]:
		if b != null:
			b.mouse_entered.connect(_on_button_hover.bind(b))
	for mb in [resume_button, new_button, quit_button]:
		if mb != null:
			mb.pressed.connect(_on_menu_button_pressed)
	if pause_menu != null:
		pause_menu.visible = false
	start_idle_sway()
	if autosave:
		load_game()
	update_ui()


func remember_editor_values() -> void:
	base_position = position
	base_cookie_scale = cookie_button.scale
	base_cookie_rotation = cookie_button.rotation_degrees
	base_score_scale = score_label.scale
	if glow != null:
		base_glow_scale = glow.scale
		base_glow_modulate = glow.modulate
		glow.pivot_offset = glow.size / 2.0
	if combo_label != null:
		base_combo_scale = combo_label.scale
		base_combo_rotation = combo_label.rotation_degrees
		base_combo_modulate = combo_label.modulate
		combo_label.pivot_offset = combo_label.size / 2.0
		combo_label.visible = false
	if flash != null:
		flash_rgb = flash.color
		flash.color = Color(flash_rgb.r, flash_rgb.g, flash_rgb.b, 0.0)
	if menu_panel != null:
		base_panel_scale = menu_panel.scale
	if background != null and background.texture is GradientTexture2D:
		bg_gradient = (background.texture as GradientTexture2D).gradient
		if bg_gradient != null:
			base_bg_colors = bg_gradient.colors.duplicate()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and autosave:
		save_game()


func _on_cookie_resized() -> void:
	cookie_button.pivot_offset = cookie_button.size / 2.0


func _on_cookie_hover_on() -> void:
	hovered = true


func _on_cookie_hover_off() -> void:
	hovered = false


func _process(delta: float) -> void:
	glow_time += delta
	var t: float = clampf(delta * 10.0, 0.0, 1.0)
	shown_cookies = lerpf(shown_cookies, float(cookies), t)
	score_label.text = score_text.format({"n": roundi(shown_cookies)})

	var heat: float = clampf(float(combo) / 30.0, 0.0, 1.0)
	update_background(heat)
	update_glow(heat)

	if combo > 0 and not menu_open:
		combo_time -= delta
		if combo_label != null and combo_rainbow:
			combo_label.modulate = base_combo_modulate * Color.from_hsv(fposmod(glow_time * 0.8, 1.0), 0.6, 1.0)
		if combo_time <= 0.0:
			combo = 0
			if combo_label != null:
				combo_label.visible = false
				combo_label.modulate = base_combo_modulate

	if auto_count > 0 and not menu_open:
		auto_accum += delta
		if auto_accum >= 1.0:
			auto_accum -= 1.0
			cookies += auto_count
			spawn_popup(cookie_center() + Vector2.UP * 90.0, "+" + str(auto_count), Color.LIGHT_CYAN, 24)
			update_ui()

	if falling_cookies:
		fall_timer += delta
		if fall_timer >= falling_cookie_interval:
			fall_timer = 0.0
			spawn_falling_cookie()

	if autosave:
		save_timer += delta
		if save_timer >= autosave_seconds:
			save_timer = 0.0
			save_game()

	if new_armed:
		new_armed_time -= delta
		if new_armed_time <= 0.0:
			new_armed = false
			update_ui()


func cookie_center() -> Vector2:
	return cookie_button.global_position + cookie_button.size / 2.0


func update_background(heat: float) -> void:
	if not animate_background or bg_gradient == null or base_bg_colors.is_empty():
		return
	var shift: float = glow_time * background_drift_speed + heat * 0.12
	var cols: PackedColorArray = PackedColorArray()
	for c in base_bg_colors:
		cols.append(Color.from_hsv(fposmod(c.h + shift, 1.0), c.s, c.v, c.a))
	bg_gradient.colors = cols


func update_glow(heat: float) -> void:
	if glow == null or not glow_pulse:
		return
	var pulse: float = 1.0 + sin(glow_time * 2.0) * 0.05 + heat * 0.3
	if hovered:
		pulse += 0.08
	glow.scale = base_glow_scale * pulse
	var rainbow: Color = Color.from_hsv(fposmod(glow_time * 0.4, 1.0), 0.6, 1.0)
	var tint: Color = Color.WHITE.lerp(rainbow, heat)
	tint.a = 0.7 + heat * 0.3
	glow.modulate = base_glow_modulate * tint


func _on_cookie_pressed() -> void:
	if menu_open:
		return
	cookies += per_click
	combo += 1
	combo_time = combo_window
	var pos: Vector2 = get_global_mouse_position()
	var center: Vector2 = cookie_center()
	var heat: float = clampf(float(combo) / 30.0, 0.0, 1.0)
	var pop_color: Color = Color.WHITE.lerp(Color.RED, heat)
	var pop_size: int = 28 + int(heat * 30.0)

	play_bounce()
	flash_cookie()
	pop_label()
	spawn_crumbs(pos, 10 + combo, Color.ORANGE)
	spawn_cookie_bits(pos, 3 + int(heat * 6.0))
	spawn_ring(center, Color.WHITE.lerp(Color.GOLD, heat))
	spawn_popup(pos, "+" + str(per_click), pop_color, pop_size)
	shake(2.0 + heat * 8.0)
	pop_combo_label()

	if posmod(combo, 10) == 0:
		play_sound(combo_sounds, combo_volume_db, 1.0, combo_max_seconds)
		spawn_popup(pos + Vector2.UP * 50.0, combo_text.format({"n": combo}) + "!", Color.GOLD, 40)
		spawn_crumbs(pos, 40, Color.GOLD)
		spawn_ring(center, Color.GOLD)
		shake(14.0)
	else:
		play_sound(click_sounds, click_volume_db, randf_range(0.95, 1.05) + heat * 0.25, click_max_seconds)

	if milestone_every > 0:
		var milestone: int = floori(float(cookies) / float(milestone_every))
		if milestone > last_milestone:
			last_milestone = milestone
			spawn_crumbs(center, 80, Color.YELLOW)
			spawn_cookie_bits(center, 14)
			spawn_ring(center, Color.YELLOW)
			spawn_popup(center + Vector2.UP * 80.0, str(milestone * milestone_every) + " COOKIES!", Color.GOLD, 48)
			screen_flash(0.55)
			play_sound(combo_sounds, combo_volume_db + 1.0, 0.9, combo_max_seconds)
			if hit_stop_on_milestone:
				hit_stop(0.08)
			shake(18.0)

	update_ui()


func _on_upgrade_pressed() -> void:
	if menu_open or cookies < upgrade_cost:
		return
	play_sound(shop_click_sounds, shop_click_volume_db, 1.0, ui_max_seconds)
	cookies -= upgrade_cost
	per_click += 1
	upgrade_cost = int(upgrade_cost * upgrade_cost_multiplier)
	buy_effect(upgrade_button, Color.LIGHT_GREEN, "UPGRADED!")
	update_ui()


func _on_auto_pressed() -> void:
	if menu_open or cookies < auto_cost:
		return
	play_sound(shop_click_sounds, shop_click_volume_db, 1.0, ui_max_seconds)
	cookies -= auto_cost
	auto_count += 1
	auto_cost = int(auto_cost * auto_cost_multiplier)
	buy_effect(auto_button, Color.LIGHT_SKY_BLUE, "AUTO-BAKER!")
	update_ui()


func buy_effect(b: Button, color: Color, text: String) -> void:
	var c: Vector2 = b.global_position + b.size / 2.0
	spawn_crumbs(c, 30, color)
	spawn_ring(c, color)
	spawn_popup(c + Vector2.UP * 30.0, text, color, 34)
	pop_control(b, 1.15, 0.3)
	shake(8.0)


func pop_control(c: Control, amount: float, time: float) -> void:
	var base: Vector2 = c.scale
	if c.has_meta("base_scale"):
		base = c.get_meta("base_scale")
	else:
		c.set_meta("base_scale", base)
	c.pivot_offset = c.size / 2.0
	c.scale = base * amount
	var tw: Tween = create_tween()
	tw.tween_property(c, "scale", base, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_bounce() -> void:
	if bounce_tween:
		bounce_tween.kill()
	cookie_button.scale = base_cookie_scale * 0.82
	bounce_tween = create_tween()
	bounce_tween.tween_property(cookie_button, "scale", base_cookie_scale, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func flash_cookie() -> void:
	var base: Color = cookie_button.self_modulate
	cookie_button.self_modulate = Color(1.7, 1.7, 1.7, base.a)
	var tw: Tween = create_tween()
	tw.tween_property(cookie_button, "self_modulate", Color(1.0, 1.0, 1.0, base.a), 0.15)


func pop_label() -> void:
	score_label.pivot_offset = score_label.size / 2.0
	score_label.scale = base_score_scale * 1.2
	var tw: Tween = create_tween()
	tw.tween_property(score_label, "scale", base_score_scale, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func pop_combo_label() -> void:
	if combo_label == null or combo < 3:
		return
	combo_label.visible = true
	combo_label.text = combo_text.format({"n": combo})
	combo_label.scale = base_combo_scale * 1.35
	combo_label.rotation_degrees = base_combo_rotation + randf_range(-4.0, 4.0)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(combo_label, "scale", base_combo_scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(combo_label, "rotation_degrees", base_combo_rotation, 0.2)


func screen_flash(alpha: float) -> void:
	if flash == null:
		return
	flash.color = Color(flash_rgb.r, flash_rgb.g, flash_rgb.b, alpha)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.4)


func hit_stop(duration: float) -> void:
	Engine.time_scale = 0.15
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func start_idle_sway() -> void:
	if idle_sway_degrees <= 0.0:
		return
	var tw: Tween = create_tween()
	tw.set_loops()
	tw.tween_property(cookie_button, "rotation_degrees", base_cookie_rotation + idle_sway_degrees, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cookie_button, "rotation_degrees", base_cookie_rotation - idle_sway_degrees, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func shake(strength: float) -> void:
	if shake_strength <= 0.0:
		return
	if shake_tween:
		shake_tween.kill()
	shake_tween = create_tween()
	for i in range(5):
		var off: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * shake_strength
		shake_tween.tween_property(self, "position", base_position + off, 0.03)
	shake_tween.tween_property(self, "position", base_position, 0.05)


func spawn_ring(center: Vector2, color: Color) -> void:
	var ring: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.set_border_width_all(6)
	sb.border_color = color
	sb.set_corner_radius_all(100)
	ring.add_theme_stylebox_override("panel", sb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(200.0, 200.0)
	ring.pivot_offset = Vector2(100.0, 100.0)
	add_child(ring)
	ring.global_position = center - Vector2(100.0, 100.0)
	ring.scale = Vector2(0.3, 0.3)
	var tw: Tween = ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.2, 2.2), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)


func spawn_cookie_bits(pos: Vector2, amount: int) -> void:
	var tex: Texture2D = cookie_button.texture_normal
	if tex == null:
		return
	for i in range(amount):
		var r: TextureRect = TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s: float = randf_range(18.0, 34.0)
		r.size = Vector2(s, s)
		r.pivot_offset = r.size / 2.0
		add_child(r)
		r.global_position = pos - r.size / 2.0
		var start: Vector2 = r.position
		var dx: float = randf_range(-220.0, 220.0)
		var peak: float = randf_range(120.0, 260.0)
		var tx: Tween = r.create_tween()
		tx.set_parallel(true)
		tx.tween_property(r, "position:x", start.x + dx, 0.9)
		tx.tween_property(r, "rotation", randf_range(-6.0, 6.0), 0.9)
		tx.tween_property(r, "modulate:a", 0.0, 0.3).set_delay(0.6)
		var ty: Tween = r.create_tween()
		ty.tween_property(r, "position:y", start.y - peak, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ty.tween_property(r, "position:y", start.y + 300.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ty.tween_callback(r.queue_free)


func spawn_falling_cookie() -> void:
	var tex: Texture2D = cookie_button.texture_normal
	if tex == null:
		return
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s: float = randf_range(30.0, 70.0)
	r.size = Vector2(s, s)
	r.pivot_offset = r.size / 2.0
	r.modulate = Color(1.0, 1.0, 1.0, 0.3)
	add_child(r)
	if vignette != null and vignette.get_parent() == self:
		move_child(r, vignette.get_index())
	elif background != null and background.get_parent() == self:
		move_child(r, background.get_index() + 1)
	else:
		move_child(r, 0)
	r.position = Vector2(randf_range(0.0, size.x), -80.0)
	var dur: float = randf_range(7.0, 12.0)
	var tw: Tween = r.create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "position:y", size.y + 80.0, dur)
	tw.tween_property(r, "rotation", randf_range(-4.0, 4.0), dur)
	tw.chain().tween_callback(r.queue_free)


func spawn_crumbs(pos: Vector2, amount: int, color: Color) -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	add_child(p)
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.8
	p.direction = Vector2.UP
	p.spread = 80.0
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0.0, 900.0)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 8.0
	p.color = color
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func spawn_popup(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var l: Label = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	add_child(l)
	l.global_position = pos + Vector2(randf_range(-40.0, 40.0), -40.0)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 130.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func update_ui() -> void:
	if cps_label != null:
		cps_label.text = per_second_text.format({"n": auto_count})
	if upgrade_button != null:
		upgrade_button.text = upgrade_text.format({"cost": upgrade_cost})
		upgrade_button.disabled = cookies < upgrade_cost
	if auto_button != null:
		auto_button.text = auto_text.format({"cost": auto_cost, "owned": auto_count})
		auto_button.disabled = cookies < auto_cost
	if new_button != null:
		if new_armed:
			new_button.text = confirm_text
		else:
			new_button.text = new_game_text


func load_sounds() -> void:
	click_sounds.clear()
	combo_sounds.clear()
	hover_sounds.clear()
	shop_click_sounds.clear()
	menu_click_sounds.clear()
	scan_sounds("res://")
	print("Sounds found: ", click_sounds.size(), " click, ", combo_sounds.size(), " combo")
	print("Button sounds: ", hover_sounds.size(), " hover, ", shop_click_sounds.size(), " upgrade click, ", menu_click_sounds.size(), " menu click")


func add_unique(list: Array, stream: AudioStream) -> void:
	if stream != null and not list.has(stream):
		list.append(stream)


func scan_sounds(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for entry in dir.get_directories():
		if not entry.begins_with("."):
			scan_sounds(dir_path.path_join(entry))
	for file_name in dir.get_files():
		var clean: String = file_name.trim_suffix(".import").trim_suffix(".remap")
		if not SOUND_EXTENSIONS.has(clean.get_extension().to_lower()):
			continue
		var path: String = dir_path.path_join(clean)
		var lower: String = clean.to_lower()
		if ui_sound_prefix != "" and lower.begins_with(ui_sound_prefix.to_lower()):
			if lower.contains("hoover") or lower.contains("hover"):
				add_unique(hover_sounds, load(path) as AudioStream)
			elif lower.contains("tactile") or lower.contains("tacticle"):
				add_unique(shop_click_sounds, load(path) as AudioStream)
			elif lower.contains("soft"):
				add_unique(menu_click_sounds, load(path) as AudioStream)
		elif music_prefix != "" and clean.begins_with(music_prefix):
			if music_stream == null:
				music_stream = load(path) as AudioStream
		elif combo_sound_prefix != "" and clean.begins_with(combo_sound_prefix):
			add_unique(combo_sounds, load(path) as AudioStream)
		elif click_sound_prefix != "" and clean.begins_with(click_sound_prefix):
			add_unique(click_sounds, load(path) as AudioStream)


func play_sound(list: Array, volume_db: float, pitch: float, max_seconds: float) -> void:
	if list.is_empty():
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	get_tree().create_timer(max_seconds).timeout.connect(p.queue_free)


func _on_button_hover(b: Button) -> void:
	if b.disabled:
		return
	play_sound(hover_sounds, hover_volume_db, randf_range(0.97, 1.03), ui_max_seconds)


func _on_menu_button_pressed() -> void:
	play_sound(menu_click_sounds, menu_click_volume_db, 1.0, ui_max_seconds)


func setup_music() -> void:
	if music_stream == null:
		print("No music found (file name should start with ", music_prefix, ")")
		return
	if music_stream is AudioStreamMP3:
		(music_stream as AudioStreamMP3).loop = true
	elif music_stream is AudioStreamOggVorbis:
		(music_stream as AudioStreamOggVorbis).loop = true
	music_bus = AudioServer.get_bus_index("Music")
	if music_bus == -1:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus, "Music")
		AudioServer.set_bus_send(music_bus, "Master")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = NORMAL_CUTOFF
	AudioServer.add_bus_effect(music_bus, lowpass)
	AudioServer.set_bus_volume_db(music_bus, 0.0)
	music_player = AudioStreamPlayer.new()
	music_player.stream = music_stream
	music_player.bus = "Music"
	music_player.volume_db = music_volume_db
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)
	music_player.play()
	print("Music playing")


func _on_music_finished() -> void:
	music_player.play()


func set_muffle(on: bool) -> void:
	if music_bus < 0:
		return
	if muffle_tween:
		muffle_tween.kill()
	var target_db: float = 0.0
	var target_cut: float = NORMAL_CUTOFF
	if on:
		target_db = menu_music_db
		target_cut = menu_music_cutoff
	muffle_tween = create_tween()
	muffle_tween.set_parallel(true)
	muffle_tween.tween_method(_set_music_bus_db, AudioServer.get_bus_volume_db(music_bus), target_db, 0.3)
	muffle_tween.tween_property(lowpass, "cutoff_hz", target_cut, 0.3)


func _set_music_bus_db(v: float) -> void:
	AudioServer.set_bus_volume_db(music_bus, v)


func _unhandled_input(event: InputEvent) -> void:
	if pause_menu == null:
		return
	if event.is_action_pressed("ui_cancel"):
		if menu_open:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	if pause_menu == null or menu_open:
		return
	menu_open = true
	new_armed = false
	set_muffle(true)
	update_ui()
	pause_menu.visible = true
	pause_menu.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(pause_menu, "modulate:a", 1.0, 0.15)
	if menu_panel != null:
		menu_panel.pivot_offset = menu_panel.size / 2.0
		menu_panel.scale = base_panel_scale * 0.9
		tw.tween_property(menu_panel, "scale", base_panel_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_menu() -> void:
	if pause_menu == null or not menu_open:
		return
	menu_open = false
	new_armed = false
	set_muffle(false)
	update_ui()
	pause_menu.visible = false


func _on_quit_pressed() -> void:
	if autosave:
		save_game()
	get_tree().quit()


func _on_new_game_pressed() -> void:
	if not new_armed:
		new_armed = true
		new_armed_time = 3.0
		update_ui()
		return
	new_armed = false
	reset_state()
	save_game()
	spawn_popup(new_button.global_position + new_button.size / 2.0 + Vector2(0.0, 70.0), "NEW GAME!", Color.GOLD, 28)
	screen_flash(0.5)
	close_menu()
	update_ui()


func reset_state() -> void:
	cookies = 0
	per_click = start_per_click
	upgrade_cost = start_upgrade_cost
	auto_count = 0
	auto_cost = start_auto_cost
	shown_cookies = 0.0
	combo = 0
	last_milestone = 0
	auto_accum = 0.0
	if combo_label != null:
		combo_label.visible = false


func save_game() -> bool:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var d: Dictionary = {
		"cookies": cookies,
		"per_click": per_click,
		"upgrade_cost": upgrade_cost,
		"auto_count": auto_count,
		"auto_cost": auto_cost
	}
	f.store_string(JSON.stringify(d))
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	cookies = int(d.get("cookies", 0))
	per_click = int(d.get("per_click", start_per_click))
	upgrade_cost = int(d.get("upgrade_cost", start_upgrade_cost))
	auto_count = int(d.get("auto_count", 0))
	auto_cost = int(d.get("auto_cost", start_auto_cost))
	shown_cookies = float(cookies)
	if milestone_every > 0:
		last_milestone = floori(float(cookies) / float(milestone_every))
	combo = 0
	if combo_label != null:
		combo_label.visible = false
	return true
