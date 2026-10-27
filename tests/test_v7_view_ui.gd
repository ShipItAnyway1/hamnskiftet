extends SceneTree

const Interface = preload("res://interface.gd")
const World = preload("res://world.gd")
const View = preload("res://readability_view.gd")
const L = preload("res://layout.gd")

# Isolated fixture: this test never loads or writes the player's profile.
class Fixture:
    extends Node3D
    var font: Font = ThemeDB.fallback_font
    var heading: Font = ThemeDB.fallback_font
    var ui: Control
    var title_label: Label
    var money_label: Label
    var pause_button: Button
    var progress_label: Label
    var cargo_label: Label
    var progress_bar: ProgressBar
    var undo_button: Button
    var dock_button: Button
    var speed_button: Button
    var sound_button: Button
    var status_label: Label
    var toast_label: Label
    var modal: Control
    var modal_title: Label
    var modal_text: Label
    var modal_action: Button
    var level_buttons: Array[Button] = []
    var shop: Control
    var shop_balance: Label
    var shop_prices: Array[Label] = []
    var shop_buttons: Array[Button] = []
    var shop_marks: Array[TextureRect] = []
    var test_mode := false
    var rescue_busy := false
    var helicopter_mode := false
    var failed := false
    var paused := false
    var won := false
    var stage_active := true
    var balance := 120
    var history := [{}]
    var state := {"rescue_used":0,"bays":[-1,-1,-1,-2,-2]}
    var truck_nodes: Dictionary = {}
    var moving_trucks: Dictionary = {}
    var camera: Camera3D
    var calls: Array[String] = []
    func _toggle_pause(): pass
    func _undo(): pass
    func _open_shop(): pass
    func _toggle_speed(): pass
    func _change_zoom(_value): pass
    func _toggle_view(): pass
    func _modal_continue(): pass
    func _new_level(_value): pass
    func _toggle_sound(): pass
    func _close_shop(): pass
    func _buy_dock(_value): pass
    func _paid_undo(): calls.append("undo")
    func _toggle_rescue(): calls.append("rescue")
    func _restart_current(): calls.append("restart")
    func _toggle_test_mode(): test_mode = not test_mode
    func _open_harbor(): calls.append("harbor")
    func _toggle_music(): calls.append("music")

var failures: Array[String] = []
func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    var game := Fixture.new()
    root.add_child(game)
    game.camera = Camera3D.new()
    game.add_child(game.camera)
    Interface.build(game)
    Interface.configure_modal(game,false)
    Interface.refresh_support(game)
    await process_frame
    var toolbar: Control = game.ui.get_meta("test_toolbar")
    check(not toolbar.visible,"Normal game hides the entire legacy toolbar")
    check(game.undo_button.get_parent() == toolbar and game.speed_button.get_parent() == toolbar,"Legacy undo/speed API is retained only inside hidden test toolbar")
    check(game.ui.get_meta("mission_label").get_parent() == game.ui,"Order progress is independent of hidden toolbar")
    var paid: Button = game.modal.get_meta("paid_undo")
    var rescue: Button = game.modal.get_meta("rescue_button")
    check("100" in paid.text and not paid.disabled,"Paid undo discloses100 before activation")
    check("gratis" in rescue.text.to_lower() and not rescue.disabled,"First helicopter rescue is visibly free")
    paid.pressed.emit()
    rescue.pressed.emit()
    check(game.calls == ["undo","rescue"],"Actual help buttons call paid root APIs")
    game.state.rescue_used = 1
    game.balance = 49
    Interface.refresh_support(game)
    check("50" in rescue.text and rescue.disabled and paid.disabled,"Repeat rescue50 and undo100 enforce affordability in UI")
    game.balance = 100
    game.state.bays = [1,2,3,-2,-2]
    Interface.refresh_support(game)
    check(rescue.disabled and game.ui.get_meta("rescue_button").disabled,"No-free-bay rescue is unavailable in pause and HUD")
    game.test_mode = true
    Interface.refresh_support(game)
    check(toolbar.visible,"Explicit test mode reveals preserved toolbar")
    game.balance = 0
    Interface.refresh_support(game)
    check("gratis" in paid.text and not paid.disabled,"Test-mode undo discloses free policy even with zero balance")
    game.test_mode = false
    Interface.refresh_support(game)
    var help: Control = game.modal.get_meta("pause_help")
    check(help.position.y+help.size.y < game.modal.get_meta("card").size.y,"All help controls fit within pause card")
    Interface.configure_modal(game,true)
    check(not help.visible,"Pause help does not leak into victory modal")
    Interface.configure_modal(game,false)

    var site := World.build()
    game.add_child(site)
    var obstacles := World.build_obstacles(site,[{"id":2,"kind":"boom","x":7,"y":7,"w":2,"h":1,"opened":false,"opens_after":2}])
    var boom: Node3D = obstacles[2]
    check(boom.has_meta("armPivot") and boom.get_meta("body").collision_layer == 4,"Closed physical boom has visible arm and selectable collider")
    World.set_obstacle_open(boom,true,false)
    check(is_equal_approx(boom.get_meta("armPivot").rotation.z,PI*.5) and boom.get_meta("body").collision_layer == 0,"Opened boom arm is UP and its collider is disabled")
    check(not boom.get_meta("counter").visible,"Opened boom clears its progress counter")
    var clearance := [AABB(Vector3(-.845,0,-2),Vector3(.79,.76,4)),AABB(Vector3(.055,0,-2),Vector3(.79,.76,4))]
    _check_open_geometry(boom,boom,clearance)
    World.set_obstacle_open(boom,false,false)
    check(boom.get_meta("body").collision_layer == 4 and is_zero_approx(boom.get_meta("armPivot").rotation.z),"Snapshot restoration can close and reblock boom")

    var view = View.new()
    game.add_child(view)
    view.setup(game)
    view.configure({"campaign":true,"config":{"spawn_bounds":Rect2i(5,5,8,10),"types":["kyl","frys"]}})
    check(view.road_viewport.world_3d == game.get_world_3d(),"Third road view shares the real world")
    check(view.road_rect.end.y <= root.get_visible_rect().size.y and view.road_rect.position.y > view.yard_rect.end.y,"Responsive road viewport follows the depot and remains inside the canvas")
    check(view.yard_rect.size.x >= 450 and view.yard_rect.size.y >= 300,"Readable depot uses the available mobile canvas")
    view._process(0)
    game.paused = true
    view._process(0)
    check(view.dock_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE and view.yard_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE and view.road_viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,"Pause captures each final3D pose once instead of repeatedly rendering unchanged views")
    game.paused = false
    view._process(0)
    check(view.dock_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and view.yard_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Resume reactivates actual3D rendering")
    var actor := Node3D.new()
    actor.position = Vector3(10,0,9)
    game.add_child(actor)
    view.follow_traffic({7:actor},{7:"arrival"})
    check(view._follow_id == 7 and view.road_heading.text == "PÅ VÄG","Road camera follows an actual actor on legal side road")
    var center: Vector3 = view.road_camera.project_position(Vector2(view.road_viewport.size)*.5,45.0)
    check(center.distance_to(actor.position+Vector3.UP*.25) < .01,"Road camera centers the actual truck rather than synthetic motion")
    actor.position = L.yard_position({"x":6,"y":6,"len":2,"dir":0})
    view.follow_traffic({7:actor},{7:"arrival"})
    check(view._follow_id == -1 and view.road_heading.text == "UTFART","Yard actor is not duplicated as road traffic")
    view.set_overview(true)
    check(not view.is_overview() and view.visible,"Normal mode cannot expose full-harbor test overview")
    game.test_mode = true
    view.set_overview(true)
    check(view.is_overview() and not view.visible and game.camera.cull_mask != 0,"Explicit test overview restores original camera mask")
    view.set_overview(false)
    game.test_mode = false
    view._process(0)
    check(view.road_texture.visible,"Normal mode shows road strip")
    game.test_mode = true
    view._process(0)
    check(not view.road_texture.visible,"Test toolbar can replace road strip")
    if failures.is_empty(): print("V7_VIEW_UI_OK:normal/test toolbar, prices/callbacks/freebay, modal fit, physical boom clearance, true-world traffic camera")
    game.queue_free()
    await process_frame
    await process_frame
    quit(0 if failures.is_empty() else 1)

func _check_open_geometry(node: Node, obstacle: Node3D, lanes: Array) -> void:
    if node is MultiMeshInstance3D:
        var multi: MultiMesh = node.multimesh
        # Headless dummy RenderingServer cannot read MultiMesh buffers back.
        # These are the exact authored transforms passed to set_instance_transform.
        var authored: Array = node.get_meta("source_transforms")
        for index in range(multi.instance_count):
            var transform: Transform3D = obstacle.global_transform.affine_inverse()*node.global_transform*authored[index]
            var bounds: AABB = transform*multi.mesh.get_aabb()
            for lane in lanes:
                check(not bounds.intersects(lane),"Opened boom mesh must not clip a full .79m vehicle corridor: "+str(bounds))
    for child in node.get_children(): _check_open_geometry(child,obstacle,lanes)
