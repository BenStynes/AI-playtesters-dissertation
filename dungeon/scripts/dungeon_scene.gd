extends Node2D

# ── Directions: N E S W ───────────────────────────────────────────────────────
const DIRS:      Array = [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]
const DIR_NAMES: Array = ["North", "East", "South", "West"]

# ── Map state ─────────────────────────────────────────────────────────────────
var _map:     Array      = []
var _pos:     Vector2i   = Vector2i(0, 0)
var _facing:  int        = 0   # 0=N 1=E 2=S 3=W
var _visited: Dictionary = {}
var _steps:   int        = 0
var _blocked: bool       = false

# ── Atmosphere ────────────────────────────────────────────────────────────────
var _bob_y:   float = 0.0   # vertical camera bob
var _bob_vel: float = 0.0
var _flicker: float = 0.0   # torch brightness variation

# ── HUD refs ──────────────────────────────────────────────────────────────────
var _lbl_hp:   Label
var _lbl_mp:   Label
var _lbl_info: Label
var _lbl_face: Label
var _lbl_tile: Label
var _lbl_msg:  Label
var _msg_timer: float = 0.0

# ── Layout ────────────────────────────────────────────────────────────────────
# Left VIEW_RATIO of screen = first-person 3D view
# Right (1-VIEW_RATIO) = stats panel + minimap
const VIEW_RATIO: float = 0.70

# ── Perspective depth slices ──────────────────────────────────────────────────
# Each row: [xl, xr, yt, yb] as fraction of the 3D view rect.
# Defines the inner edges of the corridor opening at each depth.
# depth 0 = screen boundary, depth 1 = nearest, depth 3 = farthest visible
const DF: Array = [
	[0.00, 1.00, 0.00, 1.00],   # 0  screen edge
	[0.20, 0.80, 0.14, 0.86],   # 1  nearest walls
	[0.34, 0.66, 0.27, 0.73],   # 2  mid distance
	[0.44, 0.56, 0.37, 0.63],   # 3  far
	[0.49, 0.51, 0.44, 0.56],   # 4  vanishing point
]

# Wall colours (front face), indexed by depth
const WALL_COL: Array = [
	Color(0,0,0),                       # 0 unused
	Color(0.48, 0.45, 0.41),            # 1 nearest – lightest
	Color(0.32, 0.30, 0.27),            # 2
	Color(0.20, 0.18, 0.16),            # 3 farthest – darkest
]
const SIDE_DIM:    float = 0.65   # side walls are this fraction of front brightness
const COLOR_CEIL:  Color = Color(0.07, 0.07, 0.11)
const COLOR_FLOOR: Color = Color(0.16, 0.12, 0.08)

# Special-tile tints applied to front walls at depth 1
const TILE_TINTS: Dictionary = {
	DungeonGenerator.Tile.BOSS:        Color(0.70, 0.05, 0.05),
	DungeonGenerator.Tile.CHEST:       Color(0.70, 0.60, 0.05),
	DungeonGenerator.Tile.HEAL:        Color(0.05, 0.35, 0.70),
	DungeonGenerator.Tile.ENTRANCE:    Color(0.05, 0.60, 0.10),
	DungeonGenerator.Tile.TRAP:        Color(0.65, 0.30, 0.00),
	DungeonGenerator.Tile.SECRET_DOOR: Color(0.45, 0.15, 0.60),
}

# Minimap
const MM_TILE: int = 6   # pixels per tile on minimap

# ── Procedural textures ───────────────────────────────────────────────────────
var _tex_wall:  ImageTexture   # brick pattern
var _tex_floor: ImageTexture   # stone slab
var _tex_ceil:  ImageTexture   # rough ceiling stone

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	print("Generating with seed: ", GameManager.rng.seed)
	if GameManager.dungeon_map.size() > 0:
		_map     = GameManager.dungeon_map
		_pos     = GameManager.player_grid_pos
		_facing  = GameManager.player_facing
		_visited = GameManager.visited_tiles
	else:
		var d := DungeonGenerator.generate(GameManager.current_floor, GameManager.rng.seed)
		_map     = d["map"]
		_pos     = d["entrance"]
		GameManager.dungeon_map = _map

	_create_textures()
	_mark_visited(_pos)
	_build_hud()
	_update_hud()
	
	if  AiBridge.ai_enabled:
		var timer := Timer.new()
		timer.wait_time =0.3
		timer.one_shot = false
		timer.timeout.connect(_do_ai_turn)
		add_child(timer)
		timer.start()

# ── Texture generation ────────────────────────────────────────────────────────
func _create_textures() -> void:
	_tex_wall  = _make_brick_tex()
	_tex_floor = _make_floor_tex()
	_tex_ceil  = _make_ceil_tex()

# Brick wall: alternating offset rows, with mortar lines
func _make_brick_tex() -> ImageTexture:
	var sz := 128
	var bh := 16    # brick height in px
	var bw := 32    # brick width in px
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	for y in range(sz):
		for x in range(sz):
			var row: int   = y / bh
			var offset: int = (bw / 2) * (row % 2)
			var bx: int    = (x + offset) % bw
			var by_: int   = y % bh
			var is_mortar: bool = (by_ < 2) or (bx < 2)
			if is_mortar:
				img.set_pixel(x, y, Color(0.18, 0.15, 0.12))
			else:
				# Deterministic per-brick shade variation using position hash
				var brick_id: int = (row * 7 + (x + offset) / bw)
				var v: float = 0.82 + sin(brick_id * 3.7) * 0.06 \
							 + sin(float(bx) * 0.18 + float(by_) * 0.22) * 0.03
				img.set_pixel(x, y, Color(v, v * 0.94, v * 0.84))
	return ImageTexture.create_from_image(img)

# Stone floor: staggered rectangular slabs with 1-px seams (same logic as brick, larger scale)
func _make_floor_tex() -> ImageTexture:
	var sz    := 128
	var tw    := 42   # slab width
	var th    := 26   # slab height
	var img   := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	for y in range(sz):
		for x in range(sz):
			var row: int    = y / th
			var offset: int = (tw / 2) * (row % 2)   # stagger every other row
			var tx: int     = (x + offset) % tw
			var ty_: int    = y % th
			if tx == 0 or ty_ == 0:
				# 1-px seam — dark grout
				img.set_pixel(x, y, Color(0.09, 0.07, 0.05))
			else:
				# Per-slab colour shift + subtle surface noise
				var slab_id: int = row * 11 + (x + offset) / tw
				var base: float  = 0.42 + sin(float(slab_id) * 3.1) * 0.05
				var surf: float  = sin(float(x) * 0.31 + float(y) * 0.23) * 0.025
				# Slight centre-highlight (bevel feel)
				var ex: float = float(tx) / float(tw)
				var ey: float = float(ty_) / float(th)
				var bevel: float = minf(minf(ex, 1.0 - ex), minf(ey, 1.0 - ey)) * 0.15
				var v: float = base + surf + bevel
				img.set_pixel(x, y, Color(v * 0.74, v * 0.57, v * 0.38))
	return ImageTexture.create_from_image(img)

# Ceiling: dark uniform stone — high-frequency noise so no stripes or grid show up
func _make_ceil_tex() -> ImageTexture:
	var sz  := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	for y in range(sz):
		for x in range(sz):
			var fx := float(x)
			var fy := float(y)
			# High-frequency sines look like grain/noise rather than visible stripes
			var v: float = 0.22 \
				+ sin(fx * 2.3  + fy * 3.7)  * 0.018 \
				+ sin(fx * 5.1  - fy * 2.9)  * 0.012 \
				+ sin(fx * 1.7  + fy * 6.3)  * 0.010 \
				+ sin(fx * 4.3  - fy * 5.1)  * 0.008
			img.set_pixel(x, y, Color(v * 0.60, v * 0.60, v * 0.85))
	return ImageTexture.create_from_image(img)

# ── HUD (right panel) ─────────────────────────────────────────────────────────
func _build_hud() -> void:
	var vp: Vector2  = get_viewport().size
	var hx: float    = vp.x * VIEW_RATIO + 4   # HUD left edge
	var hw: float    = vp.x * (1.0 - VIEW_RATIO) - 8

	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Stats
	var sp := PanelContainer.new()
	sp.position = Vector2(hx, 6)
	sp.custom_minimum_size = Vector2(hw, 110)
	canvas.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	_lbl_hp   = _mk_lbl(sv, "", 13)
	_lbl_mp   = _mk_lbl(sv, "", 13)
	_lbl_info = _mk_lbl(sv, "", 11)
	_lbl_face = _mk_lbl(sv, "", 11)

	# Tile description
	var tp := PanelContainer.new()
	tp.position = Vector2(hx, 124)
	tp.custom_minimum_size = Vector2(hw, 44)
	canvas.add_child(tp)
	_lbl_tile = Label.new()
	_lbl_tile.add_theme_font_size_override("font_size", 10)
	_lbl_tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tp.add_child(_lbl_tile)

	# Controls
	var cp := PanelContainer.new()
	cp.position = Vector2(hx, vp.y - 90)
	cp.custom_minimum_size = Vector2(hw, 84)
	canvas.add_child(cp)
	var cl := Label.new()
	cl.text = "W/↑  Forward\nS/↓  Back\nA/←  Turn L\nD/→  Turn R\nE    Interact"
	cl.add_theme_font_size_override("font_size", 10)
	cp.add_child(cl)

	# Floating message (centred in 3D view area)
	_lbl_msg = Label.new()
	_lbl_msg.position = Vector2(10, 10)
	_lbl_msg.custom_minimum_size = Vector2(vp.x * VIEW_RATIO - 20, 32)
	_lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_msg.add_theme_font_size_override("font_size", 15)
	_lbl_msg.add_theme_color_override("font_color", Color(1, 1, 0.2))
	_lbl_msg.visible = false
	canvas.add_child(_lbl_msg)

func _mk_lbl(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func _update_hud() -> void:
	var p: PlayerData = GameManager.player
	_lbl_hp.text   = "HP: %d / %d" % [p.hp, p.max_hp]
	_lbl_mp.text   = "MP: %d / %d" % [p.mp, p.max_mp]
	_lbl_info.text = "Floor %d  Lv %d  G:%d" % [GameManager.current_floor, p.level, p.gold]
	_lbl_face.text = "Facing: %s  [%s]" % [DIR_NAMES[_facing], p.player_class.capitalize()]

	match _map[_pos.y][_pos.x]:
		DungeonGenerator.Tile.ENTRANCE:    _lbl_tile.text = "Entrance  [E] Leave"
		DungeonGenerator.Tile.BOSS:        _lbl_tile.text = "!! BOSS TILE !!"
		DungeonGenerator.Tile.CHEST:       _lbl_tile.text = "Chest  [E] Open"
		DungeonGenerator.Tile.HEAL:        _lbl_tile.text = "Healing Spring  [E]"
		DungeonGenerator.Tile.TRAP:        _lbl_tile.text = "!! Trap — you took damage !!"
		DungeonGenerator.Tile.SECRET_DOOR: _lbl_tile.text = "Secret Door  [E]"
		_:                                 _lbl_tile.text = ""

# ── Render ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_lbl_msg.visible = false

	# Step bob — spring physics
	var spring: float = (0.0 - _bob_y) * 38.0
	var damping: float = _bob_vel * -8.5
	_bob_vel += (spring + damping) * delta
	_bob_y   += _bob_vel * delta

	# Torch flicker — two overlapping sine waves
	var t: float = Time.get_ticks_msec() * 0.001
	_flicker = sin(t * 2.3) * 0.022 + sin(t * 5.7) * 0.012

	queue_redraw()

func _draw() -> void:
	var vp: Vector2  = get_viewport().size
	var vw: float    = vp.x * VIEW_RATIO
	var vh: float    = vp.y

	# ── Apply step-bob to the 3-D view only ──────────────────────────────
	draw_set_transform(Vector2(0, _bob_y))

	# ── 3-D view background (textured ceiling + floor) ───────────────────
	draw_texture_rect(_tex_ceil,  Rect2(0, 0,        vw, vh * 0.5), true)
	draw_texture_rect(_tex_floor, Rect2(0, vh * 0.5, vw, vh * 0.5), true)

	# ── First-person walls (back → front) ─────────────────────────────────
	var fd: Vector2i = DIRS[_facing]
	var ld: Vector2i = DIRS[(_facing + 3) % 4]
	var rd: Vector2i = DIRS[(_facing + 1) % 4]

	for depth in range(3, 0, -1):
		var outer: Array = DF[depth - 1]
		var inner: Array = DF[depth]

		var p_f: Vector2i = _pos + fd * depth
		var p_l: Vector2i = p_f  + ld
		var p_r: Vector2i = p_f  + rd

		var wf: bool = _is_solid(p_f)
		var wl: bool = _is_solid(p_l)
		var wr: bool = _is_solid(p_r)

		var col_front: Color = WALL_COL[depth] * (1.0 + _flicker)
		var col_side:  Color = col_front * SIDE_DIM

		# Left side wall face — textured brick, side-dimmed
		if wl:
			_trect(outer[0]*vw, outer[2]*vh,
				   (inner[0]-outer[0])*vw, (outer[3]-outer[2])*vh, col_side)

		# Right side wall face — textured brick, side-dimmed
		if wr:
			_trect(inner[1]*vw, outer[2]*vh,
				   (outer[1]-inner[1])*vw, (outer[3]-outer[2])*vh, col_side)

		# Front wall face — textured brick, with special-tile tint at depth 1
		if wf:
			var fc: Color = col_front
			if depth == 1 and not _is_oob(p_f):
				var t: int = _map[p_f.y][p_f.x]
				if TILE_TINTS.has(t):
					fc = col_front.lerp(TILE_TINTS[t], 0.55)
			_trect(inner[0]*vw, inner[2]*vh,
				   (inner[1]-inner[0])*vw, (inner[3]-inner[2])*vh, fc)

	# Thin outline grid for the corridor frame (gives crisp dungeon-crawler feel)
	for depth in range(1, 4):
		var f: Array = DF[depth]
		var col: Color = Color(0.0, 0.0, 0.0, 0.35 - depth * 0.05)
		draw_rect(Rect2(f[0]*vw, f[2]*vh, (f[1]-f[0])*vw, (f[3]-f[2])*vh), col, false, 1.5)

	# Tile text label for what's directly ahead (depth 1)
	var ahead: Vector2i = _pos + fd
	if not _is_oob(ahead):
		var t_ahead: int = _map[ahead.y][ahead.x]
		var label: String = ""
		match t_ahead:
			DungeonGenerator.Tile.BOSS:        label = "!! DEMON LORD !!"
			DungeonGenerator.Tile.CHEST:       label = "[ CHEST ]"
			DungeonGenerator.Tile.HEAL:        label = "+ Healing Spring +"
			DungeonGenerator.Tile.ENTRANCE:    label = "^ Entrance ^"
			DungeonGenerator.Tile.TRAP:        label = "^ TRAP ^"
			DungeonGenerator.Tile.SECRET_DOOR: label = "? Secret Door ?"
		if label != "":
			var font: Font = ThemeDB.fallback_font
			draw_string(font, Vector2(vw * 0.5 - 90, vh * 0.5 + 8),
					label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.6))

	# ── Player weapon (bottom-right of 3D view) ──────────────────────────
	_draw_weapon(vw, vh)

	# ── Reset transform — HUD never bobs ─────────────────────────────────
	draw_set_transform(Vector2.ZERO)

	# ── Divider line ──────────────────────────────────────────────────────
	draw_line(Vector2(vw, 0), Vector2(vw, vh), Color(0.25, 0.25, 0.35), 2)

	# ── Right panel background ────────────────────────────────────────────
	draw_rect(Rect2(vw, 0, vp.x - vw, vh), Color(0.05, 0.05, 0.08))

	# ── Minimap ───────────────────────────────────────────────────────────
	_draw_minimap(vp, vw)

# ── Weapon drawing ───────────────────────────────────────────────────────────
# Weapon appears in the lower-right of the 3D view, base below the screen edge,
# as if the player is holding it in their right hand.
func _draw_weapon(vw: float, vh: float) -> void:
	# Dark vignette at the bottom so the weapon blends into shadow naturally
	draw_rect(Rect2(0, vh * 0.72, vw, vh * 0.28), Color(0, 0, 0, 0.55))

	var bx: float  = vw * 0.72   # weapon base x — right of centre
	var by_: float = vh + 40.0   # base below screen (handle grip hidden)

	_draw_arm(vw, vh, bx, by_)

	match GameManager.player.player_class:
		"warrior": _draw_sword(bx, by_, vh)
		"mage":    _draw_staff(bx, by_, vh)
		"thief":   _draw_dagger(bx, by_, vh)

func _draw_arm(vw: float, vh: float, bx: float, by_: float) -> void:
	var skin:   Color = Color(0.72, 0.52, 0.36)
	var shadow: Color = Color(0.45, 0.30, 0.20)
	var sleeve: Color = Color(0.20, 0.14, 0.09)

	# Sleeve — large polygon from bottom-right corner up to the weapon grip area
	var grip_y: float = by_ - 72.0   # universal grip height
	var slv := PackedVector2Array([
		Vector2(vw,       vh),
		Vector2(vw * 0.78, vh),
		Vector2(bx - 18,  grip_y + 20),
		Vector2(bx + 32,  grip_y + 10),
		Vector2(vw,       vh * 0.80),
	])
	draw_colored_polygon(slv, sleeve)

	# Sleeve shadow edge
	draw_line(Vector2(vw * 0.78, vh), Vector2(bx - 18, grip_y + 20), Color(0.10, 0.07, 0.04), 2.5)

	# Wrist / back of hand
	var hand := PackedVector2Array([
		Vector2(bx + 30,  grip_y + 12),
		Vector2(bx - 16,  grip_y + 18),
		Vector2(bx - 20,  grip_y - 10),
		Vector2(bx + 24,  grip_y - 6),
	])
	draw_colored_polygon(hand, skin)

	# Knuckle shading
	draw_line(Vector2(bx - 20, grip_y - 10), Vector2(bx + 24, grip_y - 6), shadow, 2.0)

	# Thumb hint
	var thumb := PackedVector2Array([
		Vector2(bx - 16, grip_y + 18),
		Vector2(bx - 30, grip_y + 8),
		Vector2(bx - 26, grip_y - 4),
		Vector2(bx - 14, grip_y - 2),
	])
	draw_colored_polygon(thumb, skin)

func _draw_sword(bx: float, by_: float, vh: float) -> void:
	var blade_len: float = vh * 0.55
	var bw: float = 9.0
	var guard_y: float = by_ - 95.0

	# ── Blade ────────────────────────────────────────────────────────────
	var tip := Vector2(bx, by_ - blade_len)
	var blade := PackedVector2Array([
		Vector2(bx - bw,       guard_y),
		Vector2(bx + bw,       guard_y),
		Vector2(bx + bw * 0.25, tip.y + 10),
		tip,
		Vector2(bx - bw * 0.25, tip.y + 10),
	])
	draw_colored_polygon(blade, Color(0.78, 0.80, 0.90))
	# Edge highlight
	draw_line(Vector2(bx, guard_y), tip, Color(0.97, 0.97, 1.0, 0.7), 1.5)
	# Shadow side
	draw_line(Vector2(bx - bw, guard_y), Vector2(bx - bw * 0.2, tip.y + 10),
			Color(0.40, 0.40, 0.50), 1.5)

	# ── Crossguard ───────────────────────────────────────────────────────
	draw_rect(Rect2(bx - 38, guard_y - 9, 76, 18), Color(0.72, 0.58, 0.14))
	draw_rect(Rect2(bx - 36, guard_y - 7, 72, 14), Color(0.85, 0.70, 0.20))

	# ── Handle ───────────────────────────────────────────────────────────
	draw_rect(Rect2(bx - 7, guard_y + 9, 14, 75), Color(0.32, 0.16, 0.07))
	for i in range(6):
		draw_line(Vector2(bx - 8, guard_y + 16 + i * 11),
				  Vector2(bx + 8, guard_y + 16 + i * 11),
				  Color(0.18, 0.08, 0.03, 0.8), 2)

	# ── Pommel ───────────────────────────────────────────────────────────
	draw_circle(Vector2(bx, guard_y + 9 + 75 + 9), 13, Color(0.65, 0.52, 0.12))
	draw_circle(Vector2(bx, guard_y + 9 + 75 + 9), 8,  Color(0.85, 0.70, 0.20))

func _draw_staff(bx: float, by_: float, vh: float) -> void:
	var staff_len: float = vh * 0.65
	var top_y: float = by_ - staff_len

	# ── Pole (tapered) ───────────────────────────────────────────────────
	var pole := PackedVector2Array([
		Vector2(bx - 8, by_),
		Vector2(bx + 8, by_),
		Vector2(bx + 4, top_y + 30),
		Vector2(bx - 4, top_y + 30),
	])
	draw_colored_polygon(pole, Color(0.35, 0.22, 0.10))
	draw_line(Vector2(bx + 5, by_), Vector2(bx + 3, top_y + 30),
			Color(0.50, 0.35, 0.15), 2)  # highlight edge

	# ── Decorative bands ─────────────────────────────────────────────────
	for frac in [0.25, 0.55, 0.80]:
		var band_y: float = by_ - staff_len * frac
		draw_rect(Rect2(bx - 9, band_y - 4, 18, 8), Color(0.55, 0.42, 0.15))

	# ── Orb ──────────────────────────────────────────────────────────────
	var orb := Vector2(bx, top_y + 4)
	draw_circle(orb, 26, Color(0.12, 0.08, 0.35))   # outer glow ring
	draw_circle(orb, 21, Color(0.22, 0.12, 0.60))   # body
	draw_circle(orb, 14, Color(0.40, 0.22, 0.90))   # inner bright
	draw_circle(orb, 7,  Color(0.65, 0.50, 1.00))   # core
	# Specular highlight
	draw_circle(Vector2(orb.x - 6, orb.y - 6), 5, Color(0.90, 0.85, 1.0, 0.75))

func _draw_dagger(bx: float, by_: float, vh: float) -> void:
	var blade_len: float = vh * 0.30
	var bw: float = 8.0
	var guard_y: float = by_ - 65.0

	# ── Blade ────────────────────────────────────────────────────────────
	var tip := Vector2(bx, by_ - blade_len)
	var blade := PackedVector2Array([
		Vector2(bx - bw,       guard_y),
		Vector2(bx + bw,       guard_y),
		Vector2(bx + bw * 0.2, tip.y + 8),
		tip,
		Vector2(bx - bw * 0.2, tip.y + 8),
	])
	draw_colored_polygon(blade, Color(0.75, 0.77, 0.86))
	draw_line(Vector2(bx, guard_y), tip, Color(0.95, 0.95, 1.0, 0.7), 1.5)
	draw_line(Vector2(bx - bw, guard_y), Vector2(bx - bw * 0.15, tip.y + 8),
			Color(0.35, 0.35, 0.45), 1.5)

	# ── Guard ────────────────────────────────────────────────────────────
	draw_rect(Rect2(bx - 25, guard_y - 6, 50, 12), Color(0.45, 0.40, 0.38))
	draw_rect(Rect2(bx - 23, guard_y - 4, 46, 8),  Color(0.58, 0.52, 0.48))

	# ── Handle ───────────────────────────────────────────────────────────
	draw_rect(Rect2(bx - 6, guard_y + 6, 12, 50), Color(0.18, 0.12, 0.28))
	for i in range(4):
		draw_line(Vector2(bx - 7, guard_y + 12 + i * 11),
				  Vector2(bx + 7, guard_y + 12 + i * 11),
				  Color(0.10, 0.06, 0.18, 0.9), 2)

	# ── Pommel ───────────────────────────────────────────────────────────
	draw_circle(Vector2(bx, guard_y + 6 + 50 + 7), 9, Color(0.45, 0.40, 0.38))
	draw_circle(Vector2(bx, guard_y + 6 + 50 + 7), 5, Color(0.60, 0.55, 0.52))

func _rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	if w > 0 and h > 0:
		draw_rect(Rect2(x, y, w, h), col)

# Textured wall rect — tiles _tex_wall and modulates by col (depth shade / tint)
func _trect(x: float, y: float, w: float, h: float, col: Color) -> void:
	if w > 0 and h > 0:
		draw_texture_rect(_tex_wall, Rect2(x, y, w, h), true, col)

func _draw_minimap(vp: Vector2, vw: float) -> void:
	var gw: int = DungeonGenerator.GRID_W
	var gh: int = DungeonGenerator.GRID_H
	var mw: float = gw * MM_TILE
	var mh: float = gh * MM_TILE

	# Centre the minimap horizontally in the right panel
	var panel_w: float = vp.x - vw
	var ox: float = vw + (panel_w - mw) * 0.5
	var oy: float = 175.0   # below the stats panels

	# Minimap border
	draw_rect(Rect2(ox - 1, oy - 1, mw + 2, mh + 2), Color(0.3, 0.3, 0.4))
	# Dark fill for unseen areas
	draw_rect(Rect2(ox, oy, mw, mh), Color(0.03, 0.03, 0.05))

	for y in range(gh):
		for x in range(gw):
			var key := Vector2i(x, y)
			if not _visited.has(key): continue
			var col: Color = _mm_col(_map[y][x])
			draw_rect(Rect2(ox + x * MM_TILE, oy + y * MM_TILE,
					MM_TILE - 1, MM_TILE - 1), col)

	# Player marker (bright yellow)
	draw_rect(Rect2(ox + _pos.x * MM_TILE, oy + _pos.y * MM_TILE,
			MM_TILE - 1, MM_TILE - 1), Color(1, 1, 0))

	# Facing arrow on minimap (tiny)
	var fd: Vector2i = DIRS[_facing]
	var mx: float = ox + _pos.x * MM_TILE + MM_TILE * 0.5
	var my: float = oy + _pos.y * MM_TILE + MM_TILE * 0.5
	draw_line(Vector2(mx, my),
			Vector2(mx + fd.x * MM_TILE, my + fd.y * MM_TILE),
			Color(1, 0.5, 0), 1)

func _mm_col(tile: int) -> Color:
	match tile:
		DungeonGenerator.Tile.WALL:        return Color(0.10, 0.10, 0.14)
		DungeonGenerator.Tile.FLOOR:       return Color(0.22, 0.22, 0.30)
		DungeonGenerator.Tile.ENTRANCE:    return Color(0.10, 0.70, 0.10)
		DungeonGenerator.Tile.BOSS:        return Color(0.90, 0.08, 0.08)
		DungeonGenerator.Tile.CHEST:       return Color(0.90, 0.75, 0.08)
		DungeonGenerator.Tile.HEAL:        return Color(0.10, 0.40, 0.90)
		DungeonGenerator.Tile.TRAP:        return Color(0.80, 0.38, 0.00)
		DungeonGenerator.Tile.SECRET_DOOR: return Color(0.55, 0.15, 0.65)
	return Color(0.2, 0.2, 0.3)

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if AiBridge.ai_enabled: return
	if _blocked: return
	
	
	if not (event is InputEventKey and event.pressed): return
	var fd: Vector2i = DIRS[_facing]
	match event.keycode:
				KEY_W, KEY_UP:    _move(fd)
				KEY_S, KEY_DOWN:  _move(Vector2i(-fd.x, -fd.y))
				KEY_A, KEY_LEFT:  _turn(-1)
				KEY_D, KEY_RIGHT: _turn(1)
				KEY_E:            _interact()

func _do_ai_turn() -> void:
	AiBridge.write_exploration_state(_map,_pos,_facing)
	var action: String = AiBridge.read_action()
	
	var fd: Vector2i =DIRS[_facing]
	match  action:
		"move_forward": _move(fd)
		"move_backward": _move(Vector2i(-fd.x,-fd.y))
		"turn_left": _turn(-1)
		"turn_right": _turn(1)
		"interact": _interact()
		
	
func _move(dir: Vector2i) -> void:
	var np: Vector2i = _pos + dir
	if np.x < 0 or np.x >= DungeonGenerator.GRID_W: return
	if np.y < 0 or np.y >= DungeonGenerator.GRID_H: return
	if _map[np.y][np.x] == DungeonGenerator.Tile.WALL:
		_flash("Blocked.")
		return
	_pos = np
	_mark_visited(_pos)
	_steps += 1
	_bob_vel = -7.0   # kick upward → spring snaps back → walking feel
	_on_tile(_map[_pos.y][_pos.x])
	_update_hud()

func _turn(d: int) -> void:
	_facing = (_facing + d + 4) % 4
	GameManager.player_facing = _facing
	_update_hud()

func _on_tile(tile: int) -> void:
	match tile:
		DungeonGenerator.Tile.BOSS:
			_trigger_combat([EnemyData.EnemyType.DEMON], true)
			return
		DungeonGenerator.Tile.TRAP:
			var dmg: int = GameManager.rng.randi_range(5, 15)
			GameManager.player.take_damage(dmg, true)
			_flash("TRAP! Took %d spike damage!" % dmg)
			_update_hud()
			if GameManager.player.is_dead():
				_game_over()
				return

	if tile == DungeonGenerator.Tile.FLOOR or tile == DungeonGenerator.Tile.TRAP:
		# Require at least 4 steps before any encounter can fire
		if _steps >= 4 and GameManager.check_encounter(_steps):
			_random_combat()

func _interact() -> void:
	var tile: int = _map[_pos.y][_pos.x]
	match tile:
		DungeonGenerator.Tile.CHEST, DungeonGenerator.Tile.SECRET_DOOR:
			_open_chest(tile == DungeonGenerator.Tile.SECRET_DOOR)
		DungeonGenerator.Tile.HEAL:
			_use_heal()
		DungeonGenerator.Tile.ENTRANCE:
			_leave_dungeon()

func _open_chest(is_secret: bool) -> void:
	_map[_pos.y][_pos.x] = DungeonGenerator.Tile.FLOOR
	GameManager.dungeon_map = _map
	var p: PlayerData = GameManager.player
	var roll: int = 2 if is_secret else randi() % 3
	match roll:
		0:
			var g: int = randi_range(10, 30); p.gold += g
			_flash("Found %d gold!" % g)
		1:
			var h: int = int(p.max_hp * 0.25); p.heal(h)
			_flash("Potion! +%d HP" % h)
		2:
			match randi() % 3:
				0: p.attack      += 3; _flash("Ancient blade! ATK +3!")
				1: p.magic_power += 3; _flash("Spell tome! MGC +3!")
				2: p.max_hp += 10; p.heal(10); _flash("Amulet! Max HP +10!")
	_update_hud()

func _use_heal() -> void:
	var p: PlayerData = GameManager.player
	if p.hp >= p.max_hp and p.mp >= p.max_mp:
		_flash("Already at full HP and MP.")
		return
	var hp_amt: int = int(p.max_hp * 0.5)
	var mp_amt: int = int(p.max_mp * 0.4)
	p.heal(hp_amt)
	p.restore_mp(mp_amt)
	_flash("Spring restores %d HP and %d MP!" % [hp_amt, mp_amt])
	_update_hud()

func _random_combat() -> void:
	var fn: int = GameManager.current_floor
	# Weighted pool — slimes always; skeletons from floor 1 (rare); orcs from floor 2
	var pool: Array = [
		EnemyData.EnemyType.SLIME,
		EnemyData.EnemyType.SLIME,
		EnemyData.EnemyType.SKELETON,
		EnemyData.EnemyType.SKELETON,
		EnemyData.EnemyType.ORC,
	]


	var enemies: Array = []
	var count: int = GameManager.rng.randi_range(1, 2)
	for _i in range(count):
		enemies.append(pool[GameManager.rng.randi() % pool.size()])
	_trigger_combat(enemies, false)

func _trigger_combat(enemy_types: Array, is_boss: bool) -> void:
	_steps = 0   # reset so encounters don't pile up immediately after returning
	GameManager.pending_enemies = enemy_types
	GameManager.is_boss_fight   = is_boss
	GameManager.player_grid_pos = _pos
	GameManager.player_facing   = _facing
	GameManager.dungeon_map     = _map
	GameManager.visited_tiles   = _visited
	get_tree().change_scene_to_file("res://scenes/combat.tscn")

func _leave_dungeon() -> void:
	_blocked = true
	_flash("Leaving the dungeon…")
	AiBridge.write_game_over_state("fled")
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func _game_over() -> void:
	_blocked = true
	_flash("You have fallen…")
	AiBridge.write_game_over_state("died")
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func _mark_visited(pos: Vector2i) -> void:
	_visited[pos] = true
	var radius: int = 3
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius + 1: continue
			var target := Vector2i(pos.x + dx, pos.y + dy)
			if _is_oob(target): continue
			if _has_los(pos, target):
				_visited[target] = true
	GameManager.visited_tiles = _visited

func _has_los(from: Vector2i, to: Vector2i) -> bool:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	var steps: int = maxi(absi(dx), absi(dy))
	if steps == 0: return true
	for i in range(1, steps):
		var fx: float = from.x + float(dx) * float(i) / float(steps)
		var fy: float = from.y + float(dy) * float(i) / float(steps)
		var cx: int = roundi(fx)
		var cy: int = roundi(fy)
		if _is_oob(Vector2i(cx, cy)): return false
		if _map[cy][cx] == DungeonGenerator.Tile.WALL: return false
	return true

func _is_solid(pos: Vector2i) -> bool:
	return _is_oob(pos) or _map[pos.y][pos.x] == DungeonGenerator.Tile.WALL

func _is_oob(pos: Vector2i) -> bool:
	return pos.x < 0 or pos.x >= DungeonGenerator.GRID_W or \
		   pos.y < 0 or pos.y >= DungeonGenerator.GRID_H

func _flash(msg: String) -> void:
	_lbl_msg.text    = msg
	_lbl_msg.visible = true
	_msg_timer       = 2.5
