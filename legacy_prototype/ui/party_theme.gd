class_name PartyTheme
extends RefCounted
## Builds the shared UI Theme from the Kenney UI pack: chunky font, glossy buttons,
## inked text.

const BTN := "res://assets/kenney_ui/PNG/%s/Default/button_rectangle_depth_gradient.png"

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func card_style(accent: Color, active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.25, 0.88) if not active else Color(0.2, 0.14, 0.45, 0.95)
	sb.set_corner_radius_all(18)
	sb.border_width_left = 10
	sb.border_color = accent
	sb.content_margin_left = 20
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = Toon.font()
	t.default_font_size = 22

	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", Toon.INK)
	t.set_constant("outline_size", "Label", 7)

	t.set_stylebox("normal", "Button", _btn("Blue", Color.WHITE))
	t.set_stylebox("hover", "Button", _btn("Blue", Color(1.18, 1.18, 1.18)))
	t.set_stylebox("pressed", "Button", _btn("Blue", Color(0.8, 0.8, 0.9)))
	t.set_stylebox("disabled", "Button", _btn("Grey", Color(0.85, 0.85, 0.85)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.55))
	t.set_color("font_outline_color", "Button", Toon.INK)
	t.set_constant("outline_size", "Button", 6)

	var le := StyleBoxFlat.new()
	le.bg_color = Color("f4f0ff")
	le.set_corner_radius_all(14)
	le.content_margin_left = 14
	le.content_margin_right = 14
	le.content_margin_top = 8
	le.content_margin_bottom = 8
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", Toon.INK)
	t.set_color("font_uneditable_color", "LineEdit", Color(0.35, 0.3, 0.5))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.35, 0.3, 0.5, 0.6))
	return t


static func _btn(color_name: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(BTN % color_name) as Texture2D
	sb.modulate_color = tint
	sb.texture_margin_left = 14
	sb.texture_margin_right = 14
	sb.texture_margin_top = 14
	sb.texture_margin_bottom = 18
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 10
	sb.content_margin_bottom = 14
	return sb
