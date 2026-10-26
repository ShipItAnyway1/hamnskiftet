extends SceneTree

# Actual controller, both shared-world cameras, physical ray picking and real
# buttons; never reads or writes the player's profile.
class ReadabilityGame:
    extends "res://main.gd"
    func _load_progress() -> void: pass
    func _save_progress() -> void: pass
    func _sound(_kind: String, _cargo_type: String = "") -> void: pass

const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const View = preload("res://readability_view.gd")
var game
var failures: Array[String] = []
var kinds: Dictionary = {}
var directions: Dictionary = {}
var picked_trucks := 0
var valid_dispatches := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _physics() -> void:
    await physics_frame
    await physics_frame

func _hit(screen: Vector2) -> Dictionary:
    var ray: Dictionary = game._view_ray(screen)
    if ray.is_empty(): return {}
    var origin: Vector3 = ray.camera.project_ray_origin(ray.point)
    var normal: Vector3 = ray.camera.project_ray_normal(ray.point)
    return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+normal*150,7))

func _click_truck(id: int, context: String) -> void:
    var node: Node3D = game.truck_nodes[id]
    var point: Vector2 = game._screen_position(node.global_position+Vector3.UP*.55)
    var hit: Dictionary = _hit(point)
    if hit.is_empty() or not hit.collider.has_meta("truck_id") or int(hit.collider.get_meta("truck_id")) != id:
        check(false,"%s projected truck%d hits%s at%s" % [context,id,hit,point])
        return
    var before: Dictionary = game.state.duplicate(true)
    var legal: bool = R.can_dispatch(game.state,id)
    game._pick(point)
    picked_trucks += 1
    if legal:
        valid_dispatches += 1
        check(str(game.state.trucks[id].status) == "driving" and game.history.size() == 1,"Actual %s click dispatches the intended legal truck%d" % [context,id])
        game._undo()
        check(game.state == before and game.history.is_empty(),"Pick/undo restores exact logical snapshot in "+context)
        await _physics()
    else:
        check(game.state == before and game.history.is_empty(),"Actual %s click respects a blocked truck%d" % [context,id])

func _candidate_in_view() -> int:
    var fallback := -1
    for truck in game.state.trucks:
        var id: int = int(truck.id)
        if str(truck.status) != "yard": continue
        var point: Vector2 = game._screen_position(game.truck_nodes[id].global_position+Vector3.UP*.55)
        if not View.YARD_RECT.grow(-12).has_point(point): continue
        if R.can_dispatch(game.state,id): return id
        fallback = id
    return fallback

func _run() -> void:
    game = ReadabilityGame.new()
    root.add_child(game)
    game.qa = true
    game._refresh_audio_settings()
    game.set_process(false)
    game.highest_stage = 7
    for key in P.FLEET_KEYS: game.upgrades[key] = 3
    check(game._start_stage(8),"Real stage8 provides all six types and four directions")
    await _physics()
    var view = game.readable_view
    check(view.visible and not view.is_overview() and game.camera.cull_mask == 0,"Campaign boots split view and suppresses old full-scene rendering")
    check(view.yard_viewport.world_3d == game.get_world_3d() and view.dock_viewport.world_3d == game.get_world_3d(),"Both views share the authoritative physical world")
    for id in range(game.state.trucks.size()):
        var truck: Dictionary = game.state.trucks[id]
        kinds[str(truck.type)] = true
        directions[int(truck.dir)] = true
        await _click_truck(id,"split")
    check(kinds.size() == 6 and directions.size() == 4 and picked_trucks == 30,"All six cargo types and four directions were physically clicked")
    check(valid_dispatches > 0,"Picking test includes actual legal departures, not only blocked selections")

    var before: Dictionary = game.state.duplicate(true)
    for point in [Vector2(8,800),Vector2(450,590),Vector2(450,1220),Vector2(890,800),Vector2(450,1380)]:
        check(game._view_ray(point).is_empty(),"Non-view screen area has no scene ray: "+str(point))
        game._pick(point)
    check(game.state == before and game.history.is_empty(),"Outside/label/legend/footer picks never act on the hidden overview world")

    var gate: Node3D = game.obstacle_nodes[2]
    var gate_point: Vector2 = game._screen_position(gate.global_position+Vector3.UP*.30)
    var gate_hit: Dictionary = _hit(gate_point)
    check(not gate_hit.is_empty() and gate_hit.collider.get_meta("obstacle_id",-1) == 2,"Gate projects to its actual layer4 physical collider")
    game._pick(gate_point)
    check(game.state.obstacles[2].position_index == 1 and game.obstacle_motion and game.history.size() == 1,"Actual split-view gate click starts a free move")
    game._undo()
    await _physics()
    check(game.state == before and not game.obstacle_motion,"Gate click undo restores both shared views and cancels motion")

    game._change_zoom(.55)
    view.pan(Vector2(24,-18))
    await _physics()
    var zoomed: int = _candidate_in_view()
    check(zoomed >= 0 and is_equal_approx(game.zoom,1.55),"Zoom/pan keeps a visible truck for actual picking")
    if zoomed >= 0: await _click_truck(zoomed,"zoomed/panned split")
    game._reset_camera()
    var button: Button = game.ui.get_meta("view_button")
    button.pressed.emit()
    await _physics()
    check(view.is_overview() and not view.visible and game.camera.cull_mask != 0 and button.text == "Närvy","Actual view button restores overview camera, rendering and matching label")
    check(view.yard_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and view.dock_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Overview stops both extra render passes")
    var overview_id := -1
    for id in game.state.solution:
        if R.can_dispatch(game.state,int(id)):
            overview_id = int(id)
            break
    if overview_id >= 0: await _click_truck(overview_id,"overview")
    else: check(false,"Overview has a legal selectable truck")
    button.pressed.emit()
    await _physics()
    check(not view.is_overview() and view.visible and game.camera.cull_mask == 0 and button.text == "Hela","View button returns to split rendering and matching label")

    # A locked dock opens the real harbor. In this real preview state there is
    # no active stage, so the normal parking button can buy its entitlement.
    game._new_level(7,P.stage_config(8,game.upgrades))
    await _physics()
    var dock_point: Vector2 = game._screen_position(game.dock_targets[3].global_position+Vector3.UP*.05,"dock")
    check(View.DOCK_RECT.has_point(dock_point),"Locked purchasable dock is inside the loading view")
    var dock_hit: Dictionary = _hit(dock_point)
    check(not dock_hit.is_empty() and dock_hit.collider.get_meta("buy_bay",-1) == 3,"Loading-view ray reaches intended dock purchase collider")
    var wallet: int = int(game.balance)
    game._pick(dock_point)
    check(game.harbor.visible and game.paused and not game.stage_active,"Actual dock click opens between-stage harbor")
    var buy: Button = game.harbor.get_meta("buttons").parking
    check(not buy.disabled,"Real parking button is affordable in isolated preview")
    buy.pressed.emit()
    check(game.upgrades.parking == 1 and game.unlocked_bays == 4 and game.balance == wallet-80,"Real harbor purchase button charges exactly80 and unlocks the clicked dock")
    game._close_harbor()
    await _physics()
    check(not game.harbor.visible and game.stage_active and game.state.bays.count(-1) == 4 and view.visible,"Starting after purchase retains split view and purchased dock")

    game._new_level(0)
    await _physics()
    check(not game.campaign_mode and view.is_overview() and not view.visible and game.camera.cull_mask != 0,"Legacy depot correctly uses the original full-harbor camera")
    var legacy_id: int = int(game.state.solution[0])
    await _click_truck(legacy_id,"legacy overview")
    game._new_level(0,P.stage_config(1,P.defaults()))
    await _physics()
    check(view.visible and not view.is_overview() and game.camera.cull_mask == 0,"Legacy→compact campaign switch restores configured split cameras")
    check(button.text == "Hela","View label stays consistent after legacy/campaign configuration changes")
    if failures.is_empty():
        print("READABILITY_TESTS_OK:30 actual truck rays/all6types/4directions, legal+blocked picks, gate undo, dock80coin button purchase, outside rejection, zoom/pan, overview render masks and legacy switch")
    game.set_process(false)
    game.generation += 1
    for tween in game.active_tweens:
        if tween.is_valid(): tween.kill()
    await process_frame
    game.queue_free()
    await process_frame
    await process_frame
    quit(0 if failures.is_empty() else 1)
