extends Node2D

const C_BG_TOP := Color(0.04, 0.02, 0.10)
const C_BG_BOT := Color(0.08, 0.04, 0.04)
const C_FLOOR  := Color(0.12, 0.08, 0.06)
const C_STONE  := Color(0.22, 0.18, 0.16)

const CLASS_STATS: Dictionary = {
	"warrior": {"hp": 5, "mp": 2, "atk": 4, "mag": 1, "crit": 1,
		"flavor": "A sturdy fighter hardened by\nbattle. Best for beginners.",
		"color": Color(0.95, 0.35, 0.30)},
	"mage":    {"hp": 2, "mp": 5, "atk": 2, "mag": 5, "crit": 1,
		"flavor": "A powerful spellcaster.\nSkeletons crumble before magic.",
		"color": Color(0.45, 0.55, 1.00)},
	"thief":   {"hp": 3, "mp": 3, "atk": 3, "mag": 2, "crit": 5,
		"flavor": "An agile rogue with massive\ncrits. Unpredictable.",
		"color": Color(0.30, 0.90, 0.35)},
}

var _cards: Dictionary = {}   # cls -> Control

func _ready() -> void:
	var vp: Vector2 = get_viewport().size
	var vw: float   = vp.x
	var vh: float   = vp.y

	var canvas := CanvasLayer.new()
	add_child(canvas)

	# ── title ─────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "Choose Your Class"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(vw * 0.5 - 280, 18)
	title.custom_minimum_size = Vector2(560, 36)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.20))
	canvas.add_child(title)

	# ── three class cards ─────────────────────────────────────────────────
	var classes: Array = ["warrior", "mage", "thief"]
	var card_w:  float = 230.0
	var card_h:  float = vh * 0.76
	var gap:     float = 26.0
	var total_w: float = card_w * 3 + gap * 2
	var start_x: float = vw * 0.5 - total_w * 0.5
	var card_y:  float = 68.0

	for i in range(classes.size()):
		var cls: String = classes[i]
		var cx: float   = start_x + i * (card_w + gap)
		var card := _build_card(cls, card_w, card_h, canvas)
		card.position = Vector2(cx, card_y)
		_cards[cls] = card

func _build_card(cls: String, w: float, h: float, parent: Node) -> Control:
	var info: Dictionary = CLASS_STATS[cls]
	var col:  Color      = info["color"]

	# outer container
	var card := Control.new()
	card.custom_minimum_size = Vector2(w, h)
	parent.add_child(card)

	# panel background
	var panel := PanelContainer.new()
	panel.position = Vector2(0, 0)
	panel.custom_minimum_size = Vector2(w, h)
	panel.name = "Panel"
	_set_card_style(panel, col, false)
	card.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# class name header
	var name_lbl := Label.new()
	name_lbl.text = cls.to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", col)
	vbox.add_child(name_lbl)

	# weapon sprite
	var sprite_wrap := Control.new()
	sprite_wrap.custom_minimum_size = Vector2(w - 20, 130)
	sprite_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sprite_wrap)

	var weapon_node := _WeaponSprite.new()
	weapon_node.weapon_class = cls
	weapon_node.position     = Vector2(w * 0.5 - 10, 90)
	sprite_wrap.add_child(weapon_node)

	# divider
	var div := ColorRect.new()
	div.color = col * 0.5
	div.custom_minimum_size = Vector2(w - 20, 2)
	vbox.add_child(div)

	# stat rows
	var stats_v := VBoxContainer.new()
	stats_v.add_theme_constant_override("separation", 3)
	vbox.add_child(stats_v)

	var stat_defs: Array = [
		["HP",     info["hp"]],
		["MP",     info["mp"]],
		["Attack", info["atk"]],
		["Magic",  info["mag"]],
		["Crit",   info["crit"]],
	]
	for sd: Array in stat_defs:
		stats_v.add_child(_make_stat_row(sd[0], sd[1], col))

	# divider 2
	var div2 := ColorRect.new()
	div2.color = col * 0.4
	div2.custom_minimum_size = Vector2(w - 20, 1)
	vbox.add_child(div2)

	# flavor text
	var flavor := Label.new()
	flavor.text = info["flavor"]
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor.add_theme_font_size_override("font_size", 12)
	flavor.add_theme_color_override("font_color", Color(0.75, 0.75, 0.70))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size = Vector2(w - 24, 48)
	vbox.add_child(flavor)

	# select button
	var btn := Button.new()
	btn.text = "SELECT"
	btn.custom_minimum_size = Vector2(w - 24, 40)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", col)

	var sbn := StyleBoxFlat.new()
	sbn.bg_color    = Color(0.06, 0.06, 0.14)
	sbn.border_width_left = 2; sbn.border_width_right  = 2
	sbn.border_width_top  = 2; sbn.border_width_bottom = 2
	sbn.border_color = col * 0.65
	sbn.corner_radius_top_left    = 4; sbn.corner_radius_top_right    = 4
	sbn.corner_radius_bottom_left = 4; sbn.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", sbn)

	var sbh := StyleBoxFlat.new()
	sbh.bg_color    = col * 0.22
	sbh.border_width_left = 2; sbh.border_width_right  = 2
	sbh.border_width_top  = 2; sbh.border_width_bottom = 2
	sbh.border_color = col
	sbh.corner_radius_top_left    = 4; sbh.corner_radius_top_right    = 4
	sbh.corner_radius_bottom_left = 4; sbh.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("hover",   sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	vbox.add_child(btn)

	btn.pressed.connect(func() -> void: _start(cls))

	# hover highlights the whole card
	btn.mouse_entered.connect(func() -> void: _set_card_style(panel, col, true))
	btn.mouse_exited.connect( func() -> void: _set_card_style(panel, col, false))

	return card

func _make_stat_row(label: String, stars: int, col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = "%-6s" % label
	lbl.custom_minimum_size = Vector2(60, 18)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.65))
	row.add_child(lbl)

	var star_lbl := Label.new()
	star_lbl.text = ""
	for i in range(5):
		star_lbl.text += "★" if i < stars else "☆"
	star_lbl.add_theme_font_size_override("font_size", 13)
	star_lbl.add_theme_color_override("font_color", col)
	row.add_child(star_lbl)

	return row

func _set_card_style(panel: PanelContainer, col: Color, hovered: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color  = Color(0.07, 0.06, 0.14, 0.95) if not hovered else Color(0.12, 0.10, 0.22, 0.97)
	sb.border_width_left   = 2; sb.border_width_right  = 2
	sb.border_width_top    = 2; sb.border_width_bottom = 2
	sb.border_color = col if hovered else col * 0.45
	sb.corner_radius_top_left    = 6; sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_left = 6; sb.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", sb)

func _start(cls: String) -> void:
	GameManager.start_new_game(cls, 42)
	get_tree().change_scene_to_file("res://scenes/dungeon.tscn")

# ── dungeon background ────────────────────────────────────────────────────────
func _draw() -> void:
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y

	var steps: int = 40
	for i in range(steps):
		var t: float   = float(i) / float(steps)
		var col: Color = C_BG_TOP.lerp(C_BG_BOT, t)
		var y0: float  = t * vh * 0.62
		var y1: float  = (t + 1.0 / float(steps)) * vh * 0.62
		draw_rect(Rect2(0, y0, vw, y1 - y0 + 1), col)

	draw_rect(Rect2(0, vh * 0.62, vw, vh * 0.38), C_FLOOR)

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


# ═════════════════════════════════════════════════════════════════════════════
# Inner class: weapon sprite for class cards
# ═════════════════════════════════════════════════════════════════════════════
class _WeaponSprite extends Node2D:
	var weapon_class: String = "warrior"

	func _draw() -> void:
		match weapon_class:
			"warrior": _draw_sword()
			"mage":    _draw_staff()
			"thief":   _draw_dagger()

	func _draw_sword() -> void:
		# blade
		var blade := PackedVector2Array([
			Vector2(-7, -80), Vector2(7, -80),
			Vector2(5, 20),   Vector2(-5, 20)
		])
		draw_colored_polygon(blade, Color(0.82, 0.85, 0.90))
		# fuller groove
		draw_line(Vector2(0, -76), Vector2(0, 16), Color(0.55, 0.60, 0.68), 2.0)
		# tip
		var tip := PackedVector2Array([
			Vector2(-7, -80), Vector2(7, -80), Vector2(0, -100)
		])
		draw_colored_polygon(tip, Color(0.88, 0.90, 0.95))
		# crossguard
		var guard := PackedVector2Array([
			Vector2(-28, 18), Vector2(28, 18),
			Vector2(24, 30),  Vector2(-24, 30)
		])
		draw_colored_polygon(guard, Color(0.82, 0.70, 0.20))
		# handle
		var handle := PackedVector2Array([
			Vector2(-6, 30), Vector2(6, 30),
			Vector2(5, 72),  Vector2(-5, 72)
		])
		draw_colored_polygon(handle, Color(0.25, 0.14, 0.10))
		for i in range(4):
			var gy: float = 36.0 + i * 10.0
			draw_line(Vector2(-5, gy), Vector2(5, gy), Color(0.40, 0.22, 0.15), 1.5)
		# pommel
		draw_circle(Vector2(0, 76), 8, Color(0.82, 0.70, 0.20))

	func _draw_staff() -> void:
		# pole — shorter so orb stays inside the card
		var pole := PackedVector2Array([
			Vector2(-5, -55), Vector2(5, -55),
			Vector2(7, 70),   Vector2(-7, 70)
		])
		draw_colored_polygon(pole, Color(0.40, 0.28, 0.16))
		# grain lines
		for i in range(5):
			var ly: float = -48.0 + i * 24.0
			draw_line(Vector2(-5, ly), Vector2(5, ly + 7), Color(0.28, 0.18, 0.10), 1.0)
		# gold bands
		for gy: float in [-30.0, 10.0, 50.0]:
			draw_rect(Rect2(-7, gy - 4, 14, 8), Color(0.82, 0.70, 0.20))
		# orb layers — compact, sits just above pole top
		draw_circle(Vector2(0, -68), 15, Color(0.18, 0.08, 0.30))
		draw_circle(Vector2(0, -68), 11, Color(0.42, 0.18, 0.72))
		draw_circle(Vector2(0, -68),  7, Color(0.58, 0.30, 0.92))
		draw_circle(Vector2(0, -68),  4, Color(0.78, 0.55, 1.00))
		draw_circle(Vector2(-4, -73), 3, Color(1.00, 0.90, 1.00, 0.60))

	func _draw_dagger() -> void:
		# blade
		var blade := PackedVector2Array([
			Vector2(-5, -60), Vector2(5, -60),
			Vector2(3, 14),   Vector2(-3, 14)
		])
		draw_colored_polygon(blade, Color(0.80, 0.83, 0.90))
		# edge glint
		draw_line(Vector2(-5, -58), Vector2(-3, 12), Color(0.95, 0.97, 1.00), 1.5)
		# tip
		var tip := PackedVector2Array([
			Vector2(-5, -60), Vector2(5, -60), Vector2(0, -76)
		])
		draw_colored_polygon(tip, Color(0.88, 0.90, 0.96))
		# crossguard (swept)
		var guard := PackedVector2Array([
			Vector2(-22, 12), Vector2(22, 12),
			Vector2(16, 22),  Vector2(-16, 22)
		])
		draw_colored_polygon(guard, Color(0.50, 0.52, 0.56))
		# handle
		var handle := PackedVector2Array([
			Vector2(-5, 22), Vector2(5, 22),
			Vector2(4, 54),  Vector2(-4, 54)
		])
		draw_colored_polygon(handle, Color(0.28, 0.14, 0.30))
		for i in range(3):
			var gy: float = 28.0 + i * 10.0
			draw_line(Vector2(-4, gy), Vector2(4, gy), Color(0.42, 0.22, 0.46), 1.5)
		# pommel
		draw_circle(Vector2(0, 58), 6, Color(0.52, 0.54, 0.58))
