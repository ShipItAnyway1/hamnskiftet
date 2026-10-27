extends RefCounted
## Shared low-poly vehicle kit. All geometry is native and faces toward -Z.
## Truck wheels rotate about their local X axis. Cargo bottoms rest at Y = 0.

const Layout = preload("res://layout.gd")
static var _icons: Dictionary = {}
static var _badge_materials: Dictionary = {}
static var _badge_layers: Dictionary = {}
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _merged_meshes: Dictionary = {}
const CAB_COLORS: Array[String] = ["e6a340", "458d9c", "d97065", "63866a", "6b79ad", "b77f98"]
const STEEL := "63777d"
const DARK := "283b44"
const TIRE := "263036"

static func truck(kind: String, length: float = 2.4, variant: int = 0, capacity: int = 0) -> Node3D:
    var root := Node3D.new()
    root.name = "Truck_%s" % kind
    var full_length: float = maxf(length, 1.20)
    var cab_length: float = minf(.74, full_length * .32)
    var front: float = -full_length * .5 + .04
    var rear: float = full_length * .5 - .035
    var cab_color: String = str(Layout.COLORS.get(kind,"748a91"))
    var cab := Node3D.new()
    cab.name = "Cab"
    root.add_child(cab)
    var trailer := Node3D.new()
    trailer.name = "Trailer"
    root.add_child(trailer)
    var loads := Node3D.new()
    loads.name = "VisibleLoad"
    trailer.add_child(loads)
    var bed_front: float = front + cab_length + .11
    var bed_rear: float = rear - .035
    var bed_length: float = bed_rear - bed_front
    var bed_center: float = (bed_front + bed_rear) * .5
    _box(root, Vector3(0,.255,0), Vector3(.54,.11,full_length-.10), DARK)
    _box(root, Vector3(0,.208,.10), Vector3(.34,.07,full_length-.31), "1e3038")
    # Empty beds carry the same large color field as their cargo. The chassis
    # adds a dark outline without a floating selection ring.
    _box(trailer, Vector3(0,.366,bed_center), Vector3(.74,.075,bed_length+.015), DARK)
    _box(trailer, Vector3(0,.414,bed_center), Vector3(.70,.085,bed_length), cab_color)
    _box(trailer, Vector3(0,.460,bed_center), Vector3(.65,.014,bed_length-.025), cab_color)
    _box(trailer, Vector3(0,.30,rear-.015), Vector3(.69,.10,.055), DARK)
    for x in [-.265,.265]:
        _box(trailer, Vector3(x,.33,rear+.012), Vector3(.11,.045,.016), "d7675c", false)
    _box(trailer, Vector3(0,.28,rear+.015), Vector3(.16,.045,.012), "e9eee0", false)
    _cab(cab, front, cab_length, cab_color)
    var wheels: Array[Node3D] = []
    var axle_z: Array[float] = [front+.29, rear-.52, rear-.205]
    if full_length < 2.0:
        axle_z = [front+.29,rear-.27]
    for z in axle_z:
        _box(root, Vector3(0,.145,z), Vector3(.66,.05,.05), DARK)
        for side in [-1.0,1.0]:
            var wheel := _wheel(root, Vector3(side*.315,.145,z), side)
            wheels.append(wheel)
            if z > front+cab_length:
                _box(trailer, Vector3(side*.315,.315,z), Vector3(.105,.035,.30), DARK)
    match kind:
        "kyl", "frys":
            _reefer(trailer, loads, bed_front, bed_rear, kind == "frys")
        "schakt":
            _tipper(trailer, loads, bed_front, bed_rear)
        "adr":
            _adr_bed(trailer, loads, bed_front, bed_rear)
        "timmer":
            _timber_bed(trailer, loads, bed_front, bed_rear)
        "bransle":
            _tanker(trailer, loads, bed_front, bed_rear)
        _:
            _reefer(trailer, loads, bed_front, bed_rear, false)
    var type_badge: Node3D = _truck_mark(trailer,kind,bed_front,bed_rear)
    var tier_mark := Node3D.new()
    tier_mark.name = "CapacityStripes"
    trailer.add_child(tier_mark)
    if full_length >= 2.0:
        # A pair of broad reflective rear rails is a physical fleet marker.
        # Keep the roof reserved for the category pictogram and direction.
        _box(tier_mark,Vector3(0,.388,rear-.014),Vector3(.60,.06,.055),DARK,false)
        for y in [.375,.404]:
            _box(tier_mark,Vector3(0,y,rear+.016),Vector3(.54,.014,.012),"dcefff",false)
    _batch_static(tier_mark,false)
    _batch_static(cab, true)
    _batch_static(trailer, false)
    var load_units: Array[Node3D] = []
    for child in loads.get_children():
        if child is Node3D:
            var unit: Node3D = child
            _batch_static(unit, true)
            load_units.append(unit)
    _batch_static(root, false)
    root.set_meta("wheels", wheels)
    root.set_meta("load_root", loads)
    root.set_meta("load_units", load_units)
    if kind == "bransle" and not load_units.is_empty():
        root.set_meta("load_gauge", load_units[0])
    root.set_meta("cab", cab)
    root.set_meta("trailer", trailer)
    root.set_meta("kind", kind)
    root.set_meta("variant",variant)
    root.set_meta("length", full_length)
    root.set_meta("capacity",6 if full_length >= 2.0 else 3)
    root.set_meta("tier","large" if full_length >= 2.0 else "small")
    root.set_meta("tier_mark",tier_mark)
    root.set_meta("load_target", Vector3(0,.91,bed_rear-.20))
    root.set_meta("type_badge",type_badge)
    var fx := {"kind":kind,"body":trailer,"load_root":loads,"badge":type_badge}
    if trailer.has_meta("reefer_door"):
        var door: Node3D = trailer.get_meta("reefer_door")
        root.set_meta("reefer_door",door)
        fx["door"] = door
    root.set_meta("loading_fx",fx)
    set_capacity(root,capacity if capacity > 0 else (6 if full_length >= 2.0 else 3))
    set_vehicle_lights(root,false,false)
    set_turn_signal(root,0,false)
    return root

static func set_turn_signal(model: Node3D, side: int, on: bool) -> void:
    if not is_instance_valid(model) or not model.has_meta("cab"):
        return
    var lenses: Dictionary
    if model.has_meta("turn_signal_lenses"):
        lenses = model.get_meta("turn_signal_lenses")
    else:
        var length: float = float(model.get_meta("length"))
        var front: float = -length*.5+.04
        var rear: float = length*.5-.035
        var cab: Node3D = model.get_meta("cab")
        var trailer: Node3D = model.get_meta("trailer")
        lenses = {"left":[],"right":[]}
        for direction in [-1,1]:
            var group: Array = lenses.left if direction == -1 else lenses.right
            # Replace the existing amber blocks at their exact dimensions and
            # coordinates; flashing changes material only, never the footprint.
            group.append(_signal_lens(cab,Vector3(float(direction)*.254,.582,front-.012),Vector3(.070,.025,.024)))
            group.append(_signal_lens(trailer,Vector3(float(direction)*.265-.055,.33,rear+.014),Vector3(.025,.04,.017)))
        model.set_meta("turn_signal_lenses",lenses)
    var selected: int = clampi(side,-1,1)
    var lit: bool = on and selected != 0
    for key in ["left","right"]:
        var illuminate: bool = lit and ((selected == -1 and key == "left") or (selected == 1 and key == "right"))
        for lens in lenses[key]:
            lens.material_override = _lamp_material("ffbf38" if illuminate else "96713e",illuminate)
    model.set_meta("turn_signal",{"side":selected,"on":lit})

static func _signal_lens(parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
    var assembly := Node3D.new()
    assembly.name = "TurnIndicator"
    parent.add_child(assembly)
    return _box(assembly,at,size,"f0ad46",false)

static func set_vehicle_lights(model: Node3D, braking: bool, headlights: bool = true) -> void:
    if not is_instance_valid(model) or not model.has_meta("cab"):
        return
    var lights: Dictionary
    if model.has_meta("vehicle_lights"):
        lights = model.get_meta("vehicle_lights")
    else:
        var length: float = float(model.get_meta("length"))
        var front: float = -length*.5+.04
        var rear: float = length*.5-.035
        var cab: Node3D = model.get_meta("cab")
        var trailer: Node3D = model.get_meta("trailer")
        lights = {"head":_lamp_pair(cab,front-.033,.49,.246,Vector2(.100,.060),true),
            "brake":_lamp_pair(trailer,rear+.021,.33,.265,Vector2(.100,.036),false)}
        model.set_meta("vehicle_lights",lights)
    lights.head.material_override = _lamp_material("fff2ce" if headlights else "a8b9b7",headlights)
    lights.brake.material_override = _lamp_material("ff4d48" if braking else "893b46",braking)
    model.set_meta("headlights_on",headlights)
    model.set_meta("braking",braking)

static func _lamp_pair(parent: Node3D, z: float, y: float, x: float, size: Vector2, front: bool) -> MeshInstance3D:
    var housing := Node3D.new()
    housing.name = "FrontLampLenses" if front else "RearBrakeLenses"
    parent.add_child(housing)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for side in [-1.0,1.0]:
        var center := Vector3(side*x,y,z)
        var points := [center+Vector3(-size.x*.5,-size.y*.5,0),center+Vector3(size.x*.5,-size.y*.5,0),center+Vector3(size.x*.5,size.y*.5,0),center+Vector3(-size.x*.5,size.y*.5,0)]
        for index in [0,1,2,0,2,3]:
            surface.set_normal(Vector3.FORWARD if front else Vector3.BACK)
            surface.add_vertex(points[index])
    var mesh := MeshInstance3D.new()
    mesh.name = "PairedLenses"
    mesh.mesh = _share_merged_mesh(surface.commit())
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    housing.add_child(mesh)
    return mesh

static func _lamp_material(color: String, lit: bool) -> StandardMaterial3D:
    var key: String = "vehicle_lamp/%s/%s" % [color,lit]
    if not _materials.has(key):
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(color)
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        material.emission_enabled = lit
        material.emission = Color(color)
        material.emission_energy_multiplier = .35 if lit else 0.0
        _materials[key] = material
    return _materials[key]

static func set_capacity(model: Node3D, capacity: int) -> void:
    if not is_instance_valid(model) or not model.has_meta("length"):
        return
    var length: float = float(model.get_meta("length"))
    # The caller replaces the model when its physical two/three-cell class
    # changes. This setter cannot silently widen or lengthen an existing truck.
    var count: int = clampi(capacity,5,6) if length >= 2.0 else clampi(capacity,3,4)
    model.set_meta("capacity",count)
    var meter: Node3D
    if model.has_meta("capacity_meter"):
        meter = model.get_meta("capacity_meter")
    else:
        meter = _capacity_meter(model)
        model.set_meta("capacity_meter",meter)
    var multi: MultiMesh = meter.get_meta("segments")
    multi.instance_count = count
    var span: float = .56/float(count)
    for index in range(count):
        multi.set_instance_transform(index,Transform3D(Basis.from_scale(Vector3(span-.018,.009,.100)),Vector3(-.28+span*(float(index)+.5),.0235,0)))
    _update_capacity_meter(model,float(model.get_meta("load_fraction",1.0)))

static func _capacity_meter(model: Node3D) -> Node3D:
    var meter := Node3D.new()
    meter.name = "PhysicalLoadMeter"
    var trailer: Node3D = model.get_meta("trailer")
    trailer.add_child(meter)
    var heights := {"kyl":.951,"frys":1.057,"schakt":.862,"adr":.874,"timmer":1.039,"bransle":1.050}
    var height: float = float(heights.get(str(model.get_meta("kind")),.951))
    var rear: float = float(model.get_meta("length"))*.5-.035
    meter.position = Vector3(0,height,rear-.080)
    _box(meter,Vector3.ZERO,Vector3(.63,.038,.15),"192e43",false)
    for side in [-1.0,1.0]:
        var post_height: float = height-.445
        _box(meter,Vector3(side*.302,-post_height*.5,0),Vector3(.025,post_height,.035),STEEL)
    _batch_static(meter,false)
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_colors = true
    if not _meshes.has("box"):
        _meshes["box"] = BoxMesh.new()
    multi.mesh = _meshes["box"]
    var lights := MultiMeshInstance3D.new()
    lights.name = "LoadCapacitySegments"
    lights.multimesh = multi
    lights.material_override = _vertex_material(_material("ffffff",0,.75,true))
    lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    meter.add_child(lights)
    meter.set_meta("segments",multi)
    return meter

static func _update_capacity_meter(model: Node3D, fraction: float) -> void:
    if not model.has_meta("capacity_meter"):
        return
    var meter: Node3D = model.get_meta("capacity_meter")
    var multi: MultiMesh = meter.get_meta("segments")
    var filled: int = clampi(roundi(clampf(fraction,0.0,1.0)*float(multi.instance_count)),0,multi.instance_count)
    for index in range(multi.instance_count):
        multi.set_instance_color(index,Color("fff1ae") if index < filled else Color("4e6b81"))
    meter.set_meta("filled",filled)

static func set_load_fraction(model: Node3D, fraction: float) -> void:
    if not is_instance_valid(model) or not model.has_meta("load_root"):
        return
    var amount: float = clampf(fraction,0.0,1.0)
    var loads: Node3D = model.get_meta("load_root")
    loads.visible = amount > 0.0
    model.set_meta("load_fraction",amount)
    _update_capacity_meter(model,amount)
    if model.has_meta("load_gauge"):
        # The gauge origin is its bottom edge. Its tank shell belongs to the
        # trailer, so an empty tank remains a complete physical vehicle.
        var gauge: Node3D = model.get_meta("load_gauge")
        gauge.visible = amount > 0.0
        gauge.scale.y = maxf(amount,.001)
        return
    var units: Array = model.get_meta("load_units",[])
    var visible_count: int = mini(units.size(),int(ceil(amount*float(units.size())-.000001)))
    for index in range(units.size()):
        var unit: Node3D = units[index]
        if is_instance_valid(unit):
            unit.visible = index < visible_count

static func _load_unit(parent: Node3D, label: String) -> Node3D:
    var unit := Node3D.new()
    unit.name = label
    unit.set_meta("load_unit",true)
    parent.add_child(unit)
    return unit

static func icon(kind: String, size: int = 128) -> Texture2D:
    var pixels: int = clampi(size,32,512)
    var key: String = "%s/%d" % [kind,pixels]
    if not _icons.has(key):
        var image := Image.new()
        var error: Error = image.load_svg_from_string(_icon_svg(kind),float(pixels)/128.0)
        if error != OK:
            push_error("Could not rasterize procedural cargo icon: %s" % kind)
            image = Image.create(pixels,pixels,false,Image.FORMAT_RGBA8)
            image.fill(Color(str(Layout.COLORS.get(kind,"748a91"))))
        image.generate_mipmaps()
        _icons[key] = ImageTexture.create_from_image(image)
    return _icons[key]

static func badge(kind: String, diameter: float = .55) -> Node3D:
    var root := Node3D.new()
    root.name = "TypeBadge_%s" % kind
    if not _meshes.has("badge_plane"):
        var plane := PlaneMesh.new()
        plane.size = Vector2.ONE
        _meshes["badge_plane"] = plane
    if not _badge_materials.has(kind):
        var material := ShaderMaterial.new()
        material.shader = preload("res://shaders/upright_badge.gdshader")
        material.set_shader_parameter("plate_texture",_badge_layer_texture(kind,"plate"))
        material.set_shader_parameter("glyph_texture",_glyph_texture(kind))
        _badge_materials[kind] = material
    var face := MeshInstance3D.new()
    face.name = "IconFace"
    face.mesh = _meshes["badge_plane"]
    face.material_override = _badge_materials[kind]
    face.scale = Vector3(maxf(diameter,.01),1,maxf(diameter,.01))
    face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(face)
    root.set_meta("kind",kind)
    return root

static func _glyph_texture(kind: String) -> Texture2D:
    return _badge_layer_texture(kind,"glyph")

static func _badge_layer_texture(kind: String, layer: String) -> Texture2D:
    var key: String = layer+"/"+kind
    if not _badge_layers.has(key):
        var image := Image.new()
        var error: Error = image.load_svg_from_string(_icon_svg(kind,layer))
        if error != OK:
            push_error("Could not rasterize native badge layer: "+key)
            image = Image.create(128,128,false,Image.FORMAT_RGBA8)
            image.fill(Color.TRANSPARENT)
        image.generate_mipmaps()
        _badge_layers[key] = ImageTexture.create_from_image(image)
    return _badge_layers[key]

static func _icon_svg(kind: String, layer: String = "full") -> String:
    var color: String = "#"+str(Layout.COLORS.get(kind,"748a91"))
    var ink: String = "#14232c" if kind in ["kyl","schakt","adr"] else "#ffffff"
    var drawing: String = ""
    match kind:
        "frys":
            # One clear snow crystal. Six arms and a single broad fork per arm
            # survive the final 20–40 pixel projection without a noisy halo.
            drawing = '<path d="M64 18V110M24 41L104 87M24 87L104 41M49 27L64 42L79 27M49 101L64 86L79 101M27 57L44 53L42 35M86 93L84 75L101 71M27 71L44 75L42 93M86 35L84 53L101 57" fill="none" stroke="%s" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>' % ink
        "kyl":
            drawing = '<rect x="46" y="15" width="36" height="77" rx="18" fill="%s"/><circle cx="64" cy="90" r="25" fill="%s"/><path d="M64 30V85" stroke="%s" stroke-width="11" stroke-linecap="round"/><circle cx="64" cy="90" r="12" fill="%s"/>' % [ink,ink,color,color]
        "adr":
            drawing = '<path d="M64 12L116 64L64 116L12 64Z" fill="%s"/><rect x="57" y="31" width="14" height="45" rx="5" fill="#ffffff"/><circle cx="64" cy="94" r="8" fill="#ffffff"/>' % ink
        "timmer":
            drawing = '<g fill="%s"><circle cx="38" cy="85" r="25"/><circle cx="90" cy="85" r="25"/><circle cx="64" cy="39" r="25"/></g><g fill="%s"><circle cx="38" cy="85" r="11"/><circle cx="90" cy="85" r="11"/><circle cx="64" cy="39" r="11"/></g>' % [ink,color]
        "schakt":
            drawing = '<path d="M11 91L28 60L53 60L69 85L55 110L25 111ZM64 110L74 80L102 74L119 96L106 112ZM40 49L50 18L82 15L101 43L82 66L58 65Z" fill="%s"/>' % ink
        "bransle":
            drawing = '<path d="M64 12C54 32 25 60 25 83A39 39 0 0 0 103 83C103 60 74 32 64 12Z" fill="%s"/><path d="M42 81Q42 99 61 103" fill="none" stroke="%s" stroke-width="9" stroke-linecap="round"/>' % [ink,color]
        _:
            drawing = '<path d="M26 35H102V108H26ZM26 35L64 15L102 35M64 16V108" fill="none" stroke="%s" stroke-width="10" stroke-linejoin="round"/>' % ink
    var background: String = '<rect x="2" y="2" width="124" height="124" rx="18" fill="%s"/>' % color
    if layer == "glyph":
        # All glyphs fit inside a circle. A 3% ink inset protects diagonal
        # gravel corners and mip filtering as the label turns on the belt.
        drawing = '<g transform="translate(64 64) scale(.97) translate(-64 -64)">%s</g>' % drawing
        background = ""
    elif layer == "plate":
        drawing = ""
    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">%s%s</svg>' % [background,drawing]

static func _mounted_mark(parent: Node3D, kind: String, at: Vector3, size: float, vertical: bool = false) -> Node3D:
    var mark: Node3D = badge(kind,size)
    mark.position = at
    if vertical:
        mark.rotation.x = PI*.5
    parent.add_child(mark)
    return mark

static func _truck_mark(parent: Node3D, kind: String, front: float, rear: float) -> Node3D:
    var length: float = rear-front
    var center: float = front+length*.52
    var height: float = .94
    if kind == "frys":
        height = 1.05
    elif kind == "schakt":
        center = front+.325
        height = .840
        _box(parent,Vector3(0,height-.017,center),Vector3(.71,.03,.70),str(Layout.COLORS[kind]))
        for side in [-1.0,1.0]:
            _box(parent,Vector3(side*.321,.65,front+.045),Vector3(.035,.36,.045),str(Layout.COLORS[kind]))
    elif kind == "adr":
        center = front+.325
        height = .846
        _box(parent,Vector3(0,height-.017,center),Vector3(.71,.03,.70),str(Layout.COLORS[kind]))
        for side in [-1.0,1.0]:
            _box(parent,Vector3(side*.313,.647,front+.06),Vector3(.035,.38,.04),DARK)
    elif kind == "timmer":
        center = front+.33
        height = 1.027
        _box(parent,Vector3(0,height-.016,center),Vector3(.71,.027,.70),str(Layout.COLORS[kind]))
    elif kind == "bransle":
        center = front+length*.56
        height = 1.034
        _box(parent,Vector3(0,height-.014,center),Vector3(.71,.023,.70),str(Layout.COLORS[kind]))
    return _mounted_mark(parent,kind,Vector3(0,height,center),.68)

static func cargo(kind: String, scale_factor: float = 1.0, quality: int = 0) -> Node3D:
    var root := Node3D.new()
    root.name = "Cargo_%s" % kind
    _pallet(root)
    var mark: Node3D
    match kind:
        "kyl":
            _produce(root)
            _box(root,Vector3(0,.344,.025),Vector3(.46,.018,.40),str(Layout.COLORS[kind]),false)
            mark = _mounted_mark(root,kind,Vector3(0,.355,.025),.50)
        "frys":
            _frozen(root)
            mark = _mounted_mark(root,kind,Vector3(0,.399,0),.54)
        "schakt":
            _open_bin(root)
            _box(root,Vector3(0,.350,.025),Vector3(.46,.021,.40),str(Layout.COLORS[kind]),false)
            mark = _mounted_mark(root,kind,Vector3(0,.363,.025),.50)
        "adr":
            # One substantial orange industrial drum reads at belt distance;
            # two tiny lid stickers previously disappeared into their rims.
            _drum(root,Vector3(0,.085,0),.225,.385,str(Layout.COLORS[kind]))
            mark = _mounted_mark(root,kind,Vector3(0,.482,0),.48)
        "timmer":
            for x in [-.16,0.0,.16]:
                _log(root,Vector3(x,.16,0),.077,.47)
            for x in [-.08,.08]:
                _log(root,Vector3(x,.292,0),.077,.47)
            for z in [-.155,.155]:
                _strap(root,[Vector3(-.24,.092,z),Vector3(-.24,.19,z),Vector3(-.10,.37,z),Vector3(.10,.37,z),Vector3(.24,.19,z),Vector3(.24,.092,z)],.011)
            _box(root,Vector3(0,.374,.025),Vector3(.43,.016,.40),str(Layout.COLORS[kind]),false)
            mark = _mounted_mark(root,kind,Vector3(0,.384,.025),.50)
        "bransle":
            _tank_module(root)
            mark = _mounted_mark(root,kind,Vector3(0,.511,0),.48)
        _:
            _produce(root)
            mark = _mounted_mark(root,kind,Vector3(0,.355,.065),.285)
    # Batch opaque geometry but retain the mounting node used by cargo effects.
    _batch_static(root,false)
    root.set_meta("type_badge",mark)
    root.set_meta("lift_height",_model_top(root))
    root.scale = Vector3.ONE*maxf(scale_factor,.01)
    root.set_meta("kind",kind)
    set_cargo_quality(root,quality)
    return root

static func set_cargo_quality(model: Node3D, rank: int) -> void:
    if not is_instance_valid(model) or not model.has_meta("lift_height"):
        return
    var quality: int = maxi(0,rank)
    model.set_meta("quality",quality)
    var existing: Node3D = model.get_meta("quality_mark") if model.has_meta("quality_mark") else null
    if quality == 0:
        if is_instance_valid(existing):
            existing.free()
        model.remove_meta("quality_mark")
        return
    if is_instance_valid(existing):
        return
    var seal := Node3D.new()
    seal.name = "GoldPalletQualityBand"
    model.add_child(seal)
    # A single physical quality band follows the pallet's top edge so it also
    # remains visible as goods turn on the belt. It is not a floating UI badge.
    # This thin edge remains inside the existing .52 x .488 footprint
    # and far below every cargo's original lifting/gripper attachment height.
    for side in [-1.0,1.0]:
        _box(seal,Vector3(0,.0848,side*.235),Vector3(.52,.0016,.018),"f9cd50",false)
        _box(seal,Vector3(side*.251,.0848,0),Vector3(.018,.0016,.452),"f9cd50",false)
    _batch_static(seal,false)
    model.set_meta("quality_mark",seal)

static func _model_top(model: Node3D) -> float:
    var entries: Array[Dictionary] = []
    _collect_meshes(model,Transform3D.IDENTITY,true,entries)
    var top: float = 0.0
    for entry in entries:
        var mesh_node: MeshInstance3D = entry.node
        var transformed: AABB = entry.transform*mesh_node.get_aabb()
        top = maxf(top,transformed.end.y)
    return top

static func _cab(parent: Node3D, front: float, length: float, color: String) -> void:
    var back: float = front+length
    var profile := PackedVector2Array([Vector2(front,.305),Vector2(back,.305),Vector2(back,.86),Vector2(front+.115,.86),Vector2(front,.625)])
    _profile(parent, profile,.66,color)
    _box(parent, Vector3(0,.325,front+.014),Vector3(.68,.07,.08),"b7c4bd")
    _box(parent, Vector3(0,.29,front+.036),Vector3(.61,.035,.065),DARK)
    _box(parent, Vector3(0,.475,front-.008),Vector3(.32,.145,.017),DARK)
    for row in range(4):
        _box(parent,Vector3(0,.424+row*.031,front-.020),Vector3(.285,.011,.014),"b6c5c4",false)
    _quad(parent,[Vector3(-.279,.655,front+.011),Vector3(.279,.655,front+.011),Vector3(.279,.821,front+.093),Vector3(-.279,.821,front+.093)],"284e60",.22)
    _rod(parent,Vector3(0,.655,front+.006),Vector3(0,.823,front+.092),.009,"c4d2c9",false)
    for side in [-1.0,1.0]:
        var x: float = side*.334
        _quad(parent,[Vector3(x,.654,front+.054),Vector3(x,.82,front+.137),Vector3(x,.82,back-.065),Vector3(x,.654,back-.065)],"315b6c",.24)
        _rod(parent,Vector3(x,.785,front+.135),Vector3(x,.785,back-.084),.008,"8fbbc2",false)
        _box(parent,Vector3(side*.338,.568,back-.145),Vector3(.015,.025,.083),"dbe0d2",false)
        _box(parent,Vector3(side*.334,.485,back-.047),Vector3(.008,.26,.012),Color(color).darkened(.20).to_html(false),false)
        _box(parent,Vector3(side*.322,.335,back-.15),Vector3(.105,.039,.26),STEEL)
        _rod(parent,Vector3(side*.324,.69,front+.12),Vector3(side*.351,.69,front+.055),.012,STEEL,false)
        _box(parent,Vector3(side*.352,.703,front+.051),Vector3(.035,.10,.064),DARK,false)
        _box(parent,Vector3(side*.354,.706,front+.047),Vector3(.037,.071,.041),"a2c5c7",false)
        _box(parent,Vector3(side*.246,.49,front-.019),Vector3(.112,.072,.025),"fff0c0",false)
        _sphere(parent,Vector3(side*.238,.884,back-.105),.027,"efb44e",Vector3(1,.75,1),false)
    # One broad, quiet roof surface gives direction equal visual weight to type.
    # Its complete footprint fits the flat cab roof even at full length 1.66.
    var roof_center: float = front+(.115+length)*.5
    _box(parent,Vector3(0,.868,roof_center),Vector3(.59,.019,length-.13),Color(color).lightened(.13).to_html(false),false)
    _box(parent,Vector3(0,.883,roof_center),Vector3(.54,.012,minf(.40,length-.135)),DARK,false)
    _arrow(parent,Vector3(0,.891,roof_center),1.0)

static func _wheel(parent: Node3D, at: Vector3, side: float) -> Node3D:
    var root := Node3D.new()
    root.name = "Wheel"
    parent.add_child(root)
    root.position = at
    var tire := _cylinder(root,Vector3.ZERO,.145,.107,TIRE)
    tire.rotation.z = PI*.5
    var shoulder := _cylinder(root,Vector3(side*.043,0,0),.116,.015,"35454b",false)
    shoulder.rotation.z = PI*.5
    var rim := _cylinder(root,Vector3(side*.049,0,0),.083,.009,"bcc6be",false,.50)
    rim.rotation.z = PI*.5
    var hub := _cylinder(root,Vector3(side*.053,0,0),.034,.010,STEEL,false,.45)
    hub.rotation.z = PI*.5
    for spoke in range(5):
        var angle: float = float(spoke)*TAU/5.0
        _sphere(root,Vector3(side*.055,sin(angle)*.056,cos(angle)*.056),.010,DARK,Vector3(.4,1,1),false)
    _batch_static(root, false)
    return root

static func _reefer(parent: Node3D, loads: Node3D, front: float, rear: float, frozen: bool) -> void:
    var center: float = (front+rear)*.5
    var length: float = rear-front
    var kind: String = "frys" if frozen else "kyl"
    var color: String = str(Layout.COLORS[kind])
    var roof_y: float = 1.025 if frozen else .915
    var wall_height: float = roof_y-.45
    for side in [-1.0,1.0]:
        _box(parent,Vector3(side*.336,.45+wall_height*.5,center),Vector3(.047,wall_height,length),color)
        _box(parent,Vector3(side*.362,.48,center),Vector3(.013,.045,length-.04),DARK,false)
        # Three broad ribs survive small-screen projection; tiny pinstripes do not.
        for fraction in [.08,.50,.92]:
            _box(parent,Vector3(side*.363,.45+wall_height*.5,lerpf(front,rear,fraction)),Vector3(.012,wall_height*.88,.027),Color(color).darkened(.15).to_html(false),false)
    _box(parent,Vector3(0,.45+wall_height*.5,front+.023),Vector3(.70,wall_height,.045),color)
    # Solid colored roofs distinguish actual box trucks from open-top dumpers.
    # A small rear loading hatch remains open, and the rear door is independent.
    _box(parent,Vector3(0,roof_y+.011,front+length*.43),Vector3(.70,.022,length*.86),color)
    var door := Node3D.new()
    door.name = "ReeferDoor"
    door.position = Vector3(-.35,.45,rear-.021)
    parent.add_child(door)
    _box(door,Vector3(.35,wall_height*.5,0),Vector3(.70,wall_height,.042),color)
    _box(door,Vector3(.35,wall_height*.5,.026),Vector3(.016,wall_height*.88,.012),DARK,false)
    for x in [.17,.53]:
        _box(door,Vector3(x,wall_height*.5,.032),Vector3(.022,wall_height*.64,.017),STEEL,false)
    _batch_static(door,true)
    parent.set_meta("reefer_door",door)
    if frozen:
        # Tall blue insulated body plus a high compressor gives a distinct profile.
        _box(parent,Vector3(0,roof_y+.061,front+.10),Vector3(.62,.10,.18),color)
        for x in [-.22,-.11,0.0,.11,.22]:
            _box(parent,Vector3(x,roof_y+.117,front+.10),Vector3(.055,.014,.16),DARK,false)
        _box(parent,Vector3(0,.83,front-.045),Vector3(.37,.22,.10),color)
        for x in [-.087,.087]:
            var fan := _cylinder(parent,Vector3(x,.84,front-.101),.071,.014,DARK,false)
            fan.rotation.x = PI*.5
            _box(parent,Vector3(x,.84,front-.112),Vector3(.10,.018,.009),"d9ecff",false)
    else:
        _box(parent,Vector3(0,.78,front-.043),Vector3(.26,.15,.085),color)
        for x in [-.075,0.0,.075]:
            _box(parent,Vector3(x,.78,front-.09),Vector3(.025,.095,.010),DARK,false)
        for x in [-.17,0.0,.17]:
            _box(parent,Vector3(x,roof_y+.026,front+.09),Vector3(.075,.008,.11),DARK,false)
    var unit_scale: float = .78 if length < 1.20 else .87
    var unit_depth: float = .488*unit_scale
    var count: int = clampi(int(floor((length+.04)/(unit_depth+.04))),1,3)
    var edge: float = unit_depth*.5+.025
    for i in range(count):
        var unit: Node3D = cargo(kind,unit_scale)
        var fraction: float = float(i)/maxf(count-1,1)
        unit.position = Vector3(0,.452,lerpf(rear-edge,front+edge,fraction) if count > 1 else center)
        unit.name = "FrozenPallet_%d" % i if frozen else "ProducePallet_%d" % i
        unit.set_meta("load_unit",true)
        loads.add_child(unit)

static func _tipper(parent: Node3D, loads: Node3D, front: float, rear: float) -> void:
    var paint: String = str(Layout.COLORS["schakt"])
    _box(parent,Vector3(0,.475,(front+rear)*.5),Vector3(.54,.06,rear-front),paint)
    for side in [-1.0,1.0]:
        _quad(parent,[Vector3(side*.27,.49,front),Vector3(side*.36,.80,front),Vector3(side*.36,.80,rear),Vector3(side*.27,.49,rear)],paint)
        _rod(parent,Vector3(side*.354,.805,front),Vector3(side*.354,.805,rear),.017,str(Layout.COLORS["schakt"]))
        for fraction in [.12,.50,.88]:
            var z: float = lerpf(front,rear,fraction)
            _rod(parent,Vector3(side*.274,.50,z),Vector3(side*.356,.795,z),.015,"e5d67b",false)
    for z in [front,rear]:
        _quad(parent,[Vector3(-.27,.49,z),Vector3(.27,.49,z),Vector3(.36,.80,z),Vector3(-.36,.80,z)],paint)
    var section_length: float = (rear-front)/3.0
    for index in range(3):
        var pile: Node3D = _load_unit(loads,"GravelPile_%d" % index)
        var z: float = front+section_length*(float(index)+.5)
        _rocks(pile,Vector3(0,.508,z),.51,section_length*.55,3,2)
    _rod(parent,Vector3(0,.32,front+.12),Vector3(0,.47,front+.37),.045,"adbbb8")

static func _adr_bed(parent: Node3D, loads: Node3D, front: float, rear: float) -> void:
    for side in [-1.0,1.0]:
        _box(parent,Vector3(side*.34,.51,(front+rear)*.5),Vector3(.035,.14,rear-front),str(Layout.COLORS["adr"]))
        for z in [front+.07,rear-.07]:
            _box(parent,Vector3(side*.34,.59,z),Vector3(.036,.26,.04),STEEL)
        _box(parent,Vector3(side*.364,.535,(front+rear)*.5),Vector3(.012,.13,.21),str(Layout.COLORS["adr"]),false)
        var badge := _box(parent,Vector3(side*.369,.535,(front+rear)*.5),Vector3(.006,.065,.065),DARK,false)
        badge.rotation.x = PI*.25
    var rows: int = 3 if rear-front < 1.45 else 4
    for row in range(rows):
        var z: float = lerpf(front+.16,rear-.16,float(row)/maxf(rows-1,1))
        for x in [-.15,.15]:
            var drum: Node3D = _load_unit(loads,"Drum_%d_%s" % [row,str(x)])
            _drum(drum,Vector3(x,.452,z),.116,.37,"c76953" if row%2 == 0 else "d39d47")

static func _timber_bed(parent: Node3D, loads: Node3D, front: float, rear: float) -> void:
    var center: float = (front+rear)*.5
    var length: float = rear-front-.035
    for side in [-1.0,1.0]:
        for z in [front+.10,center,rear-.10]:
            _box(parent,Vector3(side*.34,.717,z),Vector3(.037,.54,.04),str(Layout.COLORS["timmer"]))
            _box(parent,Vector3(side*.34,.995,z),Vector3(.05,.025,.057),"a0aca0",false)
    # Stable bottom-to-top order means partial loads never suspend an upper
    # log in midair or leave disconnected cut ends/rings visible.
    for x in [-.202,0.0,.202]:
        var log_unit: Node3D = _load_unit(loads,"BottomLog_%s" % str(x))
        _log(log_unit,Vector3(x,.55,center),.099,length)
    for x in [-.101,.101]:
        var log_unit: Node3D = _load_unit(loads,"MiddleLog_%s" % str(x))
        _log(log_unit,Vector3(x,.722,center),.099,length)
    var top_log: Node3D = _load_unit(loads,"TopLogAndStraps")
    _log(top_log,Vector3(0,.894,center),.099,length)
    for z in [front+.25,rear-.25]:
        _strap(top_log,[Vector3(-.31,.46,z),Vector3(-.31,.60,z),Vector3(-.20,.82,z),Vector3(0,1.003,z),Vector3(.20,.82,z),Vector3(.31,.60,z),Vector3(.31,.46,z)],.012)

static func _tanker(parent: Node3D, loads: Node3D, front: float, rear: float) -> void:
    var center: float = (front+rear)*.5
    var length: float = rear-front-.11
    var tank := _cylinder(parent,Vector3(0,.716,center),.278,length,str(Layout.COLORS["bransle"]),true,.10)
    tank.rotation.x = PI*.5
    for z in [center-length*.5,center+length*.5]:
        _sphere(parent,Vector3(0,.716,z),.277,str(Layout.COLORS["bransle"]),Vector3(1,1,.19))
    for fraction in [.24,.76]:
        var z: float = lerpf(front,rear,fraction)
        _box(parent,Vector3(0,.445,z),Vector3(.49,.075,.13),STEEL)
        var band := _torus(parent,Vector3(0,.716,z),.285,str(Layout.COLORS["bransle"]))
        band.rotation.x = PI*.5
    var gauge: Node3D = _load_unit(loads,"LiquidLevelGauge")
    gauge.position.y = .679
    for side in [-1.0,1.0]:
        _box(parent,Vector3(side*.282,.718,center),Vector3(.015,.105,length*.68),DARK,false)
        _box(gauge,Vector3(side*.293,.034,center),Vector3(.012,.068,length*.64),str(Layout.COLORS["bransle"]),false)
        _rod(parent,Vector3(side*.18,1.005,front+.18),Vector3(side*.18,1.005,rear-.18),.012,STEEL,false)
        for z in [front+.22,rear-.22]:
            _rod(parent,Vector3(side*.18,.927,z),Vector3(side*.18,1.007,z),.012,STEEL,false)
    _cylinder(parent,Vector3(0,1.007,front+.045),.089,.032,DARK,false)
    _cylinder(parent,Vector3(0,1.028,front+.045),.070,.015,"e4dcc5",false,.45)
    for x in [-.105,.105]:
        _rod(parent,Vector3(x,.48,rear+.006),Vector3(x,.96,rear+.006),.012,STEEL,false)
    for y in [.52,.62,.72,.82,.92]:
        _rod(parent,Vector3(-.105,y,rear+.009),Vector3(.105,y,rear+.009),.010,"a6b6b0",false)

static func _pallet(parent: Node3D) -> void:
    for x in [-.185,0.0,.185]:
        _box(parent,Vector3(x,.027,0),Vector3(.073,.054,.48),"98714a",false)
    for z in [-.192,-.064,.064,.192]:
        _box(parent,Vector3(0,.067,z),Vector3(.52,.034,.104),"c39a61",false)

static func _produce(parent: Node3D) -> void:
    var color: String = str(Layout.COLORS["kyl"])
    _box(parent,Vector3(0,.161,0),Vector3(.40,.061,.36),"4e9b51",false)
    _box(parent,Vector3(0,.107,0),Vector3(.46,.045,.43),color,false)
    for side in [-1.0,1.0]:
        for y in [.16,.235]:
            _box(parent,Vector3(side*.225,y,0),Vector3(.024,.047,.43),color,false)
            _box(parent,Vector3(0,y,side*.207),Vector3(.46,.047,.023),color,false)
        for z in [-.193,.193]:
            _box(parent,Vector3(side*.216,.207,z),Vector3(.034,.245,.034),color,false)
    # A real half lid carries the mark. Fruit remains exposed at the open end.
    for col in range(3):
        var p := Vector3(-.145+col*.145,.268,-.147)
        _sphere(parent,p,.065,"f4a320",Vector3(1,.95,1),false)
        _box(parent,p+Vector3(0,.062,0),Vector3(.015,.024,.015),"42652e",false)

static func _frozen(parent: Node3D) -> void:
    var color: String = str(Layout.COLORS["frys"])
    _box(parent,Vector3(0,.230,0),Vector3(.46,.29,.43),color,false)
    _box(parent,Vector3(0,.386,0),Vector3(.48,.024,.45),color,false)
    for side in [-1.0,1.0]:
        for z in [-.20,.20]:
            _box(parent,Vector3(side*.213,.23,z),Vector3(.026,.272,.027),"90bfff",false)
        _box(parent,Vector3(side*.232,.242,0),Vector3(.022,.041,.17),DARK,false)
    _box(parent,Vector3(0,.101,-.221),Vector3(.40,.025,.012),DARK,false)

static func _open_bin(parent: Node3D) -> void:
    var color: String = str(Layout.COLORS["schakt"])
    _box(parent,Vector3(0,.107,0),Vector3(.46,.04,.44),color,false)
    for side in [-1.0,1.0]:
        _box(parent,Vector3(side*.228,.20,0),Vector3(.025,.20,.45),color,false)
        _box(parent,Vector3(0,.20,side*.213),Vector3(.46,.20,.025),color,false)
    _box(parent,Vector3(0,.141,-.08),Vector3(.38,.035,.20),"747e79",false)
    _rocks(parent,Vector3(0,.16,-.10),.38,.16,3,2)

static func _tank_module(parent: Node3D) -> void:
    var color: String = str(Layout.COLORS["bransle"])
    for z in [-.14,.14]:
        _box(parent,Vector3(0,.112,z),Vector3(.44,.055,.08),DARK,false)
    var tank := _cylinder(parent,Vector3(0,.285,0),.20,.40,color,false)
    tank.rotation.x = PI*.5
    for z in [-.20,.20]:
        _sphere(parent,Vector3(0,.285,z),.198,color,Vector3(1,1,.16),false)
    for z in [-.125,.125]:
        var band := _torus(parent,Vector3(0,.285,z),.203,DARK,false)
        band.rotation.x = PI*.5
    _box(parent,Vector3(0,.495,0),Vector3(.40,.026,.40),color,false)
    _box(parent,Vector3(0,.20,-.239),Vector3(.065,.053,.035),DARK,false)
    _box(parent,Vector3(0,.234,-.244),Vector3(.10,.014,.025),color,false)

static func _drum(parent: Node3D, bottom: Vector3, radius: float, height: float, _color: String) -> void:
    var color: String = str(Layout.COLORS["adr"])
    _cylinder(parent,bottom+Vector3(0,height*.5,0),radius,height,color,false)
    for y in [height*.12,height*.87]:
        _cylinder(parent,bottom+Vector3(0,y,0),radius*1.035,height*.05,DARK,false)
    _cylinder(parent,bottom+Vector3(0,height+.004,0),radius*.94,.012,Color(color).lightened(.20).to_html(false),false)
    _cylinder(parent,bottom+Vector3(radius*.73,height+.013,0),radius*.16,.015,DARK,false)
    var diamond := _box(parent,bottom+Vector3(0,height*.50,-radius-.008),Vector3(radius*.96,radius*.96,.009),DARK,false)
    diamond.rotation.z = PI*.25
    _box(parent,bottom+Vector3(0,height*.515,-radius-.014),Vector3(.015,.050,.007),"fff9e8",false)
    _sphere(parent,bottom+Vector3(0,height*.385,-radius-.014),.008,"fff9e8",Vector3(1,1,.25),false)

static func _log(parent: Node3D, center: Vector3, radius: float, length: float) -> void:
    var body := _cylinder(parent,center,radius,length,"815c3c")
    body.rotation.x = PI*.5
    for side in [-1.0,1.0]:
        var end: Vector3 = center+Vector3(0,0,side*(length*.5+.002))
        var cut := _cylinder(parent,end,radius*.94,.007,"d8b77a",false)
        cut.rotation.x = PI*.5
        var ring := _torus(parent,end+Vector3(0,0,side*.005),radius*.67,"a9804e",false)
        ring.rotation.x = PI*.5
        var heart := _cylinder(parent,end+Vector3(0,0,side*.007),radius*.15,.005,"a48152",false)
        heart.rotation.x = PI*.5

static func _rocks(parent: Node3D, bottom: Vector3, width: float, length: float, cols: int, rows: int) -> void:
    for row in range(rows):
        for col in range(cols):
            var x: float = (float(col)/maxf(cols-1,1)-.5)*width*.72
            var z: float = (float(row)/maxf(rows-1,1)-.5)*length*.78
            var radius: float = minf(width/float(cols)*.66,length/float(rows)*.68)
            var center: Vector3 = bottom+Vector3(x,radius*.65,z)
            var rock := _sphere(parent,center,radius,["8b9692","aab0a0","75817e"][(row+col)%3],Vector3(1,.68,1.14),false)
            rock.rotation.y = float(row*7+col*11)*.47
    for i in range(3):
        _sphere(parent,bottom+Vector3((i-1)*width*.18,.15,(i%2-.5)*length*.23),width*.14,"a1a99a",Vector3(1,.8,1.25),false)

static func _strap(parent: Node3D, points: Array[Vector3], radius: float) -> void:
    for i in range(points.size()-1):
        _rod(parent,points[i],points[i+1],radius,DARK,false)

static func _arrow(parent: Node3D, at: Vector3, size: float) -> void:
    var outline := PackedVector2Array([Vector2(-.09,.145),Vector2(.09,.145),Vector2(.09,-.015),Vector2(.215,-.015),Vector2(0,-.185),Vector2(-.215,-.015),Vector2(-.09,-.015)])
    var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index in indices:
        surface.set_normal(Vector3.UP)
        surface.add_vertex(Vector3(outline[index].x*size,0,outline[index].y*size))
    var instance := MeshInstance3D.new()
    instance.mesh = surface.commit()
    instance.material_override = _material("fff9e8",0,.8,true,true)
    instance.position = at
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)

static func _profile(parent: Node3D, profile: PackedVector2Array, width: float, color: String) -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var indices: PackedInt32Array = Geometry2D.triangulate_polygon(profile)
    for side in [-1.0,1.0]:
        for index in indices:
            surface.set_normal(Vector3(side,0,0))
            surface.add_vertex(Vector3(side*width*.5,profile[index].y,profile[index].x))
    for i in range(profile.size()):
        var p: Vector2 = profile[i]
        var q: Vector2 = profile[(i+1)%profile.size()]
        var normal := Vector3(0,-(q.x-p.x),q.y-p.y).normalized()
        var vertices: Array[Vector3] = [Vector3(-width*.5,p.y,p.x),Vector3(width*.5,p.y,p.x),Vector3(width*.5,q.y,q.x),Vector3(-width*.5,q.y,q.x)]
        for index in [0,1,2,0,2,3]:
            surface.set_normal(normal)
            surface.add_vertex(vertices[index])
    var instance := MeshInstance3D.new()
    instance.mesh = surface.commit()
    instance.material_override = _material(color,0,.72,false,true)
    parent.add_child(instance)

static func _quad(parent: Node3D, vertices: Array[Vector3], color: String, roughness: float = .70) -> void:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var normal: Vector3 = (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).normalized()
    for index in [0,1,2,0,2,3]:
        surface.set_normal(normal)
        surface.add_vertex(vertices[index])
    var instance := MeshInstance3D.new()
    instance.mesh = surface.commit()
    instance.material_override = _material(color,0,roughness,false,true)
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)

static func _box(parent: Node3D, at: Vector3, size: Vector3, color: String, shadows: bool = true) -> MeshInstance3D:
    if not _meshes.has("box"):
        _meshes["box"] = BoxMesh.new()
    return _instance(parent,_meshes["box"],at,size,color,shadows)

static func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: String, shadows: bool = true, metallic: float = 0.0) -> MeshInstance3D:
    if not _meshes.has("cylinder"):
        var primitive := CylinderMesh.new()
        primitive.top_radius = .5
        primitive.bottom_radius = .5
        primitive.height = 1.0
        primitive.radial_segments = 12
        primitive.rings = 1
        _meshes["cylinder"] = primitive
    var node := _instance(parent,_meshes["cylinder"],at,Vector3(radius*2,height,radius*2),color,shadows)
    node.material_override = _material(color,metallic,.48 if metallic > 0 else .76)
    return node

static func _sphere(parent: Node3D, at: Vector3, radius: float, color: String, stretch: Vector3 = Vector3.ONE, shadows: bool = true) -> MeshInstance3D:
    if not _meshes.has("sphere"):
        var primitive := SphereMesh.new()
        primitive.radius = .5
        primitive.height = 1.0
        primitive.radial_segments = 8
        primitive.rings = 3
        _meshes["sphere"] = primitive
    return _instance(parent,_meshes["sphere"],at,stretch*radius*2,color,shadows)

static func _torus(parent: Node3D, at: Vector3, radius: float, color: String, shadows: bool = true) -> MeshInstance3D:
    if not _meshes.has("torus"):
        var primitive := TorusMesh.new()
        primitive.inner_radius = .46
        primitive.outer_radius = .50
        primitive.rings = 12
        primitive.ring_segments = 5
        _meshes["torus"] = primitive
    return _instance(parent,_meshes["torus"],at,Vector3.ONE*radius/.48,color,shadows)

static func _rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: String, shadows: bool = true) -> MeshInstance3D:
    var node := _cylinder(parent,(from+to)*.5,radius,from.distance_to(to),color,shadows)
    node.quaternion = Quaternion(Vector3.UP,(to-from).normalized())
    return node

static func _instance(parent: Node3D, mesh: Mesh, at: Vector3, size: Vector3, color: String, shadows: bool) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.position = at
    node.scale = size
    node.material_override = _material(color)
    if not shadows:
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(node)
    return node

static func _material(color: String, metallic: float = 0.0, roughness: float = .72, unshaded: bool = false, double_sided: bool = false) -> StandardMaterial3D:
    var key: String = "%s/%.2f/%.2f/%s/%s" % [color,metallic,roughness,unshaded,double_sided]
    if not _materials.has(key):
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(color)
        material.metallic = metallic
        material.roughness = roughness
        if color in Layout.COLORS.values():
            # Category paint keeps the exact icon hue under every harbor light.
            # Broad baked face shading below retains a three-dimensional toy
            # silhouette without blowing blue paint out into cyan.
            material.set_meta("category_paint",true)
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        elif unshaded:
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        if double_sided:
            material.cull_mode = BaseMaterial3D.CULL_DISABLED
        _materials[key] = material
    return _materials[key]

static func _batch_static(parent: Node3D, recursive: bool) -> void:
    # Keep all animation roots, but encode ordinary solid colors into vertices.
    # A blue door, grey handle and black trim can share one shaded draw call.
    var originals: Array[Dictionary] = []
    _collect_meshes(parent,Transform3D.IDENTITY,recursive,originals)
    var groups: Dictionary = {}
    for entry in originals:
        var original: MeshInstance3D = entry.node
        for surface_index in range(original.mesh.get_surface_count()):
            var material: Material = original.material_override
            if material == null:
                material = original.mesh.surface_get_material(surface_index)
            if material == null:
                material = _material("ffffff")
            var source_mesh: Mesh = original.mesh
            var source_surface: int = surface_index
            var batch_material: Material = material
            if material is StandardMaterial3D and material.albedo_texture == null and not material.emission_enabled:
                source_mesh = _vertex_colored_surface(original.mesh,surface_index,material,entry.transform.basis)
                source_surface = 0
                batch_material = _vertex_material(material)
            var key: String = "%d/%d" % [batch_material.get_instance_id(),int(original.cast_shadow)]
            if not groups.has(key):
                var tool := SurfaceTool.new()
                tool.begin(Mesh.PRIMITIVE_TRIANGLES)
                groups[key] = {"tool":tool,"material":batch_material,"shadows":original.cast_shadow}
            var group: Dictionary = groups[key]
            var tool: SurfaceTool = group.tool
            tool.append_from(source_mesh,source_surface,entry.transform)
    for entry in originals:
        var original: MeshInstance3D = entry.node
        original.free()
    for key in groups:
        var group: Dictionary = groups[key]
        var tool: SurfaceTool = group.tool
        var merged := MeshInstance3D.new()
        merged.name = "MaterialBatch"
        merged.mesh = _share_merged_mesh(tool.commit())
        merged.material_override = group.material
        merged.cast_shadow = int(group.shadows)
        parent.add_child(merged)

static func _share_merged_mesh(mesh: ArrayMesh) -> ArrayMesh:
    # Geometry, including baked vertex colors, is identical across equal trucks.
    # Share the GPU resource so stationary models can be instanced by the yard
    # renderer without conflating their independent doors, wheels or load roots.
    var arrays: Array = mesh.surface_get_arrays(0)
    var key: int = hash(arrays)
    var bucket: Array = _merged_meshes.get(key,[])
    for candidate in bucket:
        var cached: ArrayMesh = candidate
        if cached.surface_get_arrays(0) == arrays:
            return cached
    bucket.append(mesh)
    _merged_meshes[key] = bucket
    return mesh

static func _vertex_colored_surface(mesh: Mesh, index: int, material: StandardMaterial3D, orientation: Basis = Basis.IDENTITY) -> ArrayMesh:
    var arrays: Array = mesh.surface_get_arrays(index)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var colors := PackedColorArray()
    if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
        colors = arrays[Mesh.ARRAY_COLOR]
    if colors.size() != vertices.size():
        colors.resize(vertices.size())
        colors.fill(Color.WHITE)
    var tint: Color = material.albedo_color
    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var painted: bool = bool(material.get_meta("category_paint",false))
    for vertex in range(colors.size()):
        colors[vertex] *= tint
        if painted and normals.size() == colors.size():
            var normal := (orientation*normals[vertex]).normalized()
            var shade := .76+.24*maxf(normal.y,0.0)
            colors[vertex] *= Color(shade,shade,shade,1.0)
    arrays[Mesh.ARRAY_COLOR] = colors
    var colored := ArrayMesh.new()
    colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    return colored

static func _vertex_material(source: StandardMaterial3D) -> StandardMaterial3D:
    var metal: bool = source.metallic > .10
    var roughness: float = .50 if metal else (.23 if source.roughness < .4 else .75)
    var painted := bool(source.get_meta("category_paint",false))
    var key: String = "vertex/%s/%.2f/%d/%d/%s" % [metal,roughness,int(source.shading_mode),int(source.cull_mode),painted]
    if not _materials.has(key):
        var material := StandardMaterial3D.new()
        material.albedo_color = Color.WHITE
        material.vertex_color_use_as_albedo = true
        material.vertex_color_is_srgb = true
        material.metallic = .45 if metal else 0.0
        material.roughness = roughness
        material.shading_mode = source.shading_mode
        material.cull_mode = source.cull_mode
        material.set_meta("category_paint",painted)
        _materials[key] = material
    return _materials[key]

static func _collect_meshes(parent: Node3D, accumulated: Transform3D, recursive: bool, output: Array[Dictionary]) -> void:
    for child in parent.get_children():
        if child is Node3D:
            var local: Transform3D = accumulated * child.transform
            if child is MeshInstance3D:
                output.append({"node":child,"transform":local})
            if recursive:
                _collect_meshes(child,local,true,output)
