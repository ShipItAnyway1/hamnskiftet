extends RefCounted

# Static scenery plus container handles for main's restrained background motion.
# Identical primitive/material pairs are merged into MultiMeshes at the end.
static func build() -> Node3D:
    var builder := SiteBuilder.new()
    var world: Node3D = builder.construct()
    set_spawn_bounds(world,Rect2i(0,0,SiteBuilder.L.WIDTH,SiteBuilder.L.HEIGHT))
    return world

static func set_spawn_bounds(world: Node3D, bounds: Rect2i) -> void:
    if not is_instance_valid(world):
        return
    var complete := Rect2i(0,0,SiteBuilder.L.WIDTH,SiteBuilder.L.HEIGHT)
    var active: Rect2i = bounds.intersection(complete)
    if active.size.x < 1 or active.size.y < 1:
        active = complete
    var old: Node = world.get_node_or_null("ActiveDepotSurface")
    if old != null:
        old.free()
    var builder := SiteBuilder.new()
    builder.root = Node3D.new()
    builder.root.name = "ActiveDepotSurface"
    builder._active_yard(active)
    builder._finish_batches()
    world.add_child(builder.root)
    world.set_meta("active_spawn_bounds",active)
    world.set_meta("active_yard_bounds",Rect2(SiteBuilder.L.YARD_BOUNDS.position+Vector2(active.position)*SiteBuilder.L.CELL,Vector2(active.size)*SiteBuilder.L.CELL))

static func build_obstacles(parent: Node3D, obstacles: Array) -> Dictionary:
    var nodes: Dictionary = {}
    for value in obstacles:
        if not value is Dictionary:
            continue
        var data: Dictionary = value
        var x: int = int(data.get("x",0))
        var y: int = int(data.get("y",0))
        var width: int = maxi(1,int(data.get("w",1)))
        var depth: int = maxi(1,int(data.get("h",1)))
        if x < 0 or y < 0 or x+width > SiteBuilder.L.WIDTH or y+depth > SiteBuilder.L.HEIGHT:
            push_warning("Obstacle outside depot grid was skipped")
            continue
        var id: Variant = data.get("id",nodes.size())
        var kind: String = str(data.get("kind","container"))
        var node := Node3D.new()
        node.name = "Obstacle_%s_%s" % [str(id),kind]
        node.position = Vector3(SiteBuilder.L.YARD_ORIGIN.x+(float(x)+float(width-1)*.5)*SiteBuilder.L.CELL,0,SiteBuilder.L.YARD_ORIGIN.y+(float(y)+float(depth-1)*.5)*SiteBuilder.L.CELL)
        node.set_meta("obstacle_id",id)
        node.set_meta("kind",kind)
        node.set_meta("movable",bool(data.get("movable",false)))
        node.set_meta("cell_bounds",Rect2i(x,y,width,depth))
        var size := Vector2(float(width)*SiteBuilder.L.CELL-.10,float(depth)*SiteBuilder.L.CELL-.10)
        var builder := SiteBuilder.new()
        builder.root = node
        if kind in ["boom","barrier"]:
            builder._boom_shape(size)
        else:
            builder._obstacle_shape(kind,size)
        builder._finish_batches()
        var body := StaticBody3D.new()
        body.name = "ObstacleHitBody"
        body.collision_layer = 4
        body.collision_mask = 0
        body.set_meta("obstacle_id",id)
        var shape := BoxShape3D.new()
        var height: float = .79 if kind == "gate" else 1.10
        shape.size = Vector3(size.x+.04,height,size.y+.04)
        var collider := CollisionShape3D.new()
        collider.shape = shape
        collider.position.y = height*.5
        body.add_child(collider)
        node.add_child(body)
        node.set_meta("body",body)
        parent.add_child(node)
        nodes[id] = node
        if kind in ["boom","barrier"]:
            node.set_meta("opens_after",int(data.get("opens_after",0)))
            var progress := Label3D.new()
            progress.name = "GateProgress"
            progress.position = Vector3(0,1.12,0)
            progress.font_size = 42
            progress.pixel_size = .009
            progress.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            progress.modulate = Color("ffe08a")
            progress.outline_size = 10
            progress.text = str(int(data.get("opens_after",0)))
            node.add_child(progress)
            node.set_meta("counter",progress)
            set_obstacle_open(node,bool(data.get("opened",false)),false)
    return nodes

static func set_obstacle_open(node: Node3D, opened: bool, animate := true) -> void:
    if not is_instance_valid(node) or not node.has_meta("armPivot"): return
    node.set_meta("opened",opened)
    node.set_meta("opening",opened and animate)
    var body: StaticBody3D = node.get_meta("body")
    body.collision_layer = 0 if opened else 4
    var pivot: Node3D = node.get_meta("armPivot")
    var old: Tween = node.get_meta("gate_tween") if node.has_meta("gate_tween") else null
    if old != null and old.is_valid(): old.kill()
    var angle := PI*.5 if opened else 0.0
    if animate and node.is_inside_tree():
        var tween := node.create_tween()
        tween.tween_property(pivot,"rotation:z",angle,.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        tween.tween_callback(func():
            if is_instance_valid(node): node.set_meta("opening",false)
        )
        node.set_meta("gate_tween",tween)
    else:
        pivot.rotation.z = angle
        node.set_meta("opening",false)
    var counter: Label3D = node.get_meta("counter",null)
    if counter != null: counter.visible = not opened


class SiteBuilder:
    extends RefCounted

    const L = preload("res://layout.gd")
    const TAU_F := PI*2.0
    const SEA := "205a78"
    const ASPHALT := "30343c"
    const ROAD := "4b515b"
    const PAINT := "ccefff"
    var root: Node3D
    var meshes: Dictionary = {}
    var materials: Dictionary = {}
    var batches: Dictionary = {}
    var container_movers: Array[Node3D] = []

    func _boom_shape(size: Vector2) -> void:
        # No broad raised plinth across the opened passage: only a compact
        # hinge housing at the edge and a physical arm that rotates upwards.
        var across_x := size.x >= size.y
        var width := maxf(size.x,size.y)
        var housing := Node3D.new()
        housing.name = "BarrierMechanism"
        housing.rotation.y = 0.0 if across_x else PI*.5
        root.add_child(housing)
        var base_builder := SiteBuilder.new()
        base_builder.root = housing
        base_builder._box(Vector3(-width*.5-.05,.28,0),Vector3(.04,.56,.14),"46515e")
        base_builder._box(Vector3(-width*.5-.05,.575,0),Vector3(.06,.07,.17),"f2bd3c")
        base_builder._finish_batches()
        var pivot := Node3D.new()
        pivot.name = "armPivot"
        pivot.position = Vector3(-width*.5-.05,.58,0)
        housing.add_child(pivot)
        root.set_meta("armPivot",pivot)
        var arm_builder := SiteBuilder.new()
        arm_builder.root = pivot
        arm_builder._box(Vector3(width*.5+.025,0,0),Vector3(width+.05,.08,.15),"f5e5c2")
        var count := maxi(2,ceili(width/.28))
        for index in range(count):
            var x := .12+float(index)*(width-.25)/float(count)
            arm_builder._box(Vector3(x,.044,0),Vector3(.13,.008,.155),"f58a3d")
        arm_builder._box(Vector3(width-.01,.085,0),Vector3(.10,.055,.10),"e54842")
        arm_builder._finish_batches()

    func _obstacle_shape(kind: String, size: Vector2) -> void:
        var half := size*.5
        if kind == "gate":
            _box(Vector3(0,.37,0),Vector3(size.x,.50,size.y),"344657")
            _box(Vector3(0,.633,0),Vector3(size.x,.025,size.y),"172e40")
            for side in [-1.0,1.0]:
                _box(Vector3(side*(half.x-.055),.38,0),Vector3(.09,.49,size.y),"d2e8ee")
                for z in [-half.y+.12,half.y-.12]:
                    _cylinder(Vector3(side*(half.x-.03),.08,z),.08,.045,"1c2d38",Vector3(0,0,PI*.5))
            # Large opposed roof chevrons say this is a sliding mechanism.
            for side in [-1.0,1.0]:
                var tip := Vector3(side*.24,.653,0)
                _segment(Vector3(side*.11,.653,-.15),tip,.065,.008,"edf9fd")
                _segment(Vector3(side*.11,.653,.15),tip,.065,.008,"edf9fd")
            # A real handle stands above the housing; no floating label.
            for z in [-.13,.13]:
                _box(Vector3(0,.69,z),Vector3(.045,.095,.045),"5dd0dc")
            _box(Vector3(0,.735,0),Vector3(.065,.05,.30),"9be6ed")
            return
        _box(Vector3(0,.54,0),Vector3(size.x,1.04,size.y),"697d8a")
        for side in [-1.0,1.0]:
            _box(Vector3(0,.08,side*(half.y-.025)),Vector3(size.x,.12,.05),"30495c")
            _box(Vector3(0,1.045,side*(half.y-.02)),Vector3(size.x,.06,.04),"bdcbd1")
            var ribs: int = maxi(3,roundi(size.x/.22))
            for rib in range(ribs):
                var at: float = lerpf(-half.x+.08,half.x-.08,float(rib)/float(ribs-1))
                _box(Vector3(at,.57,side*(half.y-.002)),Vector3(.045,.84,.012),"465f70")
        _box(Vector3(0,1.073,0),Vector3(size.x-.06,.024,size.y-.06),"344a5b")
        var stripe_count: int = maxi(3,roundi(size.x/.18))
        for stripe in range(stripe_count):
            var at: float = lerpf(-half.x+.13,half.x-.13,float(stripe)/float(stripe_count-1))
            _segment(Vector3(at-.05,1.089,-half.y+.09),Vector3(at+.05,1.089,half.y-.09),.075,.008,"e4ebee")

    func construct() -> Node3D:
        root = Node3D.new()
        root.name = "HarborDepotWorld"
        _ground()
        _parking_and_roads()
        _apron_identity()
        _exit_bridge()
        _cargo_loop()
        _loading_bays()
        _harbor_edges()
        _warehouses()
        _finish_batches()
        root.set_meta("visual_theme",{"board":"292d35","margin":ASPHALT,"apron":"505761","water":SEA,"edge":"526174"})
        root.set_meta("parking_bounds",L.YARD_BOUNDS)
        root.set_meta("west_road_bounds",Rect2(-L.LANE_X-L.LANE_WIDTH*.5,-4.8,L.LANE_WIDTH,27.0))
        root.set_meta("east_road_bounds",Rect2(L.LANE_X-L.LANE_WIDTH*.5,-4.8,L.LANE_WIDTH,27.0))
        root.set_meta("apron_bounds",Rect2(L.QUAY_BOUNDS.position.x,-4.8,L.QUAY_BOUNDS.size.x,4.3))
        root.set_meta("belt_center",Vector3(0,L.BELT_TOP,L.BELT_CENTER_Z))
        root.set_meta("belt_radii",Vector2(L.BELT_RADIUS_X,L.BELT_RADIUS_Z))
        root.set_meta("belt_slots",L.BELT_SLOTS)
        root.set_meta("exit_bridge_bounds",L.BRIDGE_BOUNDS)
        root.set_meta("exit_southbound_x",0.0)
        root.set_meta("container_movers",container_movers)
        return root

    func _material(color: String) -> StandardMaterial3D:
        if materials.has(color):
            return materials[color]
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(color).srgb_to_linear().lerp(Color(color),.15)
        material.roughness = .86
        material.metallic = .08 if color in ["c6d0ce","59717b","40535f"] else 0.0
        if color == "89d9c8":
            material.emission_enabled = true
            material.emission = Color(color).srgb_to_linear()
            material.emission_energy_multiplier = .45
        materials[color] = material
        return material

    func _mesh(kind: String) -> Mesh:
        if meshes.has(kind):
            return meshes[kind]
        var mesh: Mesh
        if kind == "box":
            var box := BoxMesh.new()
            box.size = Vector3.ONE
            mesh = box
        elif kind == "cylinder":
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = 1.0
            cylinder.bottom_radius = 1.0
            cylinder.height = 1.0
            cylinder.radial_segments = 12
            cylinder.rings = 1
            mesh = cylinder
        elif kind == "cone":
            var cone := CylinderMesh.new()
            cone.top_radius = .0
            cone.bottom_radius = 1.0
            cone.height = 1.0
            cone.radial_segments = 8
            cone.rings = 1
            mesh = cone
        elif kind == "rounded_pad":
            var outline := PackedVector2Array()
            var corners := [Vector2(.40,.40),Vector2(.40,-.40),Vector2(-.40,-.40),Vector2(-.40,.40)]
            for corner in range(4):
                for step in range(5):
                    var angle: float = float(corner)*PI*.5+float(step)*PI/8.0
                    outline.append(corners[corner]+Vector2(sin(angle),cos(angle))*.10)
            var surface := SurfaceTool.new()
            surface.begin(Mesh.PRIMITIVE_TRIANGLES)
            for index in range(outline.size()):
                var a: Vector2 = outline[index]
                var b: Vector2 = outline[(index+1)%outline.size()]
                var top := [Vector3(0,.5,0),Vector3(b.x,.5,b.y),Vector3(a.x,.5,a.y)]
                for vertex in top:
                    surface.set_normal(Vector3.UP)
                    surface.add_vertex(vertex)
                var normal := Vector3(a.y-b.y,0,b.x-a.x).normalized()
                var side := [Vector3(a.x,-.5,a.y),Vector3(a.x,.5,a.y),Vector3(b.x,.5,b.y),Vector3(a.x,-.5,a.y),Vector3(b.x,.5,b.y),Vector3(b.x,-.5,b.y)]
                for vertex in side:
                    surface.set_normal(normal)
                    surface.add_vertex(vertex)
            mesh = surface.commit()
        else:
            var sphere := SphereMesh.new()
            sphere.radius = 1.0
            sphere.height = 2.0
            sphere.radial_segments = 10
            sphere.rings = 5
            mesh = sphere
        meshes[kind] = mesh
        return mesh

    func _add(kind: String, color: String, position: Vector3, scale: Vector3, rotation := Vector3.ZERO) -> void:
        var key := kind+"_"+color
        if not batches.has(key):
            batches[key] = {"mesh":_mesh(kind),"material":_material(color),"transforms":[]}
        var transform := Transform3D(Basis.from_euler(rotation)*Basis.from_scale(scale),position)
        batches[key].transforms.append(transform)

    func _box(position: Vector3, size: Vector3, color: String, angle := 0.0) -> void:
        _add("box",color,position,size,Vector3(0,angle,0))

    func _cylinder(position: Vector3, radius: float, height: float, color: String, rotation := Vector3.ZERO) -> void:
        _add("cylinder",color,position,Vector3(radius,height,radius),rotation)

    func _sphere(position: Vector3, size: Vector3, color: String) -> void:
        _add("sphere",color,position,size)

    func _segment(a: Vector3, b: Vector3, width: float, height: float, color: String) -> void:
        var delta := b-a
        _box((a+b)*.5,Vector3(width,height,delta.length()),color,atan2(delta.x,delta.z))

    func _beam(a: Vector3, b: Vector3, radius: float, color: String) -> void:
        var delta := b-a
        var basis := Basis.IDENTITY
        if delta.length() > .001:
            var up := Vector3.FORWARD if absf(delta.normalized().dot(Vector3.UP)) > .98 else Vector3.UP
            basis = Basis.looking_at(delta.normalized(),up)*Basis.from_euler(Vector3(PI/2,0,0))
        var key := "cylinder_"+color
        if not batches.has(key):
            batches[key] = {"mesh":_mesh("cylinder"),"material":_material(color),"transforms":[]}
        batches[key].transforms.append(Transform3D(basis*Basis.from_scale(Vector3(radius,delta.length(),radius)),(a+b)*.5))

    func _finish_batches() -> void:
        for key in batches:
            var batch: Dictionary = batches[key]
            var multi := MultiMesh.new()
            multi.transform_format = MultiMesh.TRANSFORM_3D
            multi.mesh = batch.mesh
            multi.instance_count = batch.transforms.size()
            for index in range(batch.transforms.size()):
                multi.set_instance_transform(index,batch.transforms[index])
            var instance := MultiMeshInstance3D.new()
            instance.name = str(key)
            instance.multimesh = multi
            instance.set_meta("source_transforms",batch.transforms.duplicate())
            instance.material_override = batch.material
            root.add_child(instance)

    func _ground() -> void:
        _box(Vector3(0,-.56,0),Vector3(220,.10,220),SEA)
        var quay: Rect2 = L.QUAY_BOUNDS
        var middle := quay.get_center()
        _box(Vector3(middle.x,-.22,middle.y),Vector3(quay.size.x,.44,quay.size.y),"163859")
        _box(Vector3(middle.x,.018,middle.y),Vector3(quay.size.x-.12,.018,quay.size.y-.12),ROAD)
        var yard: Rect2 = L.YARD_BOUNDS
        _box(Vector3(yard.get_center().x,.028,yard.get_center().y),Vector3(yard.size.x,.016,yard.size.y),ASPHALT)
        _box(Vector3(0,.028,-10.9),Vector3(quay.size.x-.2,.016,12.8),"505761")
        for x in [quay.position.x+.04,quay.end.x-.04]:
            _box(Vector3(x,.055,middle.y),Vector3(.08,.11,quay.size.y),"72bcd1")
        _box(Vector3(0,.055,quay.position.y+.04),Vector3(quay.size.x,.11,.08),"72bcd1")
        # The lower quay edge has a flush opening for the one-way exit bridge.
        var bridge: Rect2 = L.BRIDGE_BOUNDS
        var edge_span := bridge.position.x-quay.position.x
        _box(Vector3(quay.position.x+edge_span*.5,.055,quay.end.y-.04),Vector3(edge_span,.11,.08),"72bcd1")
        _box(Vector3(-quay.position.x-edge_span*.5,.055,quay.end.y-.04),Vector3(edge_span,.11,.08),"72bcd1")
        for side in [-1.0,1.0]:
            for i in range(10):
                _box(Vector3(side*(15.0+float(i%3)*2.4),-.495,-17.0+float(i)*4.8),Vector3(1.1,.007,.045),"61c4d6",.14)
        # Quay fenders and waterline piles create a credible raised harbor edge.
        for z in [-15.0,-8.0,-1.0,6.0,13.0,19.0]:
            for x in [quay.position.x-.08,quay.end.x+.08]:
                _box(Vector3(x,-.17,z),Vector3(.16,.42,.62),"465d65")
                _cylinder(Vector3(x,-.5,z),.075,.8,"6d7977")

    func _parking_and_roads() -> void:
        var yard: Rect2 = L.YARD_BOUNDS
        # The full depot remains navigable. Its quiet boundary shows the site,
        # while the per-stage surface below shows the actual puzzle footprint.
        for x in [yard.position.x-.11,yard.end.x+.11]:
            _box(Vector3(x,.040,yard.get_center().y),Vector3(.07,.008,yard.size.y+.22),"4b91b0")
        for z in [yard.position.y-.11,yard.end.y+.11]:
            _box(Vector3(0,.040,z),Vector3(yard.size.x+.22,.008,.07),"4b91b0")
        # Exactly one narrow lane on each side: left north, right south.
        for side in [-1.0,1.0]:
            for edge in [-1.0,1.0]:
                var x: float = side*L.LANE_X+edge*(L.LANE_WIDTH*.5-.04)
                _box(Vector3(x,.041,8.45),Vector3(.025,.007,24.7),"89ccdf")
            for z in [1.6,6.8,12.0,17.2]:
                _road_arrow(side*L.LANE_X,z,side)
        # The bottom connection goes west; the center exit goes south.
        _road_arrow_x(-6.0,L.BOTTOM_Z,-1.0)
        _road_arrow_x(6.0,L.BOTTOM_Z,-1.0)
        for x in [-7.6,-4.2,4.2,7.6]:
            _box(Vector3(x,.042,L.BOTTOM_Z+1.22),Vector3(1.6,.007,.025),"89ccdf")

    func _active_yard(bounds: Rect2i) -> void:
        var active := Rect2(L.YARD_BOUNDS.position+Vector2(bounds.position)*L.CELL,Vector2(bounds.size)*L.CELL)
        var center: Vector2 = active.get_center()
        # Painted surface only: neither the active boundary nor its corners is
        # a wall. Trucks keep all original escape lanes and physics dimensions.
        _box(Vector3(center.x,.041,center.y),Vector3(active.size.x,.006,active.size.y),"292d35")
        for x_index in range(1,bounds.size.x):
            var x: float = active.position.x+float(x_index)*L.CELL
            _box(Vector3(x,.046,center.y),Vector3(.012,.002,active.size.y),"323740")
        for z_index in range(1,bounds.size.y):
            var z: float = active.position.y+float(z_index)*L.CELL
            _box(Vector3(center.x,.046,z),Vector3(active.size.x,.002,.012),"323740")
        for x in [active.position.x,active.end.x]:
            _box(Vector3(x,.049,center.y),Vector3(.045,.004,active.size.y),"526174")
        for z in [active.position.y,active.end.y]:
            _box(Vector3(center.x,.049,z),Vector3(active.size.x,.004,.045),"526174")
        for side in [-1.0,1.0]:
            for end in [-1.0,1.0]:
                var x: float = center.x+side*active.size.x*.5
                var z: float = center.y+end*active.size.y*.5
                _box(Vector3(x-side*.30,.052,z),Vector3(.66,.004,.11),"7c8eaa")
                _box(Vector3(x,.052,z-end*.30),Vector3(.11,.004,.66),"7c8eaa")

    func _road_arrow(x: float, z: float, direction: float) -> void:
        _box(Vector3(x,.052,z-direction*.13),Vector3(.075,.008,.62),PAINT)
        var tip := Vector3(x,.052,z+direction*.45)
        _segment(Vector3(x-.24,.052,z+direction*.13),tip,.065,.008,PAINT)
        _segment(Vector3(x+.24,.052,z+direction*.13),tip,.065,.008,PAINT)

    func _apron_identity() -> void:
        # All apron identity is paint: the whole shared turning area stays flat.
        var center_z := L.APRON_Z+.05
        for side in [-1.0,1.0]:
            for end in [-1.0,1.0]:
                _box(Vector3(side*10.23,.041,center_z+end*1.79),Vector3(.70,.004,.028),"71aecd")
                _box(Vector3(side*10.58,.041,center_z+end*1.49),Vector3(.028,.004,.60),"71aecd")
        # A subdued harbor stencil gives the empty apron a place identity,
        # without introducing another directional or gameplay instruction.
        var ink := "6babc9"
        var at := Vector3(0,.041,center_z-.12)
        for index in range(20):
            var a := TAU_F*float(index)/20.0
            var b := TAU_F*float(index+1)/20.0
            _segment(at+Vector3(cos(a)*.15,0,-.60+sin(a)*.15),at+Vector3(cos(b)*.15,0,-.60+sin(b)*.15),.062,.003,ink)
        _segment(at+Vector3(0,0,-.45),at+Vector3(0,0,.61),.09,.003,ink)
        _segment(at+Vector3(-.39,0,-.14),at+Vector3(.39,0,-.14),.085,.003,ink)
        for index in range(18):
            var a := PI*float(index)/18.0
            var b := PI*float(index+1)/18.0
            _segment(at+Vector3(cos(a)*.64,0,.12+sin(a)*.48),at+Vector3(cos(b)*.64,0,.12+sin(b)*.48),.09,.003,ink)
        for side in [-1.0,1.0]:
            _segment(at+Vector3(side*.64,0,.12),at+Vector3(side*.49,0,.02),.085,.003,ink)
            _segment(at+Vector3(side*.64,0,.12),at+Vector3(side*.72,0,.29),.085,.003,ink)

    func _exit_bridge() -> void:
        var bridge: Rect2 = L.BRIDGE_BOUNDS
        var middle := bridge.get_center()
        _box(Vector3(middle.x,-.20,middle.y),Vector3(bridge.size.x+.16,.40,bridge.size.y),"a8b2a5")
        _box(Vector3(middle.x,.025,middle.y),Vector3(bridge.size.x,.03,bridge.size.y),ROAD)
        for side in [-1.0,1.0]:
            var x: float = side*bridge.size.x*.5
            _box(Vector3(x-side*.12,.048,26.5),Vector3(.035,.008,7.8),PAINT)
            _box(Vector3(x,.53,26.5),Vector3(.075,.08,8.0),"c6d0ce")
            _box(Vector3(x,.25,26.5),Vector3(.055,.07,8.0),"c6d0ce")
            _box(Vector3(x,-.3,middle.y),Vector3(.18,.25,bridge.size.y),"657c7f")
            for z in [22.6,24.5,26.5,28.5,30.5]:
                _box(Vector3(x,.30,z),Vector3(.09,.60,.09),"6d8485")
        _road_arrow(0,24,1.0)
        _road_arrow(0,28,1.0)
        for z in [23.5,27.0,29.5]:
            for x in [-1.25,1.25]:
                _cylinder(Vector3(x,-.9,z),.16,1.6,"657a7e")

    func _road_arrow_x(x: float, z: float, direction: float) -> void:
        _box(Vector3(x-direction*.13,.052,z),Vector3(.62,.008,.075),PAINT)
        var tip := Vector3(x+direction*.45,.052,z)
        _segment(Vector3(x+direction*.13,.052,z-.24),tip,.065,.008,PAINT)
        _segment(Vector3(x+direction*.13,.052,z+.24),tip,.065,.008,PAINT)

    func _loop_point(slot: float, height: float, offset := .0) -> Vector3:
        var tangent: Vector3 = L.belt_tangent(slot)
        var normal := Vector3(tangent.z,0,-tangent.x)
        return L.belt_position(slot,height)+normal*offset

    func _ring_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, u0: float, u1: float, width: float) -> void:
        var vertices := [a,b,c,a,c,d]
        var uvs := [Vector2(u0,0),Vector2(u0,width),Vector2(u1,width),Vector2(u0,0),Vector2(u1,width),Vector2(u1,0)]
        for index in range(6):
            tool.set_normal(normal)
            tool.set_uv(uvs[index])
            tool.add_vertex(vertices[index])

    func _belt_ring(name_value: String, width: float, top: float, bottom: float, offset: float, material: Material) -> void:
        # One watertight ribbon, rather than separated boxes under floating pads.
        # UV.x is actual travel distance around the shared constant-speed path.
        var tool := SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        var count := 180
        for index in range(count):
            var a := float(index)*L.BELT_SLOTS/float(count)
            var b := float(index+1)*L.BELT_SLOTS/float(count)
            var i0 := _loop_point(a,top,offset-width*.5)
            var o0 := _loop_point(a,top,offset+width*.5)
            var i1 := _loop_point(b,top,offset-width*.5)
            var o1 := _loop_point(b,top,offset+width*.5)
            var bi0 := Vector3(i0.x,bottom,i0.z)
            var bo0 := Vector3(o0.x,bottom,o0.z)
            var bi1 := Vector3(i1.x,bottom,i1.z)
            var bo1 := Vector3(o1.x,bottom,o1.z)
            var tangent: Vector3 = L.belt_tangent((a+b)*.5)
            var normal := Vector3(tangent.z,0,-tangent.x)
            var u0 := float(index)*L.BELT_LENGTH/float(count)
            var u1 := float(index+1)*L.BELT_LENGTH/float(count)
            _ring_quad(tool,i0,o0,o1,i1,Vector3.UP,u0,u1,width)
            _ring_quad(tool,bo0,bi0,bi1,bo1,Vector3.DOWN,u0,u1,width)
            _ring_quad(tool,o0,bo0,bo1,o1,normal,u0,u1,top-bottom)
            _ring_quad(tool,bi0,i0,i1,bi1,-normal,u0,u1,top-bottom)
        var mesh := MeshInstance3D.new()
        mesh.name = name_value
        mesh.mesh = tool.commit()
        mesh.material_override = material
        root.add_child(mesh)

    func _rubber_material() -> ShaderMaterial:
        var shader := Shader.new()
        shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float travel = 0.0;
void fragment() {
    float seam = smoothstep(0.88,0.94,fract((UV.x-travel)/0.235));
    float edge = smoothstep(0.0,0.08,UV.y)*smoothstep(0.0,0.08,1.35-UV.y);
    float grain = sin(UV.x*158.0)*sin(UV.y*210.0)*0.004;
    ALBEDO = mix(vec3(0.030,0.043,0.052),vec3(0.075,0.096,0.110),edge)*(1.0-seam*0.56)+grain;
    ROUGHNESS = 0.89;
    METALLIC = 0.03;
}
"""
        var material := ShaderMaterial.new()
        material.shader = shader
        return material

    func _cargo_loop() -> void:
        var steel := _material("497898")
        steel.cull_mode = BaseMaterial3D.CULL_DISABLED
        var rubber := _rubber_material()
        root.set_meta("belt_material",rubber)
        root.set_meta("belt_top",L.BELT_TOP)
        root.set_meta("belt_path_length",L.BELT_LENGTH)
        _belt_ring("LoadBearingSteelChassis",1.72,.86,.52,0,steel)
        _belt_ring("ContinuousRubberSlats",1.35,L.BELT_TOP,.91,0,rubber)
        var segments := 144
        for index in range(segments):
            var a := float(index)*L.BELT_SLOTS/float(segments)
            var b := float(index+1)*L.BELT_SLOTS/float(segments)
            var middle := (a+b)*.5
            var p: Vector3 = L.belt_position(middle)
            var feeder_opening := absf(p.z-L.BELT_CENTER_Z) < .68 and absf(p.x) > L.BELT_STRAIGHT_HALF
            # Deep continuous side fascia and small stainless caps establish
            # a physical carrying machine, even at the high gameplay camera.
            for side in [-1.0,1.0]:
                if side > 0 and feeder_opening:
                    continue
                _segment(_loop_point(a,.79,side*.84),_loop_point(b,.79,side*.84),.10,.37,"315d7e")
                _segment(_loop_point(a,1.014,side*.765),_loop_point(b,1.014,side*.765),.055,.072,"99afbb")
                _segment(_loop_point(a,.62,side*.87),_loop_point(b,.62,side*.87),.06,.065,"253f55")
            if index%8 == 0 and not feeder_opening:
                var tangent: Vector3 = L.belt_tangent(middle)
                var yaw := atan2(tangent.x,tangent.z)
                _box(_loop_point(middle,.89,.903),Vector3(.024,.15,.26),"e0ae38",yaw)
            if index%6 == 0:
                # Visible cross rollers live beneath the load-bearing belt.
                _beam(_loop_point(a,.88,-.70),_loop_point(a,.88,.70),.075,"b3c3cc")
        # Paired bolted legs, cross braces and feet directly under the frame.
        for x in [-4.8,-1.6,1.6,4.8]:
            for z_side in [-1.0,1.0]:
                _conveyor_support(Vector3(x,0,L.BELT_CENTER_Z+z_side*L.BELT_RADIUS_Z),Vector3.RIGHT)
        for side in [-1.0,1.0]:
            _conveyor_support(Vector3(side*(L.BELT_RADIUS_X-.25),0,L.BELT_CENTER_Z),Vector3.FORWARD)
        # Drive motors and transmissions sit in the otherwise empty island.
        for side in [-1.0,1.0]:
            var motor := Vector3(side*4.8,.51,L.BELT_CENTER_Z+side*(L.BELT_RADIUS_Z-1.17))
            _box(motor+Vector3(0,-.39,0),Vector3(.85,.20,.62),"b4bec4")
            _box(motor,Vector3(.48,.55,.44),"33678a")
            _cylinder(motor+Vector3(side*.43,.06,0),.22,.52,"e5ae35",Vector3(0,0,PI/2))
            for fin in range(5):
                _box(motor+Vector3(side*(.28+float(fin)*.085),.06,0),Vector3(.022,.40,.40),"c3902d")
            _box(motor+Vector3(-side*.13,.32,0),Vector3(.16,.13,.24),"243d52")
            _box(motor+Vector3(-side*.13,.395,0),Vector3(.09,.025,.07),"89d9c8")
        for slot in range(L.BELT_SLOTS):
            var point := _loop_point(float(slot),1.06,.87)
            if absf(point.z-L.BELT_CENTER_Z) > .72:
                _box(point,Vector3(.085,.035,.10),"89d9c8",L.belt_yaw(slot))
        for gate in L.BAY_GATES:
            var point := _loop_point(float(gate),L.BELT_TOP+.008)
            _box(point,Vector3(1.24,.012,.045),"6ce1e8",L.belt_yaw(gate))
        _feeders()
        _service_island()

    func _service_island() -> void:
        # Everything remains inside the machine's empty island, well behind
        # the crane rails and completely outside the carrying belt itself.
        var z := L.BELT_CENTER_Z-.4
        _box(Vector3(0,.12,z),Vector3(8.6,.24,1.7),"536f83")
        _box(Vector3(0,.253,z),Vector3(8.44,.025,1.54),"7ab9cd")
        for side in [-1.0,1.0]:
            _box(Vector3(0,.28,z+side*.74),Vector3(8.38,.035,.035),"d4b25b")
            for x in [-3.9,-1.95,0.0,1.95,3.9]:
                _cylinder(Vector3(x,.282,z+side*.65),.028,.025,"61798b")
        # A low neutral cabinet bank reads as the conveyor's power/control
        # equipment, rather than a second set of colorful cargo pieces.
        var cabinet_z := z-.22
        _box(Vector3(0,.57,cabinet_z),Vector3(5.8,.59,.64),"73b9ce")
        _box(Vector3(0,.89,cabinet_z),Vector3(6.02,.065,.79),"365f7b")
        _box(Vector3(0,.31,cabinet_z+.325),Vector3(5.75,.10,.045),"496c83")
        for x in [-2.15,-.72,.72,2.15]:
            _box(Vector3(x,.585,cabinet_z+.326),Vector3(1.30,.45,.018),"4d9cba")
            _box(Vector3(x+.46,.59,cabinet_z+.345),Vector3(.036,.13,.025),"456579")
            _box(Vector3(x-.23,.58,cabinet_z+.342),Vector3(.58,.18,.018),"2d6c91")
            _box(Vector3(x+.45,.76,cabinet_z+.344),Vector3(.06,.045,.018),"89d9c8")
        # Covered cable duct connects the cabinets and existing drive motors.
        _box(Vector3(0,.33,z+.48),Vector3(7.6,.12,.15),"416781")
        _box(Vector3(0,.405,z+.48),Vector3(7.68,.035,.21),"8fa9b8")
        for x in [-3.25,-2.0,-.75,.75,2.0,3.25]:
            _box(Vector3(x,.43,z+.48),Vector3(.025,.018,.21),"4f728b")

    func _conveyor_support(at: Vector3, across: Vector3) -> void:
        var normal := Vector3(-across.z,0,across.x)
        for side in [-1.0,1.0]:
            var leg: Vector3 = at+normal*side*.57
            _box(leg+Vector3(0,.31,0),Vector3(.15,.62,.15),"45677d")
            _box(leg+Vector3(0,.055,0),Vector3(.39,.11,.33),"b7c2c7")
            for bolt in [-1.0,1.0]:
                _cylinder(leg+Vector3(bolt*.12,.116,0),.026,.023,"516674")
        _beam(at-normal*.58+Vector3(0,.22,0),at+normal*.58+Vector3(0,.56,0),.035,"6a899c")
        _beam(at-normal*.64+Vector3(0,.61,0),at+normal*.64+Vector3(0,.61,0),.055,"315d7e")

    func _feeders() -> void:
        for side in [-1.0,1.0]:
            var outer := L.QUAY_BOUNDS.end.x-.5
            var length := outer-L.BELT_RADIUS_X
            var center := (outer+L.BELT_RADIUS_X)*.5
            _box(Vector3(side*center,.69,L.BELT_CENTER_Z),Vector3(length,.34,1.72),"497898")
            _box(Vector3(side*center,.955,L.BELT_CENTER_Z),Vector3(length,.09,1.35),"273943")
            for edge in [-.765,.765]:
                _box(Vector3(side*center,1.014,L.BELT_CENTER_Z+edge),Vector3(length,.072,.055),"99afbb")
                _box(Vector3(side*center,.79,L.BELT_CENTER_Z+edge*1.10),Vector3(length,.37,.10),"315d7e")
            var slats := ceili(length/.235)
            for i in range(slats):
                var x := L.BELT_RADIUS_X+float(i)*length/float(slats)
                _box(Vector3(side*x,1.002,L.BELT_CENTER_Z),Vector3(.018,.004,1.32),"182b37")
            # Last exposed roller bridges the real inlet onto the main loop.
            _beam(Vector3(side*(L.BELT_RADIUS_X+.035),.92,L.BELT_CENTER_Z-.66),Vector3(side*(L.BELT_RADIUS_X+.035),.92,L.BELT_CENTER_Z+.66),.08,"b3c3cc")
            for x in [L.BELT_RADIUS_X+.45,outer-.3]:
                _conveyor_support(Vector3(side*x,0,L.BELT_CENTER_Z),Vector3.RIGHT)
            _box(Vector3(side*(outer-.18),.89,L.BELT_CENTER_Z+.94),Vector3(.22,.36,.23),"dfaa37")
            _box(Vector3(side*(outer-.18),1.08,L.BELT_CENTER_Z+.94),Vector3(.12,.025,.10),"89d9c8")

    func _loading_bays() -> void:
        for index in range(L.BAY_X.size()):
            var x: float = L.BAY_X[index]
            _add("rounded_pad","184a7b",Vector3(x,.035,L.DOCK_Z-.3),Vector3(2.15,.02,3.0))
            for side in [-1.0,1.0]:
                _box(Vector3(x+side*1.0,.052,L.DOCK_Z-.3),Vector3(.055,.008,2.5),"5bd4e1")
            _box(Vector3(x,.052,L.DOCK_Z-1.8),Vector3(1.52,.008,.055),"5bd4e1")
            _road_arrow(x,L.DOCK_Z+1.32,-1.0)

    func _mover_piece(groups: Dictionary, position: Vector3, size: Vector3, color: String) -> void:
        if not groups.has(color):
            groups[color] = []
        groups[color].append(Transform3D(Basis.from_scale(size),position))

    func _container_mover(position: Vector3, color: String, length := 2.5) -> void:
        var node := Node3D.new()
        node.name = "ThinContainer_%02d" % container_movers.size()
        node.position = position
        node.set_meta("base_position",position)
        node.set_meta("motion_max",.03)
        root.add_child(node)
        container_movers.append(node)
        var groups: Dictionary = {}
        _mover_piece(groups,Vector3(0,.37,0),Vector3(.34,.68,length),color)
        for rib in range(10):
            var z := -length*.45+float(rib)*length*.1
            for side in [-1.0,1.0]:
                _mover_piece(groups,Vector3(side*.178,.37,z),Vector3(.018,.62,.028),color)
        for side in [-1.0,1.0]:
            _mover_piece(groups,Vector3(0,.71,side*length*.48),Vector3(.36,.035,.035),"b5c0b0")
            _mover_piece(groups,Vector3(side*.10,.37,length*.505),Vector3(.017,.60,.023),"b5c0b0")
        var local_bounds := AABB()
        var first_piece := true
        for shade in groups:
            var transforms: Array = groups[shade]
            var multi := MultiMesh.new()
            multi.transform_format = MultiMesh.TRANSFORM_3D
            multi.mesh = _mesh("box")
            multi.instance_count = transforms.size()
            for index in range(transforms.size()):
                multi.set_instance_transform(index,transforms[index])
                var part: AABB = transforms[index]*AABB(-Vector3.ONE*.5,Vector3.ONE)
                local_bounds = part if first_piece else local_bounds.merge(part)
                first_piece = false
            var instance := MultiMeshInstance3D.new()
            instance.multimesh = multi
            instance.material_override = _material(shade)
            node.add_child(instance)
        node.set_meta("local_bounds",local_bounds)

    func _harbor_edges() -> void:
        for side in [-1.0,1.0]:
            _box(Vector3(side*11.27,.028,9.5),Vector3(.48,.012,17.5),"6a7976")
            for i in range(6):
                var z := 2.0+float(i)*3.0
                var color: String = ["b87956","507e87","b9a068","5f8272"][posmod(i+int(side),4)]
                # .374 maximum mesh width + .03 motion remains outside x=11.
                _container_mover(Vector3(side*11.25,.02,z),color,2.5)
            for index in range(14):
                var z := -16.3+float(index)*2.5
                if z < -5.55 or z > -.45:
                    _cylinder(Vector3(side*11.70,.30,z),.025,.58,"7b8d87")
                if index < 13 and (z+2.5 < -5.5 or z > -.5):
                    _box(Vector3(side*11.70,.55,z+1.25),Vector3(.025,.025,2.5),"a8b5a6")
            _lamp(Vector3(side*11.58,0,-6.9),side)
            _worker(Vector3(side*10.9,.03,-7.7),"e4b25a")

    func _lamp(position: Vector3, side: float) -> void:
        _box(position+Vector3(0,.08,0),Vector3(.36,.16,.36),"b5b8a6")
        _cylinder(position+Vector3(0,1.8,0),.035,3.6,"627a7e")
        _box(position+Vector3(-side*.32,3.57,0),Vector3(.69,.075,.075),"627a7e")
        _box(position+Vector3(-side*.62,3.5,0),Vector3(.28,.08,.20),"f1dba0")

    func _worker(position: Vector3, jacket: String) -> void:
        for side in [-1.0,1.0]:
            _box(position+Vector3(side*.055,.11,0),Vector3(.065,.22,.075),"435866")
        _cylinder(position+Vector3(0,.31,0),.095,.23,jacket)
        _box(position+Vector3(0,.34,.082),Vector3(.16,.025,.025),"f1dfaa")
        _sphere(position+Vector3(0,.50,0),Vector3(.075,.085,.075),"d8a983")
        _sphere(position+Vector3(0,.57,0),Vector3(.09,.045,.09),"f1c365")

    func _warehouses() -> void:
        for side in [-1.0,1.0]:
            var position := Vector3(side*8.25,0,-16.0)
            _box(position+Vector3(0,.85,0),Vector3(5.3,1.7,2.4),"72bdca")
            _box(position+Vector3(0,1.76,0),Vector3(5.5,.12,2.6),"23577d")
            for door in [-1.4,1.4]:
                _box(position+Vector3(door,.83,1.215),Vector3(1.45,1.66,.035),"2b668d")
                for k in range(5):
                    _box(position+Vector3(door,.23+float(k)*.27,1.242),Vector3(1.35,.025,.02),"4588a8")
                _box(position+Vector3(door,1.64,1.40),Vector3(1.8,.08,.4),"45a9bc")
            for x in [-2.35,0.0,2.35]:
                _box(position+Vector3(x,1.48,1.22),Vector3(.42,.22,.025),"a5e6e9")
        _box(Vector3(0,.75,-16.2),Vector3(4.7,1.5,2.2),"89c7ce")
        _box(Vector3(0,1.56,-16.2),Vector3(4.9,.12,2.4),"245674")
        for x in [-1.65,-.55,.55,1.65]:
            _box(Vector3(x,.96,-15.08),Vector3(.7,.58,.035),"2984a7")
            _box(Vector3(x,.96,-15.05),Vector3(.025,.58,.025),"a1e1e5")
        _box(Vector3(0,.085,-14.85),Vector3(4.8,.17,.5),"5eabc0")
