extends Node3D
## Self-contained helicopter rescue. Root decides legality, payment and rules.
## var fx = preload("res://rescue_effect.gd").new()
## await fx.play(effects, truck, target_local_yaw, generation_guard, should_pause)
## The controller lives at SceneTree.root while only its visuals live in effects,
## so resetting/freeing effects cannot strand the caller's awaited coroutine.
## It removes its visuals and queues itself for deletion on every exit path.

var duration_seconds: float = 2.9
var completed: bool = false
var progress: float = 0.0
var phase: String = "idle"
var _cancel_requested: bool = false
var _visuals: Node3D
var _helicopter: Node3D
var _rotor: Node3D
var _tail_rotor: Node3D
var _cable: MeshInstance3D
var _grip: Node3D
var _materials: Dictionary = {}
var _meshes: Dictionary = {}

func play(parent: Node3D, truck: Node3D, target_yaw: float, generation_guard: Callable, should_pause: Callable = Callable()) -> void:
    if not is_instance_valid(parent) or not parent.is_inside_tree() or not is_instance_valid(truck):
        queue_free()
        return
    var tree: SceneTree = parent.get_tree()
    if get_parent() == null:
        tree.root.add_child(self)
    elif get_parent() != tree.root:
        reparent(tree.root,true)
    name = "HelicopterRescueController"
    process_mode = Node.PROCESS_MODE_ALWAYS
    completed = false
    _cancel_requested = false
    progress = 0
    var initial: Transform3D = truck.transform
    var anchor: Vector3 = truck.global_position
    var start_yaw: float = truck.rotation.y
    var top: float = _truck_top(truck)
    var length: float = 2.0
    if truck.has_meta("model"):
        var model: Node3D = truck.get_meta("model")
        length = float(model.get_meta("length",2.0))
    _visuals = Node3D.new()
    _visuals.name = "HelicopterRescueVisuals"
    _visuals.set_meta("rescue_visuals",true)
    parent.add_child(_visuals)
    _build_helicopter()
    _grip = Node3D.new()
    _grip.name = "PhysicalLiftingSling"
    _visuals.add_child(_grip)
    _build_grip(top,length)
    _cable = _rod(_visuals,Vector3.ZERO,Vector3.UP,.018,"435262")
    _cable.visible = false
    if not _valid(parent,truck,generation_guard):
        _cleanup()
        queue_free()
        return
    _pose(truck,anchor,start_yaw,target_yaw,top,0)
    var elapsed: float = 0
    var previous_us: int = Time.get_ticks_usec()
    while elapsed < maxf(.1,duration_seconds):
        await tree.process_frame
        var now_us: int = Time.get_ticks_usec()
        var delta: float = minf(.05,maxf(0.0,float(now_us-previous_us)*.000001))
        previous_us = now_us
        if not _valid(parent,truck,generation_guard):
            break
        if _cancel_requested:
            # Explicit cancellation in the SAME generation may restore its pose.
            # An invalidated generation never gets another truck pose write.
            truck.transform = initial
            break
        if should_pause.is_valid() and bool(should_pause.call()):
            continue
        elapsed = minf(maxf(.1,duration_seconds),elapsed+delta)
        progress = elapsed/maxf(.1,duration_seconds)
        _pose(truck,anchor,start_yaw,target_yaw,top,progress)
    if _valid(parent,truck,generation_guard) and not _cancel_requested and progress >= 1.0:
        truck.transform = initial
        truck.rotation.y = target_yaw
        completed = true
        phase = "complete"
    else:
        phase = "cancelled"
    _cleanup()
    queue_free()

func cancel() -> void:
    _cancel_requested = true

func _valid(parent: Variant, truck: Variant, guard: Callable) -> bool:
    return is_instance_valid(parent) and parent.is_inside_tree() and is_instance_valid(truck) and truck.is_inside_tree() and is_instance_valid(_visuals) and guard.is_valid() and bool(guard.call())

func _ease(value: float) -> float:
    var t: float = clampf(value,0.0,1.0)
    return t*t*(3.0-2.0*t)

func _pose(truck: Node3D, anchor: Vector3, from_yaw: float, to_yaw: float, top: float, t: float) -> void:
    var lift: float = 0
    var yaw: float = from_yaw
    var hover: Vector3 = anchor+Vector3(0,5.6,0)
    var sling_offset: float = 0
    _grip.visible = t >= .18 and t < .91
    _cable.visible = _grip.visible
    if t < .18:
        phase = "fly_in"
        hover = (anchor+Vector3(-7,6.8,-3.0)).lerp(hover,_ease(t/.18))
    elif t < .30:
        phase = "hook"
        sling_offset = lerpf(3.45,0,_ease((t-.18)/.12))
    elif t < .50:
        phase = "lift"
        lift = 2.35*_ease((t-.30)/.20)
        hover.y += lift*.34
    elif t < .68:
        phase = "turn"
        lift = 2.35
        yaw = lerp_angle(from_yaw,to_yaw,_ease((t-.50)/.18))
        hover.y += lift*.34
    elif t < .85:
        phase = "lower"
        yaw = to_yaw
        lift = 2.35*(1.0-_ease((t-.68)/.17))
        hover.y += lift*.34
    elif t < .91:
        phase = "unhook"
        yaw = to_yaw
        sling_offset = 3.45*_ease((t-.85)/.06)
    else:
        phase = "fly_out"
        yaw = to_yaw
        hover = hover.lerp(anchor+Vector3(7,7.0,-4.0),_ease((t-.91)/.09))
    truck.global_position = anchor+Vector3.UP*lift
    truck.rotation.y = yaw
    _helicopter.global_position = hover
    _helicopter.rotation.y = .30
    _rotor.rotation.y = t*duration_seconds*46
    _tail_rotor.rotation.x = t*duration_seconds*62
    _grip.global_transform = truck.global_transform
    _grip.global_position += Vector3.UP*sling_offset
    var from: Vector3 = _helicopter.to_global(Vector3(0,-.52,0))
    var to: Vector3 = _grip.to_global(Vector3(0,top+.16,0))
    _set_rod(_cable,_visuals.to_local(from),_visuals.to_local(to),.018)
    set_meta("phase",phase)
    set_meta("progress",progress)

func _cleanup() -> void:
    if is_instance_valid(_visuals):
        _visuals.free()
    _visuals = null
    _helicopter = null
    _rotor = null
    _tail_rotor = null
    _cable = null
    _grip = null

func _exit_tree() -> void:
    _cleanup()

func _truck_top(truck: Node3D) -> float:
    var bounds: Array[AABB] = []
    _collect_bounds(truck,Transform3D.IDENTITY,bounds)
    var top: float = .9
    for box in bounds:
        top = maxf(top,box.end.y)
    return top

func _collect_bounds(node: Node3D, accumulated: Transform3D, output: Array[AABB]) -> void:
    for child in node.get_children():
        if child is Node3D:
            var local: Transform3D = accumulated*child.transform
            if child is MeshInstance3D:
                output.append(local*child.get_aabb())
            _collect_bounds(child,local,output)

func _build_grip(top: float, length: float) -> void:
    var span: float = minf(.74,length*.31)
    _box(_grip,Vector3(0,top+.12,0),Vector3(.97,.075,.17),"ffce3f")
    for side in [-1.0,1.0]:
        _box(_grip,Vector3(side*.405,top+.08,0),Vector3(.065,.075,span*2+.10),"f4bd35")
        for end in [-1.0,1.0]:
            _rod(_grip,Vector3(0,top+.16,0),Vector3(side*.405,top+.08,end*span),.018,"687587")
            _box(_grip,Vector3(side*.405,(top+.35)*.5,end*span),Vector3(.035,top-.35,.06),"243d55")
            _box(_grip,Vector3(side*.372,.34,end*span),Vector3(.10,.07,.12),"e7bd4c")
    _sphere(_grip,Vector3(0,top+.18,0),Vector3(.11,.12,.11),"dce8ec")

func _build_helicopter() -> void:
    _helicopter = Node3D.new()
    _helicopter.name = "OriginalHarborRescueHelicopter"
    _visuals.add_child(_helicopter)
    _sphere(_helicopter,Vector3(0,.05,-.30),Vector3(1.80,1.05,2.65),"ffce3f")
    _sphere(_helicopter,Vector3(0,.03,-1.02),Vector3(1.58,.85,1.24),"163e58")
    _sphere(_helicopter,Vector3(0,.16,-1.07),Vector3(1.45,.65,1.18),"65bbd6")
    _box(_helicopter,Vector3(0,.36,-1.14),Vector3(.055,.44,.90),"254556")
    _sphere(_helicopter,Vector3(0,-.32,-.20),Vector3(1.50,.32,2.10),"eef2dc")
    _rod(_helicopter,Vector3(0,.10,.62),Vector3(0,.45,2.57),.16,"f3bc32")
    _box(_helicopter,Vector3(0,.68,2.49),Vector3(.12,.88,.53),"ffcf3f")
    _box(_helicopter,Vector3(0,1.05,2.47),Vector3(.15,.15,.56),"20394d")
    _box(_helicopter,Vector3(0,.43,2.08),Vector3(1.24,.07,.37),"ffcf3f")
    for side in [-1.0,1.0]:
        _rod(_helicopter,Vector3(side*.52,-.16,-.73),Vector3(side*.76,-.54,-.73),.045,"3b5060")
        _rod(_helicopter,Vector3(side*.52,-.16,.43),Vector3(side*.76,-.54,.43),.045,"3b5060")
        _box(_helicopter,Vector3(side*.76,-.56,-.17),Vector3(.09,.09,2.38),"22394c")
        _box(_helicopter,Vector3(side*.90,.07,-.14),Vector3(.025,.35,.58),"f9f5da")
        _box(_helicopter,Vector3(side*.917,.08,-.14),Vector3(.012,.055,.39),"234b66")
        _box(_helicopter,Vector3(side*.917,.08,-.14),Vector3(.012,.23,.055),"234b66")
    _rod(_helicopter,Vector3(0,.55,-.13),Vector3(0,1.02,-.13),.11,"344d5d")
    _rotor = Node3D.new()
    _rotor.name = "SpinningMainRotor"
    _rotor.position = Vector3(0,1.05,-.13)
    _helicopter.add_child(_rotor)
    for angle in [0.0,PI*.5]:
        var blade: MeshInstance3D = _box(_rotor,Vector3.ZERO,Vector3(4.8,.055,.13),"203747")
        blade.rotation.y = angle
        for sign_value in [-1.0,1.0]:
            var tip: MeshInstance3D = _box(_rotor,Vector3(sign_value*2.22,0,0),Vector3(.32,.058,.14),"ffe075")
            tip.position = Basis(Vector3.UP,angle)*tip.position
            tip.rotation.y = angle
    _sphere(_rotor,Vector3(0,.03,0),Vector3(.25,.15,.25),"eaf2df")
    _tail_rotor = Node3D.new()
    _tail_rotor.name = "SpinningTailRotor"
    _tail_rotor.position = Vector3(.13,.72,2.56)
    _helicopter.add_child(_tail_rotor)
    _box(_tail_rotor,Vector3.ZERO,Vector3(.06,.80,.07),"f6f2d4")
    _box(_tail_rotor,Vector3.ZERO,Vector3(.06,.07,.80),"f6f2d4")

func _material(color: String) -> StandardMaterial3D:
    if not _materials.has(color):
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(color)
        material.roughness = .65
        _materials[color] = material
    return _materials[color]

func _box(parent: Node3D, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
    if not _meshes.has("box"):
        _meshes.box = BoxMesh.new()
    var node := MeshInstance3D.new()
    node.mesh = _meshes.box
    node.position = at
    node.scale = size
    node.material_override = _material(color)
    parent.add_child(node)
    return node

func _sphere(parent: Node3D, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
    if not _meshes.has("sphere"):
        var mesh := SphereMesh.new()
        mesh.radius = .5
        mesh.height = 1
        mesh.radial_segments = 16
        mesh.rings = 8
        _meshes.sphere = mesh
    var node := MeshInstance3D.new()
    node.mesh = _meshes.sphere
    node.position = at
    node.scale = size
    node.material_override = _material(color)
    parent.add_child(node)
    return node

func _rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: String) -> MeshInstance3D:
    if not _meshes.has("rod"):
        var mesh := CylinderMesh.new()
        mesh.top_radius = .5
        mesh.bottom_radius = .5
        mesh.height = 1
        mesh.radial_segments = 10
        _meshes.rod = mesh
    var node := MeshInstance3D.new()
    node.mesh = _meshes.rod
    node.material_override = _material(color)
    parent.add_child(node)
    _set_rod(node,from,to,radius)
    return node

func _set_rod(node: Node3D, from: Vector3, to: Vector3, radius: float) -> void:
    node.position = (from+to)*.5
    node.quaternion = Quaternion(Vector3.UP,(to-from).normalized())
    node.scale = Vector3(radius*2,maxf(.001,from.distance_to(to)),radius*2)
