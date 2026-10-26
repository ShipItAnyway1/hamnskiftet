extends RefCounted

# Small original SVG illustrations and icons, rasterized at their native size.
# No font glyphs, external images or texture-imposed Control minimum sizes.
static var _cache: Dictionary = {}

static func _texture(key: String, svg: String) -> Texture2D:
    if _cache.has(key):
        return _cache[key]
    var image := Image.new()
    var error: Error = image.load_svg_from_string(svg,2.0)
    if error != OK:
        push_error("Could not render UI asset "+key)
    var texture := ImageTexture.create_from_image(image)
    _cache[key] = texture
    return texture

static func icon(kind: String, color: String = "f3f9ff") -> Texture2D:
    var drawing := ""
    match kind:
        "undo": drawing = '<path d="M22 17H10V5M11 17c7-10 25-10 34 0 10 12 2 31-13 32H18"/>'
        "restart": drawing = '<path d="M47 19V7m0 12H35M46 18a21 21 0 1 0 5 23"/>'
        "cargo": drawing = '<path d="M10 20l22-10 22 10-22 11zM10 20v25l22 10 22-10V20M32 31v24M21 15l22 11v10"/><path d="M16 40l8 4"/>'
        "harbor": drawing = '<path d="M32 11v37M19 25h26M12 37c1 18 39 18 40 0M12 37l-4 9m4-9 9 4M52 37l4 9m-4-9-9 4"/><circle cx="32" cy="10" r="5"/>'
        "dock": drawing = '<path d="M9 51V14h40M16 14V7h33M39 15v19m-4 0a4 4 0 0 0 8 0M8 52h48M22 42h23v9H22z"/><path d="M23 25h6v8h-6z" fill="#'+color+'" stroke="none"/>'
        "music": drawing = '<path d="M24 44V16l29-6v28M24 24l29-6"/><ellipse cx="16" cy="46" rx="9" ry="7" fill="#'+color+'" stroke="none"/><ellipse cx="45" cy="40" rx="9" ry="7" fill="#'+color+'" stroke="none"/>'
        "sound": drawing = '<path d="M10 25h10l13-11v36L20 39H10zM42 22c7 5 7 15 0 20M49 15c13 10 13 24 0 34"/>'
        "fit": drawing = '<path d="M23 10H10v13M41 10h13v13M10 41v13h13M54 41v13H41"/><rect x="23" y="23" width="18" height="18" rx="4"/>'
        "play": drawing = '<path d="M22 12l29 20-29 20z" fill="#'+color+'" stroke="none"/>'
        "check": drawing = '<circle cx="32" cy="32" r="25" fill="#30cf9c" stroke="none"/><path d="M18 32l10 10 20-22" stroke="#073c5e" stroke-width="6"/>'
        "close": drawing = '<path d="M18 18l28 28M46 18L18 46"/>'
        "plus": drawing = '<path d="M14 32h36M32 14v36"/>'
        "minus": drawing = '<path d="M14 32h36"/>'
        "medal":
            drawing = '<path d="M13 4l12-2 12 23-12 9z" fill="#77aa9a" stroke="#e6f1d5" stroke-width="2"/><path d="M42 2l12 4-16 28-12-9z" fill="#42637c" stroke="#dce8e8" stroke-width="2"/><circle cx="32" cy="39" r="22" fill="#b9832c" stroke="none"/><circle cx="32" cy="36" r="22" fill="#f0c45e" stroke="#ffe9a3" stroke-width="2.5"/><circle cx="32" cy="36" r="16.8" stroke="#dca13b" stroke-width="1.6"/><circle cx="32" cy="28" r="3.2" stroke="#8c6528" stroke-width="2.3"/><path d="M32 32v15M25 36h14M20 40c1 10 23 10 24 0M20 40l-2 5m2-5 5 2M44 40l2 5m-2-5-5 2" stroke="#8c6528" stroke-width="2.3"/><path d="M18 27c2-4 5-6 9-7" stroke="#fff0bc" stroke-width="2.2"/>'
        "coin":
            drawing = '<circle cx="32" cy="34" r="25" fill="#cc8419" stroke="#b98125" stroke-width="2"/><circle cx="32" cy="29" r="25" fill="#ffd540" stroke="#fff2a3" stroke-width="3"/><circle cx="32" cy="29" r="18" stroke="#dca23b" stroke-width="2"/><path d="M32 15l5 9 10 2-8 7 2 10-9-5-9 5 2-10-8-7 10-2z" fill="#fff0b4" stroke="#dca23b" stroke-width="1.5"/>'
        "truck":
            drawing = '<rect x="3" y="4" width="58" height="56" rx="17" fill="#2588ed" stroke="none"/><path d="M11 43h42v6H11z" fill="#d5a243" stroke="none"/><rect x="11" y="20" width="25" height="23" rx="4" fill="#fff8e6" stroke="#20314b" stroke-width="2"/><path d="M36 26h9l8 9v8H36z" fill="#4b929f" stroke="#20314b" stroke-width="2"/><path d="M40 29h4l5 6h-9z" fill="#cce9e6" stroke="none"/><circle cx="20" cy="44" r="6" fill="#20314b" stroke="none"/><circle cx="45" cy="44" r="6" fill="#20314b" stroke="none"/><circle cx="20" cy="44" r="2.3" fill="#ffd540" stroke="none"/><circle cx="45" cy="44" r="2.3" fill="#ffd540" stroke="none"/><path d="M18 26h12M18 31h9" stroke="#e9d9b7" stroke-width="2"/>'
        _: drawing = '<circle cx="32" cy="32" r="17"/>'
    var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="none" stroke="#'+color+'" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">'+drawing+'</g></svg>'
    return _texture(kind+color,svg)

static func harbor_card(extra: int = 0) -> Texture2D:
    var crate_color: String = "f1bc62" if extra == 0 else "83bdac"
    var svg := '''<svg xmlns="http://www.w3.org/2000/svg" width="420" height="200" viewBox="0 0 420 200">
<defs><linearGradient id="sea" x2="0" y2="1"><stop stop-color="#26aaca"/><stop offset="1" stop-color="#176ab0"/></linearGradient></defs>
<rect x="4" y="12" width="412" height="176" rx="32" fill="#1d75ab"/>
<path d="M5 142h410v14c0 18-14 32-32 32H36c-18 0-31-14-31-32z" fill="url(#sea)"/>
<path d="M25 161h35m13 12h24m233-8h48m-90 10h27" stroke="#edf8ec" stroke-width="4" stroke-linecap="round"/>
<ellipse cx="208" cy="147" rx="135" ry="18" fill="#7faeb0" opacity=".24"/>
<path d="M66 133l235-15 45 24-237 16z" fill="#adc6d8"/>
<path d="M109 158v13l237-17v-12z" fill="#567d9c"/>
<path d="M66 133v13l43 25v-13z" fill="#82a6bf"/>
<path d="M94 128V47h152M102 47V34h145M230 49v43" fill="none" stroke="#123b66" stroke-width="9" stroke-linejoin="round"/>
<path d="M94 71l24-24m-24 48l45-48" fill="none" stroke="#5d99c1" stroke-width="4"/>
<path d="M219 91v7c0 14 23 14 23 0" fill="none" stroke="#ffcd3b" stroke-width="5" stroke-linecap="round"/>
SECOND_TRUCK
<rect x="127" y="94" width="104" height="47" rx="7" fill="#fff8e7" stroke="#45616c" stroke-width="2"/>
<path d="M232 110h37l25 23v10h-62z" fill="#4d9b94" stroke="#45616c" stroke-width="2"/>
<path d="M242 115h20l16 16h-36z" fill="#cfe9e4"/>
<rect x="137" y="103" width="10" height="30" rx="2" fill="#eddfc4"/><rect x="153" y="103" width="10" height="30" rx="2" fill="#eddfc4"/>
<circle cx="151" cy="143" r="11" fill="#263e51"/><circle cx="151" cy="143" r="5" fill="#d8c7a8"/><circle cx="269" cy="143" r="11" fill="#263e51"/><circle cx="269" cy="143" r="5" fill="#d8c7a8"/>
<rect x="300" y="101" width="44" height="35" rx="4" fill="#CRATE"/><path d="M320 103v30m-17-13h37" fill="none" stroke="#fff4d8" stroke-width="3" opacity=".75"/>
<circle cx="352" cy="54" r="16" fill="#ffe2a0"/><path d="M335 87h37m-50-12h13" stroke="#fffaf0" stroke-width="7" stroke-linecap="round"/>
</svg>'''
    if extra == 1:
        var second_truck := '''<rect x="238" y="69" width="70" height="35" rx="5" fill="#88b9ad" stroke="#45616c" stroke-width="2"/>
<path d="M308 81h23l18 16v9h-41z" fill="#d8a34e" stroke="#45616c" stroke-width="2"/>
<path d="M314 85h14l12 11h-26z" fill="#e0efdc"/>
<path d="M247 76v21m11-21v21m11-21v21" fill="none" stroke="#b7dbca" stroke-width="3"/>
<circle cx="252" cy="106" r="8" fill="#263e51"/><circle cx="252" cy="106" r="3.6" fill="#d8c7a8"/>
<circle cx="328" cy="106" r="8" fill="#263e51"/><circle cx="328" cy="106" r="3.6" fill="#d8c7a8"/>'''
        svg = svg.replace("SECOND_TRUCK",second_truck)
        svg = svg.replace('<rect x="300" y="101" width="44" height="35" rx="4" fill="#CRATE"/><path d="M320 103v30m-17-13h37" fill="none" stroke="#fff4d8" stroke-width="3" opacity=".75"/>',"")
        svg = svg.replace('M66 133l235-15 45 24-237 16z','M66 133l275-21 47 25-279 21z')
        svg = svg.replace('M109 158v13l237-17v-12z','M109 158v13l279-22v-12z')
    else:
        svg = svg.replace("SECOND_TRUCK","")
    return _texture("harbor"+str(extra),svg.replace("CRATE",crate_color))


static func menu_background() -> Texture2D:
    return _texture("menu_ocean",'''<svg xmlns="http://www.w3.org/2000/svg" width="900" height="1440" viewBox="0 0 900 1440">
<defs><linearGradient id="ocean" x2="0" y2="1"><stop stop-color="#124c89"/><stop offset=".53" stop-color="#103b6b"/><stop offset="1" stop-color="#071f42"/></linearGradient><radialGradient id="glow"><stop stop-color="#46a8df" stop-opacity=".27"/><stop offset="1" stop-color="#46a8df" stop-opacity="0"/></radialGradient></defs>
<rect width="900" height="1440" fill="url(#ocean)"/><ellipse cx="760" cy="120" rx="570" ry="510" fill="url(#glow)"/>
<g fill="none" stroke="#4a9bcd" stroke-width="2" opacity=".13"><circle cx="25" cy="410" r="190"/><circle cx="25" cy="410" r="220"/><circle cx="875" cy="1100" r="190"/><circle cx="875" cy="1100" r="220"/></g>
<path d="M0 1215q225-70 450 0t450 0v225H0z" fill="#0a2b54" opacity=".55"/>
</svg>''')

static func _vector_upgrade_illustration(kind: String) -> Texture2D:
    var drawing := ""
    match kind:
        "fleet":
            drawing = '''<path d="M16 80l75-12 53 20-78 16z" fill="#0c2f60"/><path d="M27 41l54-9 39 14-54 10z" fill="#75e1ff"/><path d="M27 41v39l39 17V56z" fill="#22a6e0"/><path d="M66 56l54-10v39L66 97z" fill="#1680c6"/><path d="M120 61l22 8 14 18-36 8z" fill="#ffd948"/><path d="M120 61v34l-13 3V69z" fill="#efae20"/><path d="M128 69l11 4 8 10-19 4z" fill="#d5f8ff"/><path d="M35 51v24m10-20v25m10-21v25M76 64l32-6m-32 15 32-6" stroke="#85ddf9" stroke-width="3"/><g fill="#12345c" stroke="#072246" stroke-width="3"><ellipse cx="52" cy="88" rx="9" ry="12"/><ellipse cx="120" cy="96" rx="9" ry="12"/><ellipse cx="140" cy="92" rx="8" ry="11"/></g><g fill="#bad8e4"><ellipse cx="52" cy="88" rx="4" ry="6"/><ellipse cx="120" cy="96" rx="4" ry="6"/><ellipse cx="140" cy="92" rx="3" ry="5"/></g>'''
        "loader":
            drawing = '''<path d="M18 100l76-18 55 18-75 18z" fill="#173969"/><path d="M39 34v64m91-68v62M28 32l98-16 22 9-99 18z" fill="#ffdc59" stroke="#ffdc59" stroke-width="7" stroke-linejoin="round"/><path d="M39 34l8 9v62l-8-7zM130 30l8 5v61l-8-4z" fill="#d99120"/><path d="M29 32l98-16m-88 45 8-6m-8 24 8-6" stroke="#fff4a3" stroke-width="3"/><path d="M88 34v32" stroke="#17345c" stroke-width="4"/><path d="M81 64v9c0 14 20 14 20 0" fill="none" stroke="#ffdc59" stroke-width="5"/><path d="M67 81l28-6 22 10-30 8z" fill="#c8dff5"/><path d="M67 81v21l20 9V93z" fill="#77abda"/><path d="M87 93l30-8v21l-30 5z" fill="#548ac4"/>'''
        "belt":
            drawing = '''<ellipse cx="88" cy="90" rx="72" ry="23" fill="#123c67"/><path d="M26 67v25m42-8v25m72-44v25" stroke="#87c7e1" stroke-width="6"/><path d="M32 53c-24 6-19 30 9 33l73-10c39-6 39-33 11-36z" fill="#163753" stroke="#60c4e8" stroke-width="9"/><path d="M34 51c-22 5-17 21 7 23l75-10c25-4 26-17 9-18z" fill="none" stroke="#405c75" stroke-width="12"/><path d="M39 56l4 16m15-19 4 16m16-18 4 16m17-19 4 16m17-18 4 13" stroke="#88a3b4" stroke-width="2"/><path d="M79 24l22-5 20 9-22 5z" fill="#ffe591"/><path d="M79 24v24l20 9V33z" fill="#e7a73b"/><path d="M99 33l22-5v24l-22 5z" fill="#f5c351"/><path d="M88 27l21-4m-20 7v18" stroke="#fff0b8" stroke-width="3"/>'''
        "warehouse":
            drawing = '''<path d="M17 82l82-19 52 23-83 25z" fill="#442553"/><path d="M24 48l64-21 55 24-65 22z" fill="#d9d7ff"/><path d="M24 48v39l54 25V73z" fill="#bc75bc"/><path d="M78 73l65-22v37l-65 24z" fill="#874f9a"/><path d="M19 49l67-30 65 29-9 9-55-24-59 24z" fill="#6650a5"/><path d="M89 76l33-12v28L89 104z" fill="#362c67"/><path d="M37 62v15m13-9v15m14-9v15" stroke="#f5c9e7" stroke-width="6"/><path d="M105 91l24-5 19 8-24 6z" fill="#ffdf76"/><path d="M105 91v20l19 8v-19z" fill="#e6a62e"/><path d="M124 100l24-6v20l-24 5z" fill="#f4bf43"/>'''
        "parking":
            drawing = '''<path d="M13 63l88-23 60 29-91 28z" fill="#427c88" stroke="#9de1c8" stroke-width="3"/><path d="M13 63v18l57 29V97z" fill="#246072"/><path d="M70 97l91-28v18l-91 27z" fill="#174f67"/><path d="M34 66l40 20m-13-28 40 20m-13-28 40 20" stroke="#e0f8d5" stroke-width="3"/><path d="M75 47l25-7 23 11-26 7z" fill="#acffb4"/><path d="M75 47v19l22 11V58z" fill="#34c78f"/><path d="M97 58l26-7v20l-26 6z" fill="#1eaa80"/><path d="M120 63l19 9v11l-19 6z" fill="#ffe073"/><path d="M125 65l12 6 7 8-19 5z" fill="#d2f9ff"/><ellipse cx="93" cy="77" rx="6" ry="8" fill="#143a59"/><ellipse cx="130" cy="86" rx="6" ry="8" fill="#143a59"/>'''
        _:
            drawing = '''<path d="M28 90l50-13 59 20-54 14z" fill="#243567"/><rect x="38" y="45" width="40" height="51" rx="9" fill="#ff9a2e"/><ellipse cx="58" cy="45" rx="20" ry="7" fill="#ffd65a"/><path d="M40 54h36m-36 31h36" stroke="#b95c25" stroke-width="4"/><path d="M58 59l11 12-11 13-11-13z" fill="#513249"/><path d="M95 53c-2-13 17-21 17-31 13 15 24 26 24 40 0 28-40 29-41-9z" fill="#ff4d9a"/><path d="M103 59c0 15 16 19 23 7" fill="none" stroke="#ffb8dc" stroke-width="5" stroke-linecap="round"/>'''
    var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="176" height="128" viewBox="0 0 176 128"><defs><radialGradient id="glow"><stop stop-color="#bceeff" stop-opacity=".26"/><stop offset="1" stop-color="#bceeff" stop-opacity="0"/></radialGradient></defs><ellipse cx="88" cy="67" rx="85" ry="59" fill="url(#glow)"/>'+drawing+'</svg>'
    return _texture("upgrade_"+kind,svg)


static func upgrade_illustration(kind: String) -> Texture2D:
    # Render the actual native toy kit once, rather than enlarging flat symbols.
    # The raster fallback keeps data-only/headless checks independent of a GPU.
    var key := "upgrade_3d_"+kind
    if _cache.has(key):
        return _cache[key]
    var path := "res://assets/art/upgrade-"+kind+".png"
    if FileAccess.file_exists(path):
        var baked := Image.load_from_file(ProjectSettings.globalize_path(path))
        if not baked.is_empty():
            var texture := ImageTexture.create_from_image(baked)
            _cache[key] = texture
            return texture
    elif ResourceLoader.exists(path):
        var texture: Texture2D = load(path)
        _cache[key] = texture
        return texture
    if DisplayServer.get_name() == "headless":
        return _vector_upgrade_illustration("fleet" if kind.begins_with("fleet_") else kind)
    var viewport := SubViewport.new()
    viewport.name = "UpgradeIllustration_"+kind
    viewport.size = Vector2i(320,280)
    viewport.transparent_bg = true
    viewport.own_world_3d = true
    viewport.msaa_3d = Viewport.MSAA_4X
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
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
    camera.size = 3.35
    camera.position = Vector3(4.5,3.5,-5.5)
    stage.add_child(camera)
    camera.look_at_from_position(camera.position,Vector3(0,.55,0))
    camera.current = true
    _miniature(stage,kind)
    var texture: Texture2D = viewport.get_texture()
    _cache[key] = texture
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.add_child.call_deferred(viewport)
    return texture

static func _miniature(parent: Node3D, kind: String) -> void:
    var kit = preload("res://models.gd")
    var g = preload("res://geometry.gd")
    g.cylinder(parent,Vector3(0,-.065,0),1.55,.13,"386a93")
    g.cylinder(parent,Vector3(0,.004,0),1.48,.025,"7baac2")
    if kind.begins_with("fleet_"):
        var resource := kind.trim_prefix("fleet_")
        var typed_truck: Node3D = kit.truck(resource,2.56,0)
        kit.set_load_fraction(typed_truck,1.0)
        typed_truck.rotation.y = .40
        parent.add_child(typed_truck)
        return
    match kind:
        "fleet":
            var truck: Node3D = kit.truck("frys",2.6,0)
            kit.set_load_fraction(truck,1.0)
            truck.rotation.y = .40
            parent.add_child(truck)
            for i in range(3):
                g.box(parent,Vector3(-1.1,.028,-.65+float(i)*.46),Vector3(.13,.012,.20),"d4e8e6")
        "loader":
            for x in [-1.08,1.08]:
                for z in [-.66,.66]:
                    g.box(parent,Vector3(x,.08,z),Vector3(.37,.16,.34),"24436a")
                    g.box(parent,Vector3(x,.95,z),Vector3(.13,1.82,.13),"efaf26")
                    g.box(parent,Vector3(x,1.83,0),Vector3(.18,.17,1.65),"ffda52")
                    g.box(parent,Vector3(x,1.94,0),Vector3(.06,.035,1.69),"fff2a6")
            g.box(parent,Vector3(0,1.96,0),Vector3(2.5,.19,.35),"ffca3d")
            g.box(parent,Vector3(.15,2.11,0),Vector3(.45,.18,.45),"315d85")
            g.box(parent,Vector3(.15,1.52,0),Vector3(.035,.81,.035),"263d5a")
            g.box(parent,Vector3(.15,1.08,0),Vector3(.49,.09,.47),"f4b735")
            var crate: Node3D = kit.cargo("kyl",1.15)
            crate.position = Vector3(.15,.33,0)
            parent.add_child(crate)
        "belt":
            for i in range(44):
                var a := TAU*float(i)/44.0
                var at := Vector3(cos(a)*1.05,.46,sin(a)*.66)
                var normal := Vector3(-sin(a)*1.05,0,cos(a)*.66).normalized()
                var beam: MeshInstance3D = g.box(parent,at,Vector3(.53,.17,.20),"234460")
                beam.rotation.y = atan2(normal.x,normal.z)
                var slat: MeshInstance3D = g.box(parent,at+Vector3(0,.105,0),Vector3(.46,.035,.13),"5a768b")
                slat.rotation.y = beam.rotation.y
                for side in [-1.0,1.0]:
                    var rail: MeshInstance3D = g.box(parent,at+Vector3(normal.z,0,-normal.x)*side*.28,Vector3(.035,.22,.20),"4aa3cc")
                    rail.rotation.y = beam.rotation.y
            for x in [-.75,.75]:
                for z in [-.48,.48]:
                    g.box(parent,Vector3(x,.21,z),Vector3(.12,.42,.12),"274b6c")
                    g.box(parent,Vector3(x,.04,z),Vector3(.25,.08,.24),"ccd9db")
            var crate: Node3D = kit.cargo("adr",.95)
            crate.position = Vector3(.75,.59,-.44)
            parent.add_child(crate)
        "warehouse":
            g.box(parent,Vector3(0,.54,.15),Vector3(2.30,1.08,1.55),"dbe2df")
            g.box(parent,Vector3(0,1.13,.15),Vector3(2.47,.14,1.73),"365c86")
            g.box(parent,Vector3(.23,.47,-.64),Vector3(1.03,.94,.035),"345877")
            for x in [-.91,-.67,.87]:
                g.box(parent,Vector3(x,.76,-.655),Vector3(.16,.27,.04),"77cce9")
            for i in range(6):
                g.box(parent,Vector3(.23,.12+float(i)*.14,-.669),Vector3(.97,.025,.018),"6b96ac")
            g.box(parent,Vector3(.25,.97,-.79),Vector3(1.40,.08,.36),"f3bf3b")
            var crate: Node3D = kit.cargo("kyl",.9)
            crate.position = Vector3(-.80,0,-.93)
            parent.add_child(crate)
        "parking":
            g.box(parent,Vector3(0,.032,0),Vector3(2.45,.06,2.35),"3d647e")
            for x in [-1.05,-.35,.35,1.05]:
                g.box(parent,Vector3(x,.069,0),Vector3(.025,.012,2.15),"d8efeb")
            for i in range(3):
                var truck: Node3D = kit.truck(["kyl","frys","schakt"][i],1.66,0)
                truck.scale = Vector3.ONE*.70
                truck.position = Vector3(-.70+float(i)*.70,.071,.12)
                parent.add_child(truck)
        _:
            var adr: Node3D = kit.cargo("adr",1.85)
            adr.position = Vector3(-.63,.025,.22)
            parent.add_child(adr)
            var fuel: Node3D = kit.cargo("bransle",1.75)
            fuel.position = Vector3(.62,.025,-.10)
            parent.add_child(fuel)
            g.box(parent,Vector3(0,.045,.86),Vector3(1.5,.055,.075),"ffcf45")
