extends CanvasLayer

# Two explicit area views of ONE live World3D. No scene copies, input handlers,
# position remapping, simulation, or additional physics worlds are created.
const L = preload("res://layout.gd")
const Models = preload("res://models.gd")
const DOCK_RECT := Rect2(18,140,864,430)
const YARD_RECT := Rect2(18,616,864,582)
const ROAD_RECT := Rect2(18,1290,864,132)
const ORDER := ["schakt","timmer","kyl","frys","adr","bransle"]
const INK := Color("f2f9ff")
const MUTED := Color("a7c6df")

var game: Node3D
var road_viewport: SubViewport
var road_camera: Camera3D
var road_texture: TextureRect
var road_heading: Label
var _road_frames: Array[Control] = []
var _follow_id := -1
var dock_viewport: SubViewport
var yard_viewport: SubViewport
var dock_camera: Camera3D
var yard_camera: Camera3D
var dock_texture: TextureRect
var yard_texture: TextureRect
var legend: Control
var _campaign := false
var _overview := false
var _configured := false
var _zoom := 1.0
var _pan_offset := Vector2.ZERO
var _yard_base_size := 10.0
var _yard_base_position := Vector3.ZERO
var _original_mask := 1048575

func setup(source: Node3D) -> void:
    if game != null:
        return
    game = source
    layer = 0
    name = "ReadableHarborAreas"
    var old_camera: Camera3D = game.get("camera")
    if old_camera != null and old_camera.cull_mask != 0:
        _original_mask = old_camera.cull_mask
    var background := ColorRect.new()
    background.name = "AreaBackground"
    background.color = Color("081c34")
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    background.size = Vector2(900,1440)
    add_child(background)
    _label("DEPÅ",Vector2(23,579),Vector2(400,31),24,true)
    # Looking from the east rotates geographic north toward screen right.
    # This is an orientation marker, never a suggested puzzle move.
    var compass := _label("MOT KAJERNA  →",Vector2(638,584),Vector2(239,27),20,false)
    compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    compass.modulate = Color("b8d7ec")
    dock_viewport = _viewport("LoadingViewport",DOCK_RECT)
    yard_viewport = _viewport("DepotViewport",YARD_RECT)
    dock_camera = _camera(dock_viewport,68.0,0.0)
    yard_camera = _camera(yard_viewport,80.0,PI*.5)
    dock_texture = _texture(dock_viewport,DOCK_RECT)
    yard_texture = _texture(yard_viewport,YARD_RECT)
    _label("LASTNING",Vector2(28,146),Vector2(190,31),20,true)
    road_viewport = _viewport("TrafficViewport",ROAD_RECT)
    road_camera = _camera(road_viewport,55.0,PI*.5)
    road_camera.size = 3.7
    road_texture = _texture(road_viewport,ROAD_RECT)
    _road_frames.append(road_texture)
    _road_frames.append(road_texture.get_meta("frame"))
    road_heading = _label("UTFART",Vector2(23,1263),Vector2(850,25),20,true)
    _road_frames.append(road_heading)
    _position_road_camera(Vector3(0,0,24.0))
    legend = Control.new()
    legend.name = "CargoRecognition"
    legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
    legend.position = Vector2(18,1208)
    legend.size = Vector2(864,52)
    add_child(legend)
    _fit_loading_camera()
    _refresh_visibility()

func configure(state: Dictionary) -> void:
    if game == null:
        return
    _configured = true
    _campaign = bool(state.get("campaign",false))
    var complete := Rect2i(0,0,L.WIDTH,L.HEIGHT)
    var config: Dictionary = state.get("config",{})
    var bounds: Rect2i = config.get("spawn_bounds",complete)
    bounds = bounds.intersection(complete)
    if not bounds.has_area():
        bounds = complete
    var area := Rect2(L.YARD_BOUNDS.position+Vector2(bounds.position)*L.CELL,Vector2(bounds.size)*L.CELL)
    # Small real margins retain roofs, wheels and gate edges without diluting
    # the compact first depot in an empty full-size parking lot.
    area = area.grow(.25)
    _fit_camera(yard_camera,area,1.8,YARD_RECT.size,80.0,PI*.5)
    _yard_base_position = yard_camera.position
    _yard_base_size = yard_camera.size
    _pan_offset = Vector2.ZERO
    _apply_yard_camera()
    var kinds: Array = []
    for kind in ORDER:
        if kind in config.get("types",ORDER): kinds.append(kind)
    _build_legend(kinds)
    _refresh_visibility()

func set_zoom(value: float) -> void:
    _zoom = clampf(value,1.0,1.9)
    if is_equal_approx(_zoom,1.0):
        _pan_offset = Vector2.ZERO
    _apply_yard_camera()

func pan(relative: Vector2) -> void:
    if is_overview() or _zoom <= 1.0 or yard_camera == null:
        return
    _pan_offset += Vector2(-relative.x,relative.y)*yard_camera.size/YARD_RECT.size.y
    var extent := Vector2(_yard_base_size*YARD_RECT.size.x/YARD_RECT.size.y,_yard_base_size)
    var allowance := extent*(1.0-1.0/_zoom)*.52
    _pan_offset.x = clampf(_pan_offset.x,-allowance.x,allowance.x)
    _pan_offset.y = clampf(_pan_offset.y,-allowance.y,allowance.y)
    _apply_yard_camera()

func screen_ray(screen: Vector2) -> Dictionary:
    if game == null:
        return {}
    if is_overview():
        return {"camera":game.get("camera"),"point":screen}
    if DOCK_RECT.has_point(screen):
        return {"camera":dock_camera,"point":(screen-DOCK_RECT.position)*Vector2(dock_viewport.size)/DOCK_RECT.size}
    if YARD_RECT.has_point(screen):
        return {"camera":yard_camera,"point":(screen-YARD_RECT.position)*Vector2(yard_viewport.size)/YARD_RECT.size}
    return {}

func project(worldpos: Vector3, section: String = "yard") -> Vector2:
    if game == null:
        return Vector2(-10000,-10000)
    if is_overview():
        var original: Camera3D = game.get("camera")
        return original.unproject_position(worldpos)
    var loading := section in ["dock","loading","lastning"]
    var camera: Camera3D = dock_camera if loading else yard_camera
    var area: Rect2 = DOCK_RECT if loading else YARD_RECT
    var viewport: SubViewport = dock_viewport if loading else yard_viewport
    return area.position+camera.unproject_position(worldpos)*area.size/Vector2(viewport.size)

func set_overview(value: bool) -> void:
    _overview = value
    _refresh_visibility()

func is_overview() -> bool:
    return (_overview and bool(game.get("test_mode"))) or not _campaign

func follow_traffic(nodes: Dictionary, moving: Dictionary) -> void:
    if road_camera == null: return
    var selected := -1
    # Keep the same physical actor while visible, avoiding camera jumps when
    # several trucks start together. The strip never invents a display truck.
    var candidates: Array = moving.keys()
    if _follow_id in candidates:
        candidates.erase(_follow_id)
        candidates.push_front(_follow_id)
    for id in candidates:
        if not nodes.has(id) or not is_instance_valid(nodes[id]): continue
        var actor: Node3D = nodes[id]
        var p := actor.global_position
        var on_yard := L.YARD_BOUNDS.grow(.35).has_point(Vector2(p.x,p.z))
        var on_dock := p.z < -4.5 and absf(p.x) < 8.2
        if on_yard or on_dock: continue
        selected = int(id)
        _position_road_camera(p)
        break
    _follow_id = selected
    road_heading.text = "PÅ VÄG" if selected >= 0 else "UTFART"
    if selected < 0: _position_road_camera(Vector3(0,0,24.0))

func _position_road_camera(target: Vector3) -> void:
    road_camera.position = target+Vector3.UP*.25+road_camera.basis.z*45.0


func _process(_delta: float) -> void:
    # Toasts can also appear while paused (for example an empty undo). Keep
    # the recognition row from showing through the same bottom context strip.
    if is_instance_valid(game):
        follow_traffic(game.get("truck_nodes"),game.get("moving_trucks"))
        var show_road := visible and not bool(game.get("test_mode"))
        for control in _road_frames: control.visible = show_road
        road_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_road else SubViewport.UPDATE_DISABLED
    if legend != null and is_instance_valid(game):
        var toast: Label = game.get("toast_label")
        var context: Label = game.get("status_label")
        legend.visible = (toast == null or not toast.visible) and (context == null or context.text.is_empty())

func _refresh_visibility() -> void:
    var active := _configured and _campaign and not is_overview()
    visible = active
    for viewport in [dock_viewport,yard_viewport]:
        if viewport != null:
            viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
    if is_instance_valid(game):
        var original: Camera3D = game.get("camera")
        if original != null:
            original.cull_mask = 0 if active else _original_mask

func _apply_yard_camera() -> void:
    if yard_camera == null:
        return
    yard_camera.size = _yard_base_size/_zoom
    yard_camera.position = _yard_base_position+yard_camera.basis.x*_pan_offset.x+yard_camera.basis.y*_pan_offset.y

func _viewport(label: String, area: Rect2) -> SubViewport:
    var viewport := SubViewport.new()
    viewport.name = label
    viewport.size = Vector2i(area.size)
    viewport.own_world_3d = false
    viewport.world_3d = game.get_world_3d()
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    # Standalone SubViewports receive no automatic input. Main routes root
    # events through screen_ray, using the one authoritative physics world.
    add_child(viewport)
    return viewport

func _camera(viewport: SubViewport, pitch: float, yaw: float) -> Camera3D:
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.near = .05
    camera.far = 160.0
    camera.rotation = Vector3(-deg_to_rad(pitch),yaw,0)
    camera.cull_mask = _original_mask
    viewport.add_child(camera)
    camera.current = true
    return camera

func _fit_camera(camera: Camera3D, area: Rect2, height: float, pixels: Vector2, pitch: float, yaw: float) -> void:
    camera.rotation = Vector3(-deg_to_rad(pitch),yaw,0)
    var center := Vector3(area.get_center().x,0,area.get_center().y)
    var axis_x: Vector3 = camera.basis.x
    var axis_y: Vector3 = camera.basis.y
    var minimum := Vector2(INF,INF)
    var maximum := Vector2(-INF,-INF)
    for x in [area.position.x,area.end.x]:
        for z in [area.position.y,area.end.y]:
            for y in [0.0,height]:
                var point := Vector3(x,y,z)-center
                var projected := Vector2(point.dot(axis_x),point.dot(axis_y))
                minimum = minimum.min(projected)
                maximum = maximum.max(projected)
    var diameter: Vector2 = maximum-minimum
    var offset: Vector2 = (minimum+maximum)*.5
    camera.size = maxf(diameter.y,diameter.x/(pixels.x/pixels.y))*1.035
    camera.position = center+camera.basis.z*60.0+axis_x*offset.x+axis_y*offset.y

func _fit_loading_camera() -> void:
    # Fit the actual belt and crane silhouette. An enclosing tall box assumed
    # a crane on every far belt corner and needlessly shrank every cargo mark.
    var axis_x: Vector3 = dock_camera.basis.x
    var axis_y: Vector3 = dock_camera.basis.y
    var minimum := Vector2(INF,INF)
    var maximum := Vector2(-INF,-INF)
    var points: Array[Vector3] = []
    for x in [-8.8,8.8]:
        for z in [-14.1,-7.9]:
            for y in [.9,2.1]: points.append(Vector3(x,y,z))
    for x in [-10.0,10.0]:
        for y in [.8,2.1]: points.append(Vector3(x,y,-11.0))
    for x in [-7.45,7.45]:
        for z in [-10.3,-4.1]: points.append(Vector3(x,0,z))
        for z in [-9.9,-4.9]: points.append(Vector3(x,3.6,z))
    for point in points:
        var projected := Vector2(point.dot(axis_x),point.dot(axis_y))
        minimum = minimum.min(projected)
        maximum = maximum.max(projected)
    var diameter := maximum-minimum
    var center := (minimum+maximum)*.5
    dock_camera.size = maxf(diameter.y,diameter.x/(DOCK_RECT.size.x/DOCK_RECT.size.y))*1.035
    dock_camera.position = dock_camera.basis.z*60.0+axis_x*center.x+axis_y*center.y

func _texture(viewport: SubViewport, area: Rect2) -> TextureRect:
    var frame := Panel.new()
    frame.position = area.position-Vector2(2,2)
    frame.size = area.size+Vector2(4,4)
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = Color("102f4d")
    style.border_color = Color("467ca5")
    style.set_border_width_all(2)
    style.shadow_color = Color(0,0,0,.28)
    style.shadow_size = 5
    frame.add_theme_stylebox_override("panel",style)
    add_child(frame)
    var texture := TextureRect.new()
    texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    texture.texture = viewport.get_texture()
    texture.stretch_mode = TextureRect.STRETCH_SCALE
    texture.position = area.position
    texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture.size = area.size
    texture.set_meta("frame",frame)
    add_child(texture)
    return texture

func _label(text: String, at: Vector2, dimensions: Vector2, size: int, bold: bool) -> Label:
    var label := Label.new()
    label.text = text
    label.position = at
    label.size = dimensions
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var typeface: Font = game.get("heading") if bold else game.get("font")
    if typeface != null: label.add_theme_font_override("font",typeface)
    label.add_theme_font_size_override("font_size",size)
    label.add_theme_color_override("font_color",INK if bold else MUTED)
    add_child(label)
    return label

func _build_legend(kinds: Array) -> void:
    for child in legend.get_children(): child.free()
    if kinds.is_empty(): return
    var width: float = legend.size.x/float(kinds.size())
    for index in range(kinds.size()):
        var kind: String = str(kinds[index])
        var icon := TextureRect.new()
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.texture = Models.icon(kind)
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        icon.position = Vector2(float(index)*width+(width-28)*.5,0)
        icon.size = Vector2(28,28)
        legend.add_child(icon)
        var label := Label.new()
        label.text = str(L.NAMES.get(kind,kind))
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        label.position = Vector2(float(index)*width,29)
        label.size = Vector2(width,23)
        var typeface: Font = game.get("font")
        if typeface != null: label.add_theme_font_override("font",typeface)
        label.add_theme_font_size_override("font_size",19)
        label.add_theme_color_override("font_color",INK)
        legend.add_child(label)

func _exit_tree() -> void:
    if is_instance_valid(game):
        var original: Camera3D = game.get("camera")
        if is_instance_valid(original): original.cull_mask = _original_mask
