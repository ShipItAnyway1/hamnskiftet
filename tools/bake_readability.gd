extends SceneTree
## Standalone native-model review and fleet artwork baking.
## Headless data checks (never create PNGs):
##   Godot --headless --path truck-depot --script res://tools/bake_readability.gd -- --validate
## Native gallery, 900x1000 front and gameplay views:
##   Godot --path truck-depot --script res://tools/bake_readability.gd -- --gallery
## Final fleet PNGs, using UiAssets._miniature and its exact stage recipe:
##   Godot --path truck-depot --script res://tools/bake_readability.gd -- --bake-fleet
## Optional --output-dir=/absolute/path applies to review artifacts only.
## The six final fleet paths always match UiAssets.upgrade_illustration.

const Models = preload("res://models.gd")
const UiAssets = preload("res://ui_assets.gd")
const Geometry = preload("res://geometry.gd")
const Layout = preload("res://layout.gd")
const TYPES: Array[String] = ["kyl","frys","schakt","adr","timmer","bransle"]
const NAMES := {"kyl":"KYL","frys":"FRYS","schakt":"SCHAKT","adr":"FARLIGT GODS","timmer":"TIMMER","bransle":"BRÄNSLE"}
const GALLERY_SIZE := Vector2i(900,1000)
const ART_SIZE := Vector2i(320,280)
var failures: Array[String] = []
var output_directory := "res://qa/readability"
var model_signature: String = ""
var ui_signature: String = ""
var gallery_views: Array[Dictionary] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var arguments: PackedStringArray = OS.get_cmdline_user_args()
    for argument in arguments:
        if argument.begins_with("--output-dir="):
            output_directory = argument.trim_prefix("--output-dir=")
    model_signature = FileAccess.get_sha256("res://models.gd")
    ui_signature = FileAccess.get_sha256("res://ui_assets.gd")
    _validate_models()
    if not failures.is_empty():
        quit(1)
        return
    if DisplayServer.get_name() == "headless":
        if "--bake-fleet" in arguments or "--gallery" in arguments:
            push_error("PNG rendering requires a native GPU run. Headless checks did not write artwork.")
            quit(2)
        else:
            quit(0)
        return
    if "--validate" in arguments:
        quit(0)
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
    if "--bake-fleet" in arguments:
        await _bake_fleet()
    else:
        await _gallery()
    quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error(message)

func _validate_models() -> void:
    var fingerprints: Dictionary = {}
    var dimensions: Array[Dictionary] = []
    for kind in TYPES:
        var icon: Texture2D = Models.icon(kind)
        check(icon != null and icon.get_width() >= 32,"Native symbol exists: "+kind)
        if icon != null:
            fingerprints[hash(icon.get_image().get_data())] = true
        for length in [1.66,2.56]:
            var capacity: int = 3 if length < 2 else 6
            var truck: Node3D = Models.truck(kind,length,0,capacity)
            check(str(truck.get_meta("kind","")) == kind,"Truck category metadata: "+kind)
            check(truck.has_meta("type_badge"),"Actual truck retains its category mark: "+kind)
            check(int(truck.get_meta("capacity",0)) == capacity,"Gallery represents the correct physical capacity: "+kind)
            Models.set_load_fraction(truck,1.0)
            var bounds: AABB = _bounds(truck)
            check(bounds.size.x > .3 and bounds.size.x <= .751,"Vehicle keeps its occupied column width: "+kind)
            check(bounds.size.z <= length+.001 and bounds.size.z > length*.7,"Vehicle keeps its two/three-cell length: "+kind)
            check(bounds.position.is_finite() and bounds.size.is_finite(),"Finite native vehicle geometry: "+kind)
            dimensions.append({"type":kind,"length":length,"capacity":capacity,"bounds":str(bounds)})
            truck.free()
        var cargo: Node3D = Models.cargo(kind,1.9)
        check(str(cargo.get_meta("kind","")) == kind,"Cargo matches vehicle category: "+kind)
        check(cargo.has_meta("type_badge"),"Physical cargo retains its matching symbol: "+kind)
        check(float(cargo.get_meta("lift_height",0)) > .1,"Physical cargo has a real lifting surface: "+kind)
        var cargo_bounds: AABB = _bounds(cargo)
        check(cargo_bounds.size.x > .1 and cargo_bounds.size.z > .1,"Physical cargo is three-dimensional: "+kind)
        cargo.free()
    check(fingerprints.size() == 6,"All six native category symbols are distinct")
    if failures.is_empty():
        print("READABILITY_MODELS_OK: six categories, twelve truck models, six physical cargo models, matching symbols and exact occupied dimensions")
        print("MODEL_SOURCE_SHA256 "+model_signature)
        print("READABILITY_DIMENSIONS "+JSON.stringify(dimensions))

func _bounds(model: Node3D) -> AABB:
    var boxes: Array[AABB] = []
    _collect_bounds(model,Transform3D.IDENTITY,boxes)
    if boxes.is_empty():
        check(false,"Native model contains no mesh geometry")
        return AABB()
    var result: AABB = boxes[0]
    for box in boxes:
        result = result.merge(box)
    return result

func _collect_bounds(parent: Node3D, accumulated: Transform3D, boxes: Array[AABB]) -> void:
    for child in parent.get_children():
        if child is Node3D:
            var local: Transform3D = accumulated*child.transform
            if child is MeshInstance3D and child.mesh != null:
                boxes.append(local*child.get_aabb())
            _collect_bounds(child,local,boxes)

func _stage(size: Vector2i) -> Dictionary:
    # Same render recipe as ui_assets.upgrade_illustration, deliberately calling
    # _miniature directly so an old baked PNG can never enter this generation.
    var viewport := SubViewport.new()
    viewport.size = size
    viewport.transparent_bg = true
    viewport.own_world_3d = true
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var stage := Node3D.new()
    viewport.add_child(stage)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(0,0,0,0)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("d5eaff")
    environment.environment.ambient_light_energy = .72
    stage.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-49,-32,0)
    sun.light_color = Color("fff3d2")
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    sun.shadow_bias = .02
    sun.directional_shadow_max_distance = 16
    stage.add_child(sun)
    var rim := DirectionalLight3D.new()
    rim.rotation_degrees = Vector3(-30,125,0)
    rim.light_color = Color("8ddaff")
    rim.light_energy = .32
    stage.add_child(rim)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.size = 3.35
    camera.position = Vector3(4.5,3.5,-5.5)
    stage.add_child(camera)
    camera.look_at_from_position(camera.position,Vector3(0,.55,0))
    camera.current = true
    return {"viewport":viewport,"stage":stage,"camera":camera}

func _plate(stage: Node3D) -> void:
    Geometry.cylinder(stage,Vector3(0,-.065,0),1.55,.13,"386a93")
    Geometry.cylinder(stage,Vector3(0,.004,0),1.48,.025,"7baac2")

func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color = Color.WHITE) -> void:
    var label := Label.new()
    label.text = text
    label.position = at
    label.size = dimensions
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)

func _gallery() -> void:
    root.size = GALLERY_SIZE
    root.content_scale_size = GALLERY_SIZE
    DisplayServer.window_set_title("Hamnskiftet · modelläsbarhet · native 3D")
    var ui := Control.new()
    root.add_child(ui)
    var background := ColorRect.new()
    background.color = Color("0b2340")
    background.size = Vector2(GALLERY_SIZE)
    ui.add_child(background)
    _label(ui,"HAMNSKIFTET · RIKTIGA SPELMODELLER",Vector2(20,9),Vector2(860,30),23)
    _label(ui,"LITEN · 2 RUTOR / 3 LAST",Vector2(34,46),Vector2(270,28),14,Color("9fc3dc"))
    _label(ui,"STOR · 3 RUTOR / 6 LAST",Vector2(330,46),Vector2(270,28),14,Color("9fc3dc"))
    _label(ui,"MATCHANDE FYSISKT GODS",Vector2(620,46),Vector2(275,28),14,Color("9fc3dc"))
    for row in range(TYPES.size()):
        var kind: String = TYPES[row]
        var base_y: float = 80+float(row)*150
        var strip := ColorRect.new()
        strip.color = Color("12314f") if row%2 == 0 else Color("0d2945")
        strip.position = Vector2(0,base_y)
        strip.size = Vector2(900,148)
        ui.add_child(strip)
        var swatch := ColorRect.new()
        swatch.color = Color(str(Layout.COLORS[kind]))
        swatch.position = Vector2(14,base_y+5)
        swatch.size = Vector2(5,17)
        ui.add_child(swatch)
        _label(ui,str(NAMES[kind]),Vector2(27,base_y+2),Vector2(280,23),16)
        for column in range(3):
            var container := SubViewportContainer.new()
            container.position = Vector2(column*300,base_y+24)
            container.size = Vector2(300,124)
            container.stretch = true
            container.mouse_filter = Control.MOUSE_FILTER_IGNORE
            ui.add_child(container)
            var view: Dictionary = _stage(Vector2i(300,124))
            container.add_child(view.viewport)
            if column == 1:
                UiAssets._miniature(view.stage,"fleet_"+kind)
            else:
                _plate(view.stage)
                var model: Node3D = Models.truck(kind,1.66,0,3) if column == 0 else Models.cargo(kind,1.9)
                model.rotation.y = .40
                if column == 0:
                    Models.set_load_fraction(model,1.0)
                view.stage.add_child(model)
            gallery_views.append(view)
    _label(ui,"SAMMA KAMERASKALA · ORIGINALMODELLER OCH SYMBOLER FRÅN SPELET",Vector2(20,982),Vector2(860,18),11,Color("7fa5c3"))
    await _draw_frames()
    _save_review_image(root.get_texture().get_image(),"gallery-front.png")
    for view in gallery_views:
        var camera: Camera3D = view.camera
        camera.look_at_from_position(Vector3(0,6.4,5.35),Vector3(0,.55,0))
    await _draw_frames()
    _save_review_image(root.get_texture().get_image(),"gallery-gameplay.png")
    print("READABILITY_GALLERY_OK "+ProjectSettings.globalize_path(output_directory))
    ui.free()
    gallery_views.clear()

func _draw_frames() -> void:
    for _index in range(4):
        await process_frame
    RenderingServer.force_draw(false)

func _save_review_image(image: Image, filename: String) -> void:
    var path: String = output_directory.path_join(filename)
    check(not image.is_empty(),"Native GPU produced a real image: "+filename)
    if not image.is_empty():
        check(image.save_png(ProjectSettings.globalize_path(path)) == OK,"Save review image: "+filename)

func _bake_fleet() -> void:
    var views: Array[Dictionary] = []
    for kind in TYPES:
        var view: Dictionary = _stage(ART_SIZE)
        root.add_child(view.viewport)
        UiAssets._miniature(view.stage,"fleet_"+kind)
        view["kind"] = kind
        views.append(view)
    await _draw_frames()
    var images: Array[Image] = []
    for view in views:
        var image: Image = view.viewport.get_texture().get_image()
        check(not image.is_empty() and image.get_size() == ART_SIZE,"Actual fleet bake dimensions: "+str(view.kind))
        if not image.is_empty():
            var used: Rect2i = image.get_used_rect()
            check(used.size.x > 60 and used.size.y > 60,"Visible native fleet object: "+str(view.kind))
            check(used.position.x > 1 and used.position.y > 1 and used.end.x < ART_SIZE.x-1 and used.end.y < ART_SIZE.y-1,"Fleet thumbnail avoids edge clipping: "+str(view.kind))
            check(image.get_pixel(0,0).a < .05,"Fleet thumbnail retains transparent corners: "+str(view.kind))
        images.append(image)
    check(FileAccess.get_sha256("res://models.gd") == model_signature,"Models stayed unchanged during the bake")
    check(FileAccess.get_sha256("res://ui_assets.gd") == ui_signature,"UI miniature recipe stayed unchanged during the bake")
    if failures.is_empty():
        for index in range(TYPES.size()):
            var path: String = "res://assets/art/upgrade-fleet_"+TYPES[index]+".png"
            check(images[index].save_png(ProjectSettings.globalize_path(path)) == OK,"Save final native fleet PNG: "+TYPES[index])
        var contact := Image.create(960,560,false,Image.FORMAT_RGBA8)
        contact.fill(Color("0b2340"))
        for index in range(images.size()):
            contact.blend_rect(images[index],Rect2i(Vector2i.ZERO,ART_SIZE),Vector2i((index%3)*320,(index/3)*280))
        _save_review_image(contact,"fleet-baked-contact.png")
        print("READABILITY_FLEET_BAKED_OK: six 320x280 transparent PNGs from current Models and UiAssets._miniature")
        print("BAKED_MODEL_SHA256 "+model_signature)
    for view in views:
        view.viewport.free()
