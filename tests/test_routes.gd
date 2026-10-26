extends SceneTree

# Independent physical clearance checks over the actual production drive tween.
# Run headless: --path truck-depot --script tests/test_routes.gd
# Static world geometry is inspected; no game UI, saved progress or audio.
const Rules = preload("res://puzzle.gd")
const Models = preload("res://models.gd")
const World = preload("res://world.gd")
const L = preload("res://layout.gd")
const SPACING := .035
const ANGLE_SPACING := .025

class DriveHarness:
    extends "res://main.gd"
    var captured: Tween
    func _ready() -> void:
        pass
    func _process(_delta: float) -> void:
        pass
    func _tween() -> Tween:
        captured = create_tween()
        captured.pause()
        return captured

var driver
var templates: Dictionary = {}
var failures: Array[Dictionary] = []
var reported: Dictionary = {}
var route_count := 0
var pose_count := 0
var wheel_count := 0
var yard_obstacle_cache: Dictionary = {}
var dock_bound := Rect2()
var dock_bound_ready := false
var strip_obstacles: Array[Dictionary] = []

func _initialize() -> void:
    call_deferred("_run")

func _template(kind: String, cells: int, loaded: bool) -> Dictionary:
    var key := "%s:%d:%s" % [kind,cells,loaded]
    if templates.has(key):
        return templates[key]
    var model: Node3D = Models.truck(kind,float(cells)*L.CELL-.14,0)
    Models.set_load_fraction(model,1.0 if loaded else 0.0)
    var trailer: Node3D = model.get_meta("trailer")
    var body_points := PackedVector2Array()
    var trailer_points := PackedVector2Array()
    _collect_mesh_points(model,Transform3D.IDENTITY,body_points,trailer)
    _collect_mesh_points(trailer,Transform3D.IDENTITY,trailer_points,null)
    var wheels := PackedVector2Array()
    for wheel in model.get_meta("wheels"):
        # Outer edges of the actual 0.107-wide tire, on each actual axle.
        var at: Vector3 = wheel.position
        wheels.append(Vector2(at.x-.0535,at.z))
        wheels.append(Vector2(at.x+.0535,at.z))
    var data := {"body":Geometry2D.convex_hull(body_points),
        "trailer":Geometry2D.convex_hull(trailer_points),"wheels":wheels}
    templates[key] = data
    model.free()
    return data

func _collect_mesh_points(parent: Node3D, transform: Transform3D, points: PackedVector2Array, excluded: Node3D) -> void:
    for child in parent.get_children():
        if not child is Node3D or child == excluded or not child.visible:
            continue
        var local: Transform3D = transform*child.transform
        if child is MeshInstance3D and child.mesh:
            var box: AABB = child.get_aabb()
            for corner in range(8):
                var point: Vector3 = local*box.get_endpoint(corner)
                points.append(Vector2(point.x,point.z))
        _collect_mesh_points(child,local,points,excluded)

func _yard_position(truck: Dictionary) -> Vector3:
    return L.yard_position(truck)

func _transform(point: Vector2, position: Vector3, yaw: float) -> Vector2:
    var rotated := Basis(Vector3.UP,yaw)*Vector3(point.x,0,point.y)
    return Vector2(position.x+rotated.x,position.z+rotated.z)

func _footprint(data: Dictionary, pose: Dictionary) -> PackedVector2Array:
    var points := PackedVector2Array()
    for local in data.body:
        points.append(_transform(local,pose.position,pose.yaw))
    for local in data.trailer:
        points.append(_transform(local,pose.position,float(pose.yaw)+float(pose.trailer)))
    return Geometry2D.convex_hull(points)

func _bounds(points: PackedVector2Array) -> Rect2:
    var result := Rect2(points[0],Vector2.ZERO)
    for point in points:
        result = result.expand(point)
    return result

func _obstacles(state: Dictionary, moving_id: int, target_bay: int) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var key: int = state.trucks.size()
    if not yard_obstacle_cache.has(key):
        var yard: Array[Dictionary] = []
        for other in state.trucks:
            var shape := _template(str(other.type),int(other.len),false)
            var pose := {"position":_yard_position(other),"yaw":-float(other.dir)*PI/2.0,"trailer":0.0}
            yard.append({"id":int(other.id),"name":"yard:%d" % int(other.id),"rect":_bounds(_footprint(shape,pose))})
        yard_obstacle_cache[key] = yard
    for obstacle in yard_obstacle_cache[key]:
        if int(obstacle.id) != moving_id:
            result.append(obstacle)
    # Other loading places may hold ANY full-length, fully loaded truck. Use
    # the union of the six real model AABBs, rather than a center-point test.
    if not dock_bound_ready:
        var first := true
        for kind in Rules.TYPES:
            var shape := _template(kind,3,true)
            var local := _bounds(_footprint(shape,{"position":Vector3.ZERO,"yaw":0.0,"trailer":0.0}))
            dock_bound = local if first else dock_bound.merge(local)
            first = false
        dock_bound_ready = true
    for bay in range(L.BAY_X.size()):
        if bay != target_bay:
            result.append({"name":"dock:%d" % bay,"rect":Rect2(dock_bound.position+Vector2(L.BAY_X[bay],L.DOCK_Z),dock_bound.size)})
    result.append_array(strip_obstacles)
    return result

func _overlaps(polygon: PackedVector2Array, obstacle: Rect2) -> bool:
    var axes := PackedVector2Array([Vector2.RIGHT,Vector2.DOWN])
    for index in range(polygon.size()-1):
        var edge := polygon[index+1]-polygon[index]
        if edge.length_squared() > .000001:
            axes.append(Vector2(-edge.y,edge.x).normalized())
    var center := obstacle.get_center()
    var half := obstacle.size*.5
    for axis in axes:
        var minimum := INF
        var maximum := -INF
        for point in polygon:
            var projection: float = point.dot(axis)
            minimum = minf(minimum,projection)
            maximum = maxf(maximum,projection)
        var middle: float = center.dot(axis)
        var radius := absf(axis.x)*half.x+absf(axis.y)*half.y
        # Ignore sub-centimeter touching/trim. Larger penetration is a failure.
        if maximum <= middle-radius+.01 or minimum >= middle+radius-.01:
            return false
    return true

func _dry(point: Vector2) -> bool:
    return L.QUAY_BOUNDS.grow(.001).has_point(point) or L.BRIDGE_BOUNDS.grow(.001).has_point(point)

func _fail(case_name: String, kind: String, pose: Dictionary, detail: String) -> void:
    var key := case_name+":"+kind+":"+detail
    if reported.has(key):
        return
    reported[key] = true
    failures.append({"case":case_name,"kind":kind,"position":pose.position,
        "yaw_degrees":rad_to_deg(float(pose.yaw)),"trailer_degrees":rad_to_deg(float(pose.trailer)),"detail":detail})

func _inspect(data: Dictionary, pose: Dictionary, obstacles: Array[Dictionary], case_name: String) -> void:
    pose_count += 1
    var polygon := _footprint(data,pose)
    var bounds := _bounds(polygon)
    for obstacle in obstacles:
        if bounds.intersects(obstacle.rect) and _overlaps(polygon,obstacle.rect):
            _fail(case_name,"swept_body_collision",pose,str(obstacle.name))
    for point in polygon:
        if not _dry(point):
            _fail(case_name,"body_outside_asphalt",pose,"paved quay or exit bridge")
            break
    for local in data.wheels:
        wheel_count += 1
        if not _dry(_transform(local,pose.position,pose.yaw)):
            _fail(case_name,"wheel_outside_asphalt",pose,"actual axle/tire track")
            break

func _pose(node: Node3D) -> Dictionary:
    var model: Node3D = node.get_meta("model")
    var trailer: Node3D = model.get_meta("trailer")
    return {"position":node.position,"yaw":node.rotation.y,"trailer":trailer.rotation.y}

func _inspect_sweep(data: Dictionary, before: Dictionary, after: Dictionary, obstacles: Array[Dictionary], case_name: String) -> void:
    var translation: float = before.position.distance_to(after.position)
    var rotation: float = absf(angle_difference(float(before.yaw),float(after.yaw)))
    var trailer_rotation: float = absf(angle_difference(float(before.trailer),float(after.trailer)))
    var count := maxi(1,ceili(maxf(translation/SPACING,maxf(rotation,trailer_rotation)/ANGLE_SPACING)))
    for index in range(1,count+1):
        var fraction := float(index)/float(count)
        var pose := {"position":before.position.lerp(after.position,fraction),
            "yaw":lerp_angle(float(before.yaw),float(after.yaw),fraction),
            "trailer":lerp_angle(float(before.trailer),float(after.trailer),fraction)}
        _inspect(data,pose,obstacles,case_name)

func _sample(points: Array[Vector3], yaw: float, reverse: bool, data: Dictionary, obstacles: Array[Dictionary], case_name: String) -> Dictionary:
    route_count += 1
    var vehicle := Node3D.new()
    var model := Node3D.new()
    var trailer := Node3D.new()
    model.add_child(trailer)
    model.set_meta("trailer",trailer)
    model.set_meta("wheels",[])
    vehicle.add_child(model)
    vehicle.set_meta("model",model)
    driver.add_child(vehicle)
    vehicle.position = points[0]
    vehicle.rotation.y = yaw
    var curve: Curve3D = driver._rounded_curve(points)
    var length: float = curve.get_baked_length()
    var duration := maxf(.35,length/15.0)
    var steps := maxi(2,ceili(length/.045*1.6))
    driver._drive(vehicle,points,reverse)
    var tween: Tween = driver.captured
    var previous := _pose(vehicle)
    _inspect(data,previous,obstacles,case_name)
    for step in range(steps+2):
        var running: bool = tween.custom_step(duration/float(steps))
        var current := _pose(vehicle)
        _inspect_sweep(data,previous,current,obstacles,case_name)
        previous = current
        if not running:
            break
    if vehicle.position.distance_to(points[-1]) > .01:
        _fail(case_name,"incomplete_drive",previous,"production tween failed to reach endpoint")
    vehicle.free()
    return previous

func _run() -> void:
    var scenery: Node3D = World.build()
    # Headless dummy rendering does not retain MultiMesh transform getters.
    # World stores the bounds computed from the same generated mesh transforms.
    for mover in scenery.get_meta("container_movers"):
        var bounds: AABB = mover.transform*mover.get_meta("local_bounds")
        var projected := Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
        strip_obstacles.append({"name":mover.name,"rect":projected.grow(float(mover.get_meta("motion_max")))})
    scenery.free()
    driver = DriveHarness.new()
    root.add_child(driver)
    for level in range(2):
        var state: Dictionary = Rules.create_level(level)
        var free: Array[int] = []
        for truck in state.trucks:
            if Rules.can_dispatch(state,int(truck.id)):
                free.append(int(truck.id))
        print("ROUTE_LEVEL_%d_INITIAL_FREE: %s" % [level,str(free)])
        for id in free:
            var truck: Dictionary = state.trucks[id]
            var start := _yard_position(truck)
            var empty := _template(str(truck.type),int(truck.len),false)
            var loaded := _template(str(truck.type),int(truck.len),true)
            for bay in range(L.BAY_X.size()):
                var prefix := "L%d truck%d dir%d len%d bay%d" % [level,id,int(truck.dir),int(truck.len),bay]
                var obstacles := _obstacles(state,id,bay)
                var arrival: Array[Vector3] = driver._arrival_points(truck,bay,start)
                _sample(arrival,-float(truck.dir)*PI/2.0,false,empty,obstacles,prefix+" arrival")
                var dock := Vector3(L.BAY_X[bay],0,L.DOCK_Z)
                var reverse_points: Array[Vector3] = [dock,Vector3(L.BAY_X[bay],0,L.APRON_Z)]
                var reversed := _sample(reverse_points,0.0,true,loaded,obstacles,prefix+" reverse")
                var departure: Array[Vector3] = [reversed.position,Vector3(L.LANE_X,0,L.APRON_Z),Vector3(L.LANE_X,0,L.BOTTOM_Z),Vector3(0,0,L.BOTTOM_Z),Vector3(0,0,L.BRIDGE_BOUNDS.end.y-3.0)]
                _sample(departure,float(reversed.yaw),false,loaded,obstacles,prefix+" departure")
    print("ROUTE_SAMPLES: %d actual tween legs, %d swept poses, %d axle/tire samples" % [route_count,pose_count,wheel_count])
    var limit := failures.size() if "--report-all" in OS.get_cmdline_user_args() else mini(15,failures.size())
    for index in range(limit):
        print("ROUTE_FAILURE ",failures[index])
    # custom_step finishes the motion synchronously; give the real coroutine
    # its next process frame before destroying its owner during teardown.
    await process_frame
    await process_frame
    driver.free()
    if failures.is_empty():
        print("ROUTE_TESTS_OK: both initial yards/all available trucks/all five bays; swept body, stationary trucks, docks, thin moving strips and dry wheel tracks")
    else:
        print("ROUTE_TESTS_FAILED: %d distinct route/obstacle failures (add -- --report-all for all)" % failures.size())
    quit(0 if failures.is_empty() else 1)
