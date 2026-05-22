extends Node2D

# palette (shared with the rest of the game)
const C_BG_TOP := Color(0.04, 0.02, 0.10)
const C_BG_BOT := Color(0.08, 0.04, 0.04)
const C_FLOOR  := Color(0.12, 0.08, 0.06)
const C_STONE  := Color(0.22, 0.18, 0.16)

var _blink_timer: float = 0.0
var _blink_show:  bool  = true
var _lbl_prompt:  Label

func _ready() -> void:
	
	if AiBridge.ai_enabled:
		call_deferred("_start_ai_game")
		return
	
	var vp: Vector2 = get_viewport().size
	var vw: float   = vp.x
	var vh: float   = vp.y

	var canvas := CanvasLayer.new()
	add_child(canvas)

	# ── title ─────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "DUNGEON\nDELVE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(vw * 0.5 - 240, vh * 0.12)
	title.custom_minimum_size = Vector2(480, 200)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.20))
	canvas.add_child(title)

	# drop shadow
	var shadow := Label.new()
	shadow.text = "DUNGEON\nDELVE"
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.position = Vector2(vw * 0.5 - 237, vh * 0.123)
	shadow.custom_minimum_size = Vector2(480, 200)
	shadow.add_theme_font_size_override("font_size", 72)
	shadow.add_theme_color_override("font_color", Color(0.55, 0.25, 0.05, 0.55))
	shadow.z_index = -1
	canvas.add_child(shadow)

	# ── subtitle ──────────────────────────────────────────────────────────
	var sub := Label.new()
	sub.text = "— A descent into darkness —"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(vw * 0.5 - 260, vh * 0.46)
	sub.custom_minimum_size = Vector2(520, 30)
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.65, 0.55, 0.40))
	canvas.add_child(sub)

	# ── blink prompt ──────────────────────────────────────────────────────
	_lbl_prompt = Label.new()
	_lbl_prompt.text = "PRESS ANY KEY TO START"
	_lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_prompt.position = Vector2(vw * 0.5 - 200, vh * 0.72)
	_lbl_prompt.custom_minimum_size = Vector2(400, 28)
	_lbl_prompt.add_theme_font_size_override("font_size", 20)
	_lbl_prompt.add_theme_color_override("font_color", Color(0.90, 0.90, 0.80))
	canvas.add_child(_lbl_prompt)

func _start_ai_game() -> void:
	
	GameManager.start_new_game(GameManager.ai_class,AiBridge.start_seed)
	get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
func _process(delta: float) -> void:
	if _lbl_prompt == null: return
	
	_blink_timer += delta
	if _blink_timer >= 0.55:
		_blink_timer = 0.0
		_blink_show  = not _blink_show
		_lbl_prompt.modulate.a = 1.0 if _blink_show else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		get_tree().change_scene_to_file("res://scenes/class_select.tscn")
	if event is InputEventMouseButton and event.pressed:
		get_tree().change_scene_to_file("res://scenes/class_select.tscn")

# ── procedural dungeon background ─────────────────────────────────────────────
func _draw() -> void:
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y

	# gradient background
	var steps: int = 40
	for i in range(steps):
		var t: float   = float(i) / float(steps)
		var col: Color = C_BG_TOP.lerp(C_BG_BOT, t)
		var y0: float  = t * vh * 0.62
		var y1: float  = (t + 1.0 / float(steps)) * vh * 0.62
		draw_rect(Rect2(0, y0, vw, y1 - y0 + 1), col)

	# stone floor
	draw_rect(Rect2(0, vh * 0.62, vw, vh * 0.38), C_FLOOR)

	# floor tiles
	var tile_w: float = 64.0
	var tile_h: float = 32.0
	var rows: int = int(vh * 0.38 / tile_h) + 2
	var cols: int = int(vw / tile_w) + 2
	for r in range(rows):
		for c in range(cols):
			var ox: float = (tile_w * 0.5) if (r % 2 == 1) else 0.0
			var tx: float = c * tile_w - ox
			var ty: float = vh * 0.62 + r * tile_h
			var shade: float = 0.55 + 0.1 * ((r + c) % 2)
			draw_rect(Rect2(tx + 1, ty + 1, tile_w - 2, tile_h - 2), C_STONE * shade)

	# dungeon corridor arch
	_draw_arch(vw, vh)

	# atmospheric torches on the sides
	_draw_torch(Vector2(vw * 0.18, vh * 0.38), vw, vh)
	_draw_torch(Vector2(vw * 0.82, vh * 0.38), vw, vh)

func _draw_arch(vw: float, vh: float) -> void:
	var cx: float  = vw * 0.5
	var aw: float  = vw * 0.50
	var ah: float  = vh * 0.50
	var top: float = vh * 0.10

	# side walls
	draw_rect(Rect2(0, 0, cx - aw * 0.5, vh * 0.62), Color(0.10, 0.07, 0.07))
	draw_rect(Rect2(cx + aw * 0.5, 0, vw - (cx + aw * 0.5), vh * 0.62), Color(0.10, 0.07, 0.07))

	# arch opening
	draw_rect(Rect2(cx - aw * 0.5, top, aw, ah), Color(0.01, 0.01, 0.03))

	# keystone arch lintel
	var stone_h: float = 14.0
	var stone_w: float = 36.0
	var num: int = int(aw / stone_w) + 1
	for i in range(num):
		var sx: float  = cx - aw * 0.5 + i * stone_w
		var sc: Color  = Color(0.28, 0.22, 0.19) if (i % 2 == 0) else Color(0.18, 0.14, 0.12)
		draw_rect(Rect2(sx, top - stone_h, stone_w - 1, stone_h), sc)

	# pillars
	draw_rect(Rect2(cx - aw * 0.5 - 24, top, 24, ah), Color(0.22, 0.17, 0.15))
	draw_rect(Rect2(cx + aw * 0.5,       top, 24, ah), Color(0.22, 0.17, 0.15))

	# depth — a smaller inner arch
	var iw: float = aw * 0.60
	var ih: float = ah * 0.70
	var it: float = top + ah * 0.15
	draw_rect(Rect2(cx - iw * 0.5, it, iw, ih), Color(0.005, 0.005, 0.015))
	for i in range(int(iw / stone_w) + 1):
		var sx: float = cx - iw * 0.5 + i * stone_w
		var sc: Color = Color(0.20, 0.16, 0.13) if (i % 2 == 0) else Color(0.13, 0.10, 0.09)
		draw_rect(Rect2(sx, it - 10, stone_w - 1, 10), sc)

func _draw_torch(pos: Vector2, _vw: float, _vh: float) -> void:
	# bracket
	draw_rect(Rect2(pos.x - 4, pos.y, 8, 20), Color(0.30, 0.22, 0.14))
	# flame layers (outer → inner)
	draw_circle(pos + Vector2(0, -4), 14, Color(0.70, 0.22, 0.04, 0.80))
	draw_circle(pos + Vector2(0, -8), 10, Color(0.95, 0.55, 0.06, 0.90))
	draw_circle(pos + Vector2(0, -12), 6,  Color(1.00, 0.90, 0.40, 0.95))
	draw_circle(pos + Vector2(0, -15), 3,  Color(1.00, 1.00, 0.85, 1.00))
	# glow halo
	draw_circle(pos + Vector2(0, -8), 32, Color(0.80, 0.45, 0.05, 0.12))
