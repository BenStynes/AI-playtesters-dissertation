class_name DungeonGenerator
extends RefCounted

const GRID_W: int = 56
const GRID_H: int = 56

enum Tile {
	WALL        = 0,
	FLOOR       = 1,
	ENTRANCE    = 2,
	BOSS        = 3,
	CHEST       = 4,
	HEAL        = 5,
	TRAP        = 6,
	SECRET_DOOR = 7
}

# Returns: { "map": Array, "entrance": Vector2i, "boss": Vector2i,
#             "width": int, "height": int }
static func generate(floor_num: int = 1, seed_value: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var map: Array = []
	for _y in range(GRID_H):
		var row: Array = []
		row.resize(GRID_W)
		row.fill(Tile.WALL)
		map.append(row)

	var rooms: Array = []
	var target: int = clampi(8 + floor_num, 10, 16)
	var attempts: int = 0

	while rooms.size() < target and attempts < 500:
		attempts += 1
		var w: int = rng.randi_range(4, 9)
		var h: int = rng.randi_range(4, 9)
		var rx: int = rng.randi_range(1, GRID_W - w - 1)
		var ry: int = rng.randi_range(1, GRID_H - h - 1)
		var new_room := Rect2i(rx, ry, w, h)

		var overlaps: bool = false
		for room: Rect2i in rooms:
			if room.grow(2).intersects(new_room):
				overlaps = true
				break
		if overlaps:
			continue

		rooms.append(new_room)
		for cy in range(ry, ry + h):
			for cx in range(rx, rx + w):
				map[cy][cx] = Tile.FLOOR

	# Connect rooms sequentially with L-shaped corridors
	for i in range(rooms.size() - 1):
		var a: Rect2i = rooms[i]
		var b: Rect2i = rooms[i + 1]
		var ax: int = a.position.x + a.size.x / 2
		var ay: int = a.position.y + a.size.y / 2
		var bx: int = b.position.x + b.size.x / 2
		var by_: int = b.position.y + b.size.y / 2
		_carve_corridor(map, ax, ay, bx, by_)

	# Special tiles
	var entrance_pos: Vector2i = _room_center(rooms[0])
	map[entrance_pos.y][entrance_pos.x] = Tile.ENTRANCE

	var boss_pos: Vector2i = _room_center(rooms[rooms.size() - 1])
	map[boss_pos.y][boss_pos.x] = Tile.BOSS

	# Chests in middle rooms
	for i in range(1, rooms.size() - 1):
		if rng.randi() % 2 == 0:
			var cp: Vector2i = _room_center(rooms[i])
			if map[cp.y][cp.x] == Tile.FLOOR:
				map[cp.y][cp.x] = Tile.CHEST

	# Heal spots — guarantee one per 2 middle rooms
	for i in range(1, rooms.size() - 1):
		if i % 2 == 0 or rng.randi() % 2 == 0:
			var hp_pos: Vector2i = _random_floor(map, rooms[i], rng)
			if hp_pos != Vector2i(-1, -1):
				map[hp_pos.y][hp_pos.x] = Tile.HEAL

	# Trap tiles — placed AFTER heals so they don't overwrite them
	var trap_count: int = 4 + floor_num
	var placed: int = 0
	var tattempts: int = 0
	while placed < trap_count and tattempts < 500:
		tattempts += 1
		var tx: int = rng.randi_range(1, GRID_W - 2)
		var ty: int = rng.randi_range(1, GRID_H - 2)
		if map[ty][tx] == Tile.FLOOR:   # only FLOOR, not HEAL
			map[ty][tx] = Tile.TRAP
			placed += 1

	# Secret doors — 2-3 placed on walls adjacent to middle rooms
	var secret_count: int = rng.randi_range(2, 3)
	var srooms: Array = rooms.slice(1, rooms.size() - 1)
	for i in range(srooms.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = srooms[i]
		srooms[i] = srooms[j]
		srooms[j] = temp
	var secrets_placed: int = 0
	for sr: Rect2i in srooms:
		if secrets_placed >= secret_count: break
		# Try all four sides of the room
		var candidates: Array = [
			Vector2i(sr.position.x - 1,               sr.position.y + sr.size.y / 2),
			Vector2i(sr.position.x + sr.size.x,       sr.position.y + sr.size.y / 2),
			Vector2i(sr.position.x + sr.size.x / 2,   sr.position.y - 1),
			Vector2i(sr.position.x + sr.size.x / 2,   sr.position.y + sr.size.y),
		]
		for c: Vector2i in candidates:
			if c.x >= 1 and c.x < GRID_W - 1 and c.y >= 1 and c.y < GRID_H - 1:
				if map[c.y][c.x] == Tile.WALL:
					map[c.y][c.x] = Tile.SECRET_DOOR
					secrets_placed += 1
					break

	return {
		"map":      map,
		"entrance": entrance_pos,
		"boss":     boss_pos,
		"width":    GRID_W,
		"height":   GRID_H
	}

static func _room_center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)

static func _random_floor(map: Array, room: Rect2i, rng: RandomNumberGenerator) -> Vector2i:
	for _a in range(20):
		var x: int = rng.randi_range(room.position.x, room.position.x + room.size.x - 1)
		var y: int = rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
		if map[y][x] == Tile.FLOOR:
			return Vector2i(x, y)
	return Vector2i(-1, -1)

static func _carve_corridor(map: Array, x1: int, y1: int, x2: int, y2: int) -> void:
	var cx: int = x1
	var cy: int = y1
	# Horizontal leg — 2 tiles tall so corridors feel walkable
	while cx != x2:
		for dy in [-1, 0]:
			var wy: int = cy + dy
			if cx >= 0 and cx < GRID_W and wy >= 0 and wy < GRID_H:
				if map[wy][cx] == Tile.WALL:
					map[wy][cx] = Tile.FLOOR
		cx += 1 if x2 > cx else -1
	# Vertical leg — 2 tiles wide
	while cy != y2:
		for dx in [0, 1]:
			var wx: int = cx + dx
			if wx >= 0 and wx < GRID_W and cy >= 0 and cy < GRID_H:
				if map[cy][wx] == Tile.WALL:
					map[cy][wx] = Tile.FLOOR
		cy += 1 if y2 > cy else -1
	if cx >= 0 and cx < GRID_W and cy >= 0 and cy < GRID_H:
		map[cy][cx] = Tile.FLOOR
