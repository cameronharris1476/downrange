extends RefCounted
class_name TexLib

const ROOT := "res://assets/third_party/polyhaven/textures/"
var shader: Shader
var _sets := {}
var log_lines: PackedStringArray = PackedStringArray()


func setup(surface_shader: Shader) -> void:
	shader = surface_shader


func material(id: String, metallic: float, tint: Color = Color.WHITE) -> ShaderMaterial:
	var set: Dictionary = _texture_set(id)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex", set["albedo"])
	mat.set_shader_parameter("normal_tex", set["normal"])
	mat.set_shader_parameter("rough_tex", set["rough"])
	mat.set_shader_parameter("metallic", metallic)
	mat.set_shader_parameter("tint", tint)
	return mat


func _texture_set(id: String) -> Dictionary:
	if _sets.has(id):
		return _sets[id]
	var albedo := _image("%s%s_diff_2k.jpg" % [ROOT, id], true)
	var normal := _image("%s%s_nor_2k.jpg" % [ROOT, id], false)
	var rough := _image("%s%s_rough_2k.jpg" % [ROOT, id], false)
	var packed := {"albedo": albedo, "normal": normal, "rough": rough}
	_sets[id] = packed
	return packed


func _image(path: String, albedo: bool) -> Texture2D:
	var absolute := ProjectSettings.globalize_path(path)
	var image := Image.new()
	var err := image.load(absolute)
	if err != OK:
		log_lines.append("texture load failed %s (%s)" % [path, err])
		image = Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color(0.4, 0.4, 0.4) if albedo else Color(0.5, 0.5, 1.0))
	if albedo:
		if image.get_format() != Image.FORMAT_RGB8 and image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		image.srgb_to_linear()
		log_lines.append("albedo %s sample %s" % [path.get_file(), image.get_pixel(image.get_width() / 2, image.get_height() / 2)])
	image.generate_mipmaps()
	var compressed := image.duplicate()
	var cerr: Error = compressed.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC)
	if cerr == OK:
		image = compressed
	else:
		log_lines.append("compress skipped %s (%s)" % [path.get_file(), cerr])
	return ImageTexture.create_from_image(image)
