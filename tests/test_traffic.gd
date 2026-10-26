extends SceneTree

# Real controller and visuals, isolated from every player profile. Rectangle
# separation below uses independent center/radius SAT, not Traffic.overlaps.
class TrafficGame:
    extends "res://main.gd"
    func _load_progress() -> void: pass
    func _save_progress() -> void: pass
    func _sound(_kind: String, _cargo_type: String = "") -> void: pass

const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const L = preload("res://layout.gd")
const T = preload("res://traffic.gd")
var game
var failures: Array[String] = []
var checked_frames := 0
var pair_checks := 0
var simultaneous_frames := 0
var cursor := 0
var departure_visual_checks: Dictionary = {}
var queued_visual_checks := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _body(id: int) -> Dictionary:
    var node: Node3D = game.truck_nodes[id]
    var basis: Basis = node.global_basis.orthonormalized()
    return {"id":id,"center":Vector2(node.global_position.x,node.global_position.z),
        "right":Vector2(basis.x.x,basis.x.z).normalized(),
        "forward":Vector2(basis.z.x,basis.z.z).normalized(),
        "half_width":.395,"half_length":(float(game.state.trucks[id].len)*L.CELL-.08)*.5}

func _penetrates(a: Dictionary, b: Dictionary) -> bool:
    var delta: Vector2 = b.center-a.center
    # A separating projection on any face normal proves disjoint rectangles.
    # Six millimeters accommodates the controller's four millimeter allowance.
    for axis in [a.right,a.forward,b.right,b.forward]:
        var radius_a: float = absf(axis.dot(a.right))*float(a.half_width)+absf(axis.dot(a.forward))*float(a.half_length)
        var radius_b: float = absf(axis.dot(b.right))*float(b.half_width)+absf(axis.dot(b.forward))*float(b.half_length)
        if radius_a+radius_b-absf(delta.dot(axis)) <= .006:
            return false
    return true

func _separation() -> bool:
    var bodies: Array[Dictionary] = []
    for id in game.truck_nodes:
        if str(game.state.trucks[int(id)].status) != "done": bodies.append(_body(int(id)))
    for i in range(bodies.size()):
        for j in range(i+1,bodies.size()):
            pair_checks += 1
            if _penetrates(bodies[i],bodies[j]):
                check(false,"Physical OBB overlap frame%d trucks%d/%d centers%s/%s" % [checked_frames,bodies[i].id,bodies[j].id,bodies[i].center,bodies[j].center])
                return false
    return true

func _conservation() -> bool:
    var identities: Dictionary = {}
    var remaining: Dictionary = {}
    var remaining_value := 0.0
    for cargo in game.state.feed_left+game.state.feed_right+game.state.belt:
        if cargo == null: continue
        if identities.has(int(cargo.id)):
            check(false,"Cargo identity duplicated during simultaneous traffic")
            return false
        identities[int(cargo.id)] = true
        remaining[cargo.type] = int(remaining.get(cargo.type,0))+1
        remaining_value += float(cargo.value)
    var loaded := 0
    var loaded_value := 0.0
    var expected: Dictionary = {}
    for truck in game.state.trucks:
        loaded += int(truck.loaded)
        loaded_value += float(truck.delivery_value)
        expected[truck.type] = int(expected.get(truck.type,0))+int(truck.capacity)-int(truck.loaded)
    if identities.size()+loaded != int(game.state.cargo_total) or not is_equal_approx(remaining_value+loaded_value,float(game.state.cargo_value_total)):
        check(false,"Cargo units/value lost during real controller traffic")
        return false
    for kind in expected:
        if int(expected[kind]) != int(remaining.get(kind,0)):
            check(false,"Resource-specific cargo conservation failed for "+kind)
            return false
    return true

func _loading_visuals() -> bool:
    for bay in range(game.state.bays.size()):
        var id: int = int(game.state.bays[bay])
        if id < 0 or not game.truck_nodes.has(id): continue
        var truck: Dictionary = game.state.trucks[id]
        var node: Node3D = game.truck_nodes[id]
        var displayed: int = int(node.get_meta("displayed_load",-1))
        var in_flight: int = int(game.loading_in_flight.get(id,0))
        var queued: Array = game.load_queues.get(bay,[])
        var busy: bool = bool(game.load_busy.get(bay,false))
        if int(truck.loaded)-displayed != in_flight or in_flight != queued.size()+(1 if busy else 0):
            check(false,"Visible load/one-crane queue mismatch truck%d loaded%d displayed%d inflight%d queued%d busy%s" % [id,truck.loaded,displayed,in_flight,queued.size(),busy])
            return false
        for entry in queued:
            queued_visual_checks += 1
            if not is_instance_valid(entry.get("cargo_visual")):
                check(false,"Queued goods must remain real visible scene objects")
                return false
            if entry.has("pad") and not is_instance_valid(entry.pad):
                check(false,"Queued pallet lost its receiving support")
                return false
        var model: Node3D = node.get_meta("model")
        if not is_equal_approx(float(model.get_meta("load_fraction",-1)),float(displayed)/float(truck.capacity)):
            check(false,"Actual truck load meter disagrees with landed visual units")
            return false
        if game.moving_trucks.get(id) == "departure":
            departure_visual_checks[id] = true
            if in_flight != 0 or displayed != int(truck.capacity) or busy or not queued.is_empty():
                check(false,"Truck departed before all six real goods finished serial loading")
                return false
    return true

func _diagnostics(reason: String) -> void:
    print("TRAFFIC_FAILURE ",reason," frame=",checked_frames," step=",cursor," delivered=",game.state.delivered," bays=",game.state.bays)
    print("TRAFFIC_MOTION_ACTORS ",game.motion_actors)
    print("TRAFFIC_APRON owner=",game.traffic.apron_owner," queue=",game.traffic.apron_queue)
    print("TRAFFIC_METRICS peak=",game.peak_moving," simultaneous_frames=",simultaneous_frames," SATpairs=",pair_checks," obstacles=",game.state.get("obstacles",[]))
    for id in game.motion_actors:
        var actor: Dictionary = game.motion_actors[id]
        var node: Node3D = game.truck_nodes[id]
        var curve: Curve3D = actor.get("curve")
        var blocked_by: Array = []
        if curve != null:
            var next: float = minf(float(actor.length),float(actor.distance)+.09)
            var position: Vector3 = curve.sample_baked(next,true)
            var facing: Vector3 = (curve.sample_baked(minf(float(actor.length),next+.1),true)-curve.sample_baked(maxf(0,next-.1),true)).normalized()
            var yaw: float = atan2(-facing.x,-facing.z)+(PI if actor.reverse else 0.0)
            var candidate: Dictionary = _body(int(id))
            candidate.center = Vector2(position.x,position.z)
            candidate.right = Vector2(cos(yaw),-sin(yaw))
            candidate.forward = Vector2(sin(yaw),cos(yaw))
            for other in game.truck_nodes:
                if int(other) != int(id) and _penetrates(candidate,_body(int(other))): blocked_by.append(other)
            print("TRAFFIC_ACTOR ",id," phase=",game.moving_trucks.get(id)," position=",node.position," yaw=",node.rotation.y," next=",position," nextyaw=",yaw," blockers=",blocked_by)
    print("TRAFFIC_STATES ",game.state.trucks)

func _apron_entry_regression() -> void:
    var control := T.new()
    var owner: PackedVector2Array = T.corners(Vector3(1.353103,0,-2.074418),-.08688457,2.62)
    check(control.claim_apron(1,owner,owner),"First vehicle owns the actual apron turn")
    # This nose was allowed to advance by the previous painted-lane boundary.
    # It must wait HERE, before it can obstruct the owner's rounded turn.
    var approach: PackedVector2Array = T.corners(Vector3(.45,0,2.90),0,2.62)
    check(not control.claim_apron(0,approach,approach),"Second long truck waits before its front enters the reserved turn sweep")
    var independent_lane: PackedVector2Array = T.corners(Vector3(10,0,12),PI,2.62)
    check(control.claim_apron(9,independent_lane,independent_lane),"Unrelated side-lane movement remains parallel")
    var docked: PackedVector2Array = T.corners(Vector3(6,0,-6.3),0,2.62)
    control.claim_apron(1,docked,docked)
    check(control.apron_owner == -1 and control.claim_apron(0,approach,approach),"Owner releases after its complete rear clears; next waiting truck proceeds")

func _run() -> void:
    _apron_entry_regression()
    game = TrafficGame.new()
    root.add_child(game)
    game.qa = true
    game._refresh_audio_settings()
    game.highest_stage = 7
    game.upgrades = P.defaults()
    for key in P.FLEET_KEYS: game.upgrades[key] = 3
    game.upgrades.parking = 2
    game.upgrades.belt = P.max_rank("belt")
    check(game.upgrades.loader == 0,"Stress retains base crane speed against maximum belt")
    check(game._start_stage(8),"Stage8 starts through actual controller")
    var tempo := 24.0
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--traffic-tempo="):
            tempo = clampf(argument.trim_prefix("--traffic-tempo=").to_float(),1.0,60.0)
    game.qa_multiplier = tempo
    print("TRAFFIC_TEST_TEMPO ",tempo)
    check(game.state.total == 30 and game.state.bays == [-1,-1,-1,-1,-1],"Stress fixture is exactly30 trucks and5 open docks")
    for truck in game.state.trucks: check(truck.capacity == 6 and truck.len == 3,"Every stress vehicle has six units and a three-cell body")
    var previous: Dictionary = {}
    var no_progress := 0
    var previous_loaded := 0
    var previous_delivered := 0
    while not game.won and checked_frames < 12000 and failures.is_empty():
        var progress := false
        while cursor < game.state.solution_steps.size():
            var step: Dictionary = game.state.solution_steps[cursor]
            if step.action == "move_obstacle":
                if not game._move_obstacle(int(step.id)): break
            elif R.can_dispatch(game.state,int(step.id)):
                game._dispatch(int(step.id))
                if str(game.state.trucks[int(step.id)].status) != "driving":
                    check(false,"Legal stress selection rejected by controller")
                    break
            else: break
            cursor += 1
            progress = true
        await process_frame
        checked_frames += 1
        if not _separation() or not _conservation() or not _loading_visuals(): break
        var moving_this_frame := 0
        var now: Dictionary = {}
        for id in game.truck_nodes:
            var position: Vector3 = game.truck_nodes[id].global_position
            now[id] = position
            if previous.has(id) and position.distance_to(previous[id]) > .0001:
                moving_this_frame += 1
        if moving_this_frame >= 2: simultaneous_frames += 1
        if moving_this_frame > 0: progress = true
        previous = now
        var loaded := 0
        for truck in game.state.trucks: loaded += int(truck.loaded)
        if loaded > previous_loaded or int(game.state.delivered) > previous_delivered: progress = true
        previous_loaded = loaded
        previous_delivered = int(game.state.delivered)
        no_progress = 0 if progress else no_progress+1
        if no_progress >= 300:
            _diagnostics("300 frames without vehicle/loading/dispatch progress")
            check(false,"Traffic deadlock detected before large frame guard")
            break
    if not game.won or not R.is_won(game.state):
        if failures.is_empty(): _diagnostics("full frame guard")
        check(false,"Entire upgraded stage8 must reach an actual controller win")
    check(game.peak_load_queue > 1 and queued_visual_checks > 0,"Max belt really exercises waiting visible goods behind one busy crane")
    check(departure_visual_checks.size() == 30,"Every real departure was observed with all six visual goods landed")
    check(game.peak_moving >= 5,"At least5 vehicles are simultaneously active")
    check(simultaneous_frames > 0,"At least2 actual bodies move in the same frame")
    if failures.is_empty():
        print("LOAD_QUEUE_TESTS_OK: max belt/base crane,peak waiting queue%d,%d queued visuals checked,30 fully landed departures" % [game.peak_load_queue,queued_visual_checks])
        print("TRAFFIC_TESTS_OK: stage8/30 six-capacity trucks/5 docks,180 units conserved, actual win, peak%d moving, %d simultaneous-motion frames, %d independent SAT pairs over%d frames" % [game.peak_moving,simultaneous_frames,pair_checks,checked_frames])
    game.set_process(false)
    game.generation += 1
    for tween in game.active_tweens:
        if tween.is_valid(): tween.kill()
    await process_frame
    game.queue_free()
    await process_frame
    await process_frame
    quit(0 if failures.is_empty() else 1)
