extends Node2D

# ─────────────────────────────────────────────
#  EXPLOSION.GD  –  Desktop Rebellion
# ─────────────────────────────────────────────

const LINE_EXTEND_DIST  := 55.0
const LINE_SHRINK_WIDTH := 0.08
const CIRCLE_SHRINK     := 0.15
const DURATION          := 0.38

var _lines         : Array   = []
var _line_origins  : Array   = []
var _line_ends     : Array   = []
var _line_widths   : Array   = []
var _circle        : Node    = null   # Node covers Panel, Node2D, anything
var _circle_scale  : Vector2 = Vector2.ONE
var _timer         : float   = 0.0
var _running       : bool    = false


func _ready() -> void:
	for child in get_children():
		if child is Line2D:
			_lines.append(child)
			_line_origins.append((child as Line2D).get_point_position(0))
			_line_ends.append((child as Line2D).get_point_position(1))
			_line_widths.append((child as Line2D).width)

	# Accept Panel, Polygon2D, MeshInstance2D — anything named Circle
	for child in get_children():
		if child.name == "Circle":
			_circle = child
			_circle_scale = child.scale
			break

	explode()


func explode() -> void:
	_timer     = 0.0
	_running   = true
	modulate.a = 1.0


func _process(delta: float) -> void:
	if not _running:
		return

	_timer += delta
	var t      : float = clampf(_timer / DURATION, 0.0, 1.0)
	var ease_t : float = 1.0 - pow(1.0 - t, 3.0)

	# Animate lines
	for i in _lines.size():
		var line   : Line2D  = _lines[i]
		var origin : Vector2 = _line_origins[i]
		var dir    : Vector2 = (_line_ends[i] - origin).normalized()
		line.set_point_position(0, origin)
		line.set_point_position(1, _line_ends[i] + dir * LINE_EXTEND_DIST * ease_t)
		line.width = lerpf(_line_widths[i], _line_widths[i] * LINE_SHRINK_WIDTH, ease_t)

	# Animate circle scale
	if _circle != null:
		_circle.scale = _circle_scale * lerpf(1.0, CIRCLE_SHRINK, ease_t)

	# Fade out last 30%
	if t > 0.7:
		modulate.a = lerpf(1.0, 0.0, (t - 0.7) / 0.3)

	if t >= 1.0:
		queue_free()
