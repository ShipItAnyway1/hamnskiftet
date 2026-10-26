extends Node3D

const P = preload("res://progression.gd")
const Traffic = preload("res://traffic.gd")
const AudioKit = preload("res://audio_manager.gd")
const ReadabilityView = preload("res://readability_view.gd")
const RescueFX = preload("res://rescue_effect.gd")
const CampaignSave = preload("res://campaign_save.gd")
const HarborMenu = preload("res://harbor_menu.gd")
const YardRenderer = preload("res://rendering_helper.gd")
const Rules = preload("res://puzzle.gd")
const Models = preload("res://models.gd")
const Harbor = preload("res://world.gd")
const G = preload("res://geometry.gd")
const L = preload("res://layout.gd")
const CELL := L.CELL
const BAY_X := L.BAY_X
const TYPE_NAMES := L.NAMES
const TYPE_COLORS := L.COLORS
const INK := Color("f3faff")
const MUTED := Color("b3d4ed")
const TICK_TIME := .85

var upgrades: Dictionary = P.defaults()
var active_upgrades: Dictionary = P.defaults()
var campaign_mode := false
var current_stage := 1
var highest_stage := 0
var stage_active := false
var harbor: Control
var harbor_was_paused := false
var legend_was_paused := false
var v4_round := ""
var v5_round := ""
var v6_round := ""
var v7_round := ""
var test_mode := false
var failed := false
var helicopter_mode := false
var rescue_busy := false
var barrier_states: Dictionary = {}
var feed_arrivals: Dictionary = {}
var readable_view: CanvasLayer
var traffic := Traffic.new()
var moving_trucks: Dictionary = {}
var motion_actors: Dictionary = {}
var obstacle_nodes: Dictionary = {}
var obstacle_motion := false
var peak_moving := 0
var load_queues: Dictionary = {}
var load_busy: Dictionary = {}
var peak_load_queue := 0
var soundscape: Node
var music_enabled := true
var yard_batch: Node3D
var saved_campaign_state: Dictionary = {}
var saved_active_upgrades: Dictionary = P.defaults()
var saved_elapsed := 0.0
var saved_earned := 0
var save_clock := 0.0
var state: Dictionary
var level_index := 0
var generation := 0
var history: Array[Dictionary] = []
var camera: Camera3D
var dynamic: Node3D
var effects: Node3D
var truck_nodes: Dictionary = {}
var cargo_nodes: Dictionary = {}
var feed_nodes: Array[Node3D] = []
var carrier_nodes: Array[Node3D] = []
var bay_labels: Array[Label3D] = []
var bay_machines: Array[Dictionary] = []
var active_tweens: Array[Tween] = []
var driving := false
var departure_queue: Array[int] = []
var loading_in_flight: Dictionary = {}
var clock := 0.0
var elapsed := 0.0
var speed := 1.0
var qa_multiplier := 1.0
var paused := false
var won := false
var stalled := false
var earned := 0
var balance := 120
var unlocked_bays := 3
var reward_claims: Dictionary = {}
var belt_material: ShaderMaterial
var container_movers: Array = []
var container_origins: Array[Vector3] = []
var dock_targets: Array[StaticBody3D] = []
var combo := 0
var last_departure_time := -100.0
var ui: Control
var font: SystemFont
var heading: SystemFont
var title_label: Label
var progress_label: Label
var cargo_label: Label
var money_label: Label
var status_label: Label
var toast_label: Label
var toast_left := 0.0
var progress_bar: ProgressBar
var undo_button: Button
var speed_button: Button
var sound_button: Button
var _web_settings_save_pending := false
var pause_button: Button
var dock_button: Button
var shop: Control
var shop_balance: Label
var shop_prices: Array[Label] = []
var shop_buttons: Array[Button] = []
var shop_marks: Array[TextureRect] = []
var shop_was_paused := false
var cargo_focus := ""
var level_buttons: Array[Button] = []
var modal: Control
var modal_title: Label
var modal_text: Label
var modal_action: Button
var audio: AudioStreamPlayer
var sound_enabled := true
var sounds: Dictionary = {}
var qa := false
var review_round := ""
var review_motion_types: Dictionary = {}
var review_motion_done: Dictionary = {}
var zoom := 1.0
var base_camera_size := 35.8

func _ready() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument == "--test-mode":
            test_mode = true
        if argument.begins_with("--v7="):
            v7_round = argument.trim_prefix("--v7=")
        if argument.begins_with("--v6="):
            v6_round = argument.trim_prefix("--v6=")
        if argument.begins_with("--v5="):
            v5_round = argument.trim_prefix("--v5=")
        if argument.begins_with("--v4="):
            v4_round = argument.trim_prefix("--v4=")
        if argument.begins_with("--review="):
            review_round = argument.trim_prefix("--review=")
    qa = "--qa" in OS.get_cmdline_user_args() or "--qa-full" in OS.get_cmdline_user_args()
    qa = qa or not review_round.is_empty() or not v4_round.is_empty() or not v5_round.is_empty() or not v6_round.is_empty() or not v7_round.is_empty()
    DisplayServer.window_set_title("Hamnskiftet · Lastbilspussel")
    font = SystemFont.new()
    font.font_names = PackedStringArray(["Avenir Next", "Trebuchet MS", "sans-serif"])
    heading = SystemFont.new()
    heading.font_names = font.font_names
    heading.font_weight = 800
    _build_scene()
    _build_ui()
    _web_settings_debug_setup()
    readable_view = ReadabilityView.new()
    add_child(readable_view)
    readable_view.setup(self)
    _build_audio()
    if not qa:
        _load_progress()
    if not qa or not v4_round.is_empty() or not v5_round.is_empty() or not v6_round.is_empty() or not v7_round.is_empty():
        if not _restore_campaign():
            _new_level(highest_stage,P.stage_config(highest_stage+1,upgrades))
            stage_active = false
        _open_harbor()
    else:
        _new_level(0)
    if not qa:
        if "--play" in OS.get_cmdline_user_args():
            _close_harbor()
        if not OS.has_feature("web"):
            DisplayServer.call_deferred("window_move_to_foreground")
        if "--handoff" in OS.get_cmdline_user_args():
            call_deferred("_capture_handoff")
    if not v7_round.is_empty():
        call_deferred("_run_v7_review")
    elif not v6_round.is_empty():
        call_deferred("_run_v6_review")
    elif not v5_round.is_empty():
        call_deferred("_run_v5_review")
    elif not v4_round.is_empty():
        call_deferred("_run_v4_review")
    elif not review_round.is_empty():
        call_deferred("_run_review")
    elif qa:
        call_deferred("_run_qa")

func _build_scene() -> void:
    var harbor: Node3D = Harbor.build()
    add_child(harbor)
    belt_material = harbor.get_meta("belt_material",null)
    container_movers = harbor.get_meta("container_movers",[])
    for mover in container_movers:
        container_origins.append(mover.position)
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color("75a8bb")
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color("d3e6f1")
    settings.ambient_light_energy = .50
    settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.environment = settings
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-62,-30,0)
    sun.light_color = Color("fff0d0")
    sun.light_energy = .78
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 70
    sun.shadow_bias = .025
    add_child(sun)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = base_camera_size
    camera.position = Vector3(0,45,41.0)
    add_child(camera)
    camera.look_at(Vector3(0,0,3.6))
    camera.current = true
    dynamic = Node3D.new()
    dynamic.name = "SpelbaraLastbilarOchVaror"
    add_child(dynamic)
    effects = Node3D.new()
    effects.name = "LastningOchEffekter"
    add_child(effects)
    for bay in range(5):
        var label := Label3D.new()
        label.font = heading
        label.font_size = 50
        label.pixel_size = .011
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.no_depth_test = true
        label.outline_size = 6
        label.outline_modulate = Color("142b3b")
        label.modulate = Color("d8e7ed")
        label.position = Vector3(BAY_X[bay],.68,-4.58)
        add_child(label)
        bay_labels.append(label)
        _build_machine(bay)
        var target := StaticBody3D.new()
        target.collision_layer = 2
        target.collision_mask = 0
        target.position = Vector3(BAY_X[bay],.12,L.DOCK_Z)
        target.set_meta("buy_bay",bay)
        var hit := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(2.3,.15,2.8)
        hit.shape = shape
        target.add_child(hit)
        add_child(target)
        dock_targets.append(target)

func _build_machine(bay: int) -> void:
    var machine := Node3D.new()
    machine.name = "RailMountedCrane_%02d" % (bay+1)
    machine.position = Vector3(BAY_X[bay],0,-7.45)
    add_child(machine)
    # The rear end cantilevers over the conveyor. Every support foot stays
    # outside its rubber surface and outside the clear driving apron.
    for x in [-1.18,1.18]:
        for z in [-.48,2.16]:
            G.box(machine,Vector3(x,.10,z),Vector3(.38,.20,.38),"c1cbd1")
            G.box(machine,Vector3(x,1.56,z),Vector3(.10,3.0,.10),"3b6381")
            G.box(machine,Vector3(x,.65,z),Vector3(.18,.16,.18),"f4bd48")
        G.box(machine,Vector3(x,3.11,.25),Vector3(.12,.19,5.2),"3b6381")
        G.box(machine,Vector3(x,3.22,.25),Vector3(.035,.035,5.2),"b9cad4")
    var trolley := Node3D.new()
    trolley.position = Vector3(0,0,1.80)
    machine.add_child(trolley)
    G.box(trolley,Vector3(0,3.30,0),Vector3(2.58,.19,.30),"f4bd48")
    G.box(trolley,Vector3(0,3.46,0),Vector3(.43,.24,.40),"345775")
    var cable := G.box(trolley,Vector3(0,2.72,0),Vector3(.027,.85,.027),"263d48")
    var claw := G.box(trolley,Vector3(0,2.27,0),Vector3(.42,.09,.42),"f4bd48")
    # A fixed pump serves fuel tankers through a connected flexible hose.
    var arm := Node3D.new()
    arm.position = Vector3(.94,0,.35)
    machine.add_child(arm)
    G.box(arm,Vector3(0,.48,0),Vector3(.28,.96,.36),"e60064")
    G.box(arm,Vector3(0,1.08,0),Vector3(.22,.24,.30),"263d48")
    arm.visible = false
    # A parked yard tug gives the otherwise empty service strip some life.
    var forklift := Node3D.new()
    forklift.position = Vector3(-1.05,0,1.5)
    forklift.visible = false
    machine.add_child(forklift)
    var tail_lift := Node3D.new()
    tail_lift.name = "RearLoadingRollerLift"
    machine.add_child(tail_lift)
    G.box(tail_lift,Vector3(0,.41,0),Vector3(.75,.07,1.0),"345775")
    for z in [-.40,-.20,0.0,.20,.40]:
        var roller := G.cylinder(tail_lift,Vector3(0,.452,z),.025,.67,"adc3d1")
        roller.rotation.z = PI*.5
    for x in [-.34,.34]:
        G.box(tail_lift,Vector3(x,.24,0),Vector3(.06,.34,.72),"345775")
        G.box(tail_lift,Vector3(x,.46,0),Vector3(.035,.04,1.00),"f4bd48")
    tail_lift.visible = false
    bay_machines.append({"root":machine,"trolley":trolley,"cable":cable,"claw":claw,"forklift":forklift,"arm":arm,"tail_lift":tail_lift})

func _style(color: Color, radius := 18, border := Color.TRANSPARENT) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = color
    box.corner_radius_top_left = radius
    box.corner_radius_top_right = radius
    box.corner_radius_bottom_left = radius
    box.corner_radius_bottom_right = radius
    if border.a > 0:
        box.set_border_width_all(1)
        box.border_color = border
    return box

func _label(parent: Node, text_value: String, pos: Vector2, dimensions: Vector2, font_size := 22, color := INK, bold := false) -> Label:
    var label := Label.new()
    label.text = text_value
    label.position = pos
    label.size = dimensions
    label.add_theme_font_override("font",heading if bold else font)
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _button(parent: Node, text_value: String, pos: Vector2, dimensions: Vector2, action: Callable, primary := false) -> Button:
    var button := Button.new()
    button.text = text_value
    button.position = pos
    button.size = dimensions
    button.add_theme_font_override("font",heading)
    button.add_theme_font_size_override("font_size",20)
    var base := Color("76d8b6") if primary else Color("1d3342")
    button.add_theme_color_override("font_color",Color("182d39") if primary else INK)
    button.add_theme_color_override("font_hover_color",Color("182d39") if primary else Color.WHITE)
    button.add_theme_color_override("font_pressed_color",Color("182d39") if primary else Color.WHITE)
    button.add_theme_color_override("font_disabled_color",Color("6c8797"))
    button.add_theme_stylebox_override("normal",_style(base,12,Color("314956")))
    button.add_theme_stylebox_override("hover",_style(base.lightened(.10),12,Color("76d8b6")))
    button.add_theme_stylebox_override("pressed",_style(base.darkened(.12),12,Color("76d8b6")))
    button.add_theme_stylebox_override("disabled",_style(Color("172d3e"),15))
    button.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),15,Color("f4d27b")))
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _build_ui() -> void:
    preload("res://interface.gd").build(self)
    harbor = HarborMenu.build(self)
    ui.add_child(harbor)
    harbor.visible = false
    var artwork_path := "res://assets/art/harbor-hero-v4.png"
    if FileAccess.file_exists(artwork_path):
        var artwork := Image.load_from_file(ProjectSettings.globalize_path(artwork_path))
        if artwork != null and not artwork.is_empty():
            harbor.get_meta("artwork").texture = ImageTexture.create_from_image(artwork)
    elif ResourceLoader.exists(artwork_path):
        harbor.get_meta("artwork").texture = load(artwork_path)

func _new_level(index: int, config: Dictionary = {}, restored: Dictionary = {}) -> void:
    generation += 1
    failed = false
    helicopter_mode = false
    rescue_busy = false
    barrier_states.clear()
    feed_arrivals.clear()
    if not test_mode:
        speed = 1.0
    if soundscape != null and soundscape.has_method("set_rescue_active"):
        soundscape.set_rescue_active(false)
    if is_instance_valid(yard_batch):
        yard_batch.restore()
        yard_batch.queue_free()
    yard_batch = null
    for tween in active_tweens:
        if tween.is_valid():
            tween.kill()
    active_tweens.clear()
    for node in dynamic.get_children():
        node.free()
    for node in effects.get_children():
        node.free()
    truck_nodes.clear()
    cargo_nodes.clear()
    feed_nodes.clear()
    carrier_nodes.clear()
    departure_queue.clear()
    loading_in_flight.clear()
    load_queues.clear()
    load_busy.clear()
    peak_load_queue = 0
    moving_trucks.clear()
    motion_actors.clear()
    obstacle_nodes.clear()
    obstacle_motion = false
    traffic.clear()
    peak_moving = 0
    level_index = index
    campaign_mode = not config.is_empty()
    stage_active = false
    active_upgrades = upgrades.duplicate(true)
    if campaign_mode:
        current_stage = int(config.get("stage",index+1))
        unlocked_bays = P.bay_count(int(upgrades.parking))
    state = Rules.create_level(index,config) if restored.is_empty() else restored.duplicate(true)
    if not state.has("rescue_used"):
        state.rescue_used = 0
    if soundscape != null and soundscape.has_method("set_boss"):
        soundscape.set_boss(bool(config.get("boss",false)))
    Rules.unlock_bays(state,unlocked_bays)
    if restored.is_empty():
        for _warmup in range(8):
            Rules.tick(state)
    Harbor.set_spawn_bounds(get_node("HarborDepotWorld"),state.get("config",{}).get("spawn_bounds",Rect2i(0,0,L.WIDTH,L.HEIGHT)))
    history.clear()
    driving = false
    clock = 0
    elapsed = 0
    save_clock = 0
    toast_left = 0
    toast_label.visible = false
    earned = 0
    combo = 0
    last_departure_time = -100
    paused = false
    won = false
    stalled = false
    modal.visible = false
    _set_modal_view(false)
    shop.visible = false
    if harbor != null:
        harbor.visible = false
    if ui.has_meta("cargo_legend"):
        ui.get_meta("cargo_legend").visible = false
    pause_button.text = "II"
    cargo_focus = ""
    _reset_camera()
    if is_instance_valid(readable_view):
        readable_view.configure(state)
    _reset_machines()
    _build_dynamic()
    _update_docks()
    _refresh_ui()

func _build_dynamic() -> void:
    for truck in state.trucks:
        if str(truck.status) == "done":
            continue
        var id := int(truck.id)
        var node := Node3D.new()
        node.name = "Lastbil_%d_%s" % [id,str(truck.type)]
        node.set_meta("truck_id",id)
        var model: Node3D = Models.truck(str(truck.type),float(truck.len)*CELL-.14,id,int(truck.capacity) if campaign_mode else 0)
        node.add_child(model)
        node.set_meta("model",model)
        var bay: int = state.bays.find(id)
        if str(truck.status) == "yard":
            node.position = _yard_position(truck)
            node.rotation.y = _yard_yaw(int(truck.dir))
        else:
            node.position = Vector3(BAY_X[maxi(bay,0)],0,L.DOCK_Z)
            node.rotation.y = 0
            if str(truck.status) == "driving":
                Rules.arrive(state,id)
            elif str(truck.status) == "departing":
                departure_queue.append(id)
        dynamic.add_child(node)
        var body := StaticBody3D.new()
        body.collision_layer = 1 if str(truck.status) == "yard" else 0
        body.collision_mask = 0
        body.set_meta("truck_id",id)
        var collider := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(.80,1.1,float(truck.len)*CELL-.08)
        collider.shape = shape
        collider.position.y = .55
        body.add_child(collider)
        node.add_child(body)
        node.set_meta("body",body)
        truck_nodes[id] = node
        _show_load(id)
        if str(truck.status) == "loading" and model.has_meta("reefer_door"):
            var door: Node3D = model.get_meta("reefer_door")
            door.rotation.y = -PI*.55
            _position_tail_lift(bay,node)
    for slot in range(L.BELT_SLOTS):
        var carrier := Node3D.new()
        G.box(carrier,Vector3(0,.035,0),Vector3(1.18,.07,1.08),"303b45")
        G.box(carrier,Vector3(0,.075,0),Vector3(1.10,.01,1.00),"384652")
        carrier.visible = state.belt[slot] != null
        dynamic.add_child(carrier)
        carrier.position = _belt_position(float(slot))
        carrier.rotation.y = L.belt_yaw(float(slot))
        carrier_nodes.append(carrier)
    _sync_cargo()
    _update_feed_preview()
    obstacle_nodes = Harbor.build_obstacles(dynamic,state.get("obstacles",[]))
    _sync_barriers(false)
    var parked: Array[Node3D] = []
    for truck in state.trucks:
        if str(truck.status) == "yard":
            parked.append(truck_nodes[int(truck.id)].get_meta("model"))
    if not parked.is_empty():
        yard_batch = YardRenderer.build(dynamic,parked)

func _fit_cargo(node: Node3D, kind: String) -> void:
    # Every category uses the full real carrier footprint. Cold goods used to
    # be reduced on two axes, which made their matching marks much smaller.
    node.set_meta("kind",kind)

func _position_tail_lift(bay: int, truck: Node3D) -> void:
    var model: Node3D = truck.get_meta("model")
    var rear := truck.position.z+float(model.get_meta("length"))*.5-.035
    var lift: Node3D = bay_machines[bay].tail_lift
    lift.position.z = rear+.46-bay_machines[bay].root.position.z
    lift.visible = true

func _yard_position(truck: Dictionary) -> Vector3:
    return L.yard_position(truck)

func _yard_yaw(direction: int) -> float:
    return -float(direction)*PI/2

func _belt_position(slot: float, height := L.BELT_HEIGHT) -> Vector3:
    return L.belt_position(slot,height)

func _sync_cargo() -> void:
    var present: Dictionary = {}
    for slot in range(state.belt.size()):
        var cargo = state.belt[slot]
        if cargo == null:
            continue
        var id := int(cargo.id)
        present[id] = true
        if not cargo_nodes.has(id):
            var node: Node3D = Models.cargo(str(cargo.type),1.9,int(cargo.get("quality",0)))
            _fit_cargo(node,str(cargo.type))
            node.name = "Vara_%d_%s" % [id,str(cargo.type)]
            dynamic.add_child(node)
            cargo_nodes[id] = node
        cargo_nodes[id].set_meta("slot",slot)
        cargo_nodes[id].position = _belt_position(float(slot),L.CARGO_HEIGHT)
        cargo_nodes[id].rotation.y = L.belt_yaw(float(slot))
    for id in cargo_nodes.keys():
        if not present.has(id):
            var node: Node3D = cargo_nodes[id]
            node.queue_free()
            cargo_nodes.erase(id)

func _update_feed_preview() -> void:
    for node in feed_nodes:
        if is_instance_valid(node):
            node.queue_free()
    feed_nodes.clear()
    for side in range(2):
        var feed: Array = state.feed_left if side == 0 else state.feed_right
        for i in range(mini(feed.size(),3)):
            var node: Node3D = Models.cargo(str(feed[i].type),1.6,int(feed[i].get("quality",0)))
            _fit_cargo(node,str(feed[i].type))
            var sign_value := -1.0 if side == 0 else 1.0
            node.position = Vector3(sign_value*(L.BELT_RADIUS_X+.65+float(i)*.96),L.CARGO_HEIGHT,L.BELT_CENTER_Z)
            dynamic.add_child(node)
            feed_nodes.append(node)

func _process(delta: float) -> void:
    if state == null or state.is_empty():
        return
    if toast_left > 0:
        toast_left -= delta
        toast_label.visible = toast_left > 0
    if paused or won or failed:
        if soundscape != null:
            soundscape.set_activity(0)
            soundscape.set_rescue_active(false)
        return
    var game_delta := delta*speed*qa_multiplier
    elapsed += game_delta
    save_clock += delta
    if save_clock >= 2.0 and campaign_mode and stage_active and not qa:
        save_clock = 0
        _save_progress()
    clock += game_delta
    var ticks := 0
    var interval := _belt_interval()
    while clock >= interval and ticks < 12:
        clock -= interval
        _step_belt()
        ticks += 1
    var phase := clock/interval
    for id in cargo_nodes:
        var node: Node3D = cargo_nodes[id]
        var slot := float(node.get_meta("slot"))+phase
        var target_position := _belt_position(slot,L.CARGO_HEIGHT)
        if feed_arrivals.has(id):
            var arrival: Dictionary = feed_arrivals[id]
            arrival.elapsed = float(arrival.elapsed)+game_delta
            var blend := smoothstep(0.0,.55,float(arrival.elapsed))
            node.position = Vector3(arrival.from).lerp(target_position,blend)
            if blend >= .999:
                feed_arrivals.erase(id)
        else:
            node.position = target_position
        node.rotation.y = L.belt_yaw(slot)
    for slot in range(carrier_nodes.size()):
        carrier_nodes[slot].visible = state.belt[slot] != null
        carrier_nodes[slot].position = _belt_position(float(slot)+phase)
        carrier_nodes[slot].rotation.y = L.belt_yaw(float(slot)+phase)
    if belt_material != null:
        belt_material.set_shader_parameter("travel",(float(state.ticks)+phase)/L.BELT_SLOTS*L.BELT_LENGTH)
    if campaign_mode or not driving:
        for id in departure_queue:
            if int(loading_in_flight.get(id,0)) == 0 and not moving_trucks.has(id) and (not truck_nodes.has(id) or not truck_nodes[id].get_meta("settling",false)):
                departure_queue.erase(id)
                _depart(id)
                break
    for i in range(container_movers.size()):
        container_movers[i].position = container_origins[i]+Vector3(0,0,sin(elapsed*.45+float(i))*.03)
    if soundscape != null:
        soundscape.set_activity(moving_trucks.size())
        soundscape.set_rescue_active(rescue_busy and not qa)
    _refresh_ui()
    _check_failure()

func _step_belt() -> void:
    var event: Dictionary = Rules.tick(state)
    for load_event in event.loads:
        _animate_load(load_event)
    _sync_cargo()
    for spawn in event.spawned:
        var cargo_id := int(spawn.cargo_id)
        if cargo_nodes.has(cargo_id):
            var entry_point := _belt_position(float(spawn.slot),L.CARGO_HEIGHT)
            entry_point.x += -1.10 if int(spawn.slot) == int(L.BELT_SLOTS/2) else 1.10
            feed_arrivals[cargo_id] = {"from":entry_point,"elapsed":0.0}
            cargo_nodes[cargo_id].position = entry_point
    if not event.spawned.is_empty():
        _update_feed_preview()
        _sound("feed")
    for id in event.departures:
        if int(id) not in departure_queue:
            departure_queue.append(int(id))
    var is_stalled: bool = Rules.is_stuck(state)
    if is_stalled and not stalled:
        _toast("Varuflödet har låst sig.",3.0)
        _sound("blocked")
    stalled = is_stalled
    _sync_barriers()

func _animate_load(event: Dictionary) -> void:
    var id := int(event.truck_id)
    var bay := int(event.bay)
    var entry := event.duplicate()
    var cargo_id := int(event.cargo_id)
    var cargo: Node3D
    if cargo_nodes.has(cargo_id):
        cargo = cargo_nodes[cargo_id]
        cargo_nodes.erase(cargo_id)
        cargo.reparent(effects,true)
    else:
        cargo = Models.cargo(str(event.type),1.9,int(event.get("quality",0)))
        _fit_cargo(cargo,str(event.type))
        effects.add_child(cargo)
    cargo.position = _belt_position(float(Rules.GATES[bay]),L.CARGO_HEIGHT)
    entry["cargo_visual"] = cargo
    entry["landed_loads"] = int(state.trucks[id].loaded)
    entry["ready"] = true
    loading_in_flight[id] = int(loading_in_flight.get(id,0))+1
    if not load_queues.has(bay):
        load_queues[bay] = []
    if load_busy.get(bay,false):
        # Receiving rollers support a waiting pallet while the one physical
        # crane finishes. A fast belt no longer creates overlapping cranes.
        var pad := Node3D.new()
        effects.add_child(pad)
        var start := cargo.position
        var side := -.57 if load_queues[bay].size()%2 == 0 else .57
        var staging := start+Vector3(side,0,.62)
        G.box(pad,Vector3(start.x,L.BELT_TOP+.04,start.z+.62),Vector3(2.36,.08,1.16),"526e7d")
        for x in [-1.08,1.08]:
            G.box(pad,Vector3(start.x+x,.50,start.z+.62),Vector3(.07,1.0,.08),"284557")
        entry["pad"] = pad
        entry.ready = false
        var my_generation := generation
        var transfer := _load_tween()
        transfer.tween_property(cargo,"position",staging,.16).set_trans(Tween.TRANS_SINE)
        transfer.tween_callback(func():
            if generation == my_generation:
                entry.ready = true
                _start_next_load(bay)
        )
    load_queues[bay].append(entry)
    peak_load_queue = maxi(peak_load_queue,load_queues[bay].size())
    _start_next_load(bay)

func _start_next_load(bay: int) -> void:
    if load_busy.get(bay,false) or not load_queues.has(bay) or load_queues[bay].is_empty():
        return
    var event: Dictionary = load_queues[bay][0]
    if not event.ready:
        return
    load_queues[bay].pop_front()
    load_busy[bay] = true
    _animate_load_now(event)

func _finish_load(bay: int, event: Dictionary) -> void:
    if event.has("pad") and is_instance_valid(event.pad):
        event.pad.queue_free()
    load_busy[bay] = false
    _start_next_load(bay)

func _animate_load_now(event: Dictionary) -> void:
    var id := int(event.truck_id)
    if not truck_nodes.has(id):
        return
    var kind := str(event.type)
    var bay := int(event.bay)
    var truck: Node3D = truck_nodes[id]
    var cargo: Node3D
    var cargo_id := int(event.cargo_id)
    if event.has("cargo_visual"):
        cargo = event.cargo_visual
    elif cargo_nodes.has(cargo_id):
        cargo = cargo_nodes[cargo_id]
        cargo_nodes.erase(cargo_id)
        cargo.reparent(effects,true)
    else:
        cargo = Models.cargo(kind,1.9,int(event.get("quality",0)))
        _fit_cargo(cargo,kind)
        effects.add_child(cargo)
    var start := cargo.position if event.has("cargo_visual") else _belt_position(float(Rules.GATES[bay]),L.CARGO_HEIGHT)
    var target := truck.position+Vector3(0,.91,.38)
    cargo.position = start
    cargo.rotation.y = 0
    if not event.has("cargo_visual"):
        loading_in_flight[id] = int(loading_in_flight.get(id,0))+1
    bay_machines[bay].trolley.visible = false
    var my_generation := generation
    var landed_loads := int(event.get("landed_loads",state.trucks[id].loaded))
    if not review_round.is_empty() and not review_motion_types.has(kind):
        review_motion_types[kind] = true
        _capture_review_motion(kind)
    if kind == "bransle":
        _animate_fuel(cargo,id,bay,start,target,my_generation,landed_loads,event)
        return
    var top := float(cargo.get_meta("lift_height",.43))*cargo.scale.y
    var refrigerated := kind in ["kyl","frys"]
    var rear := truck.position.z+float(truck.get_meta("model").get_meta("length"))*.5-.035
    var staging := Vector3(truck.position.x,.478,rear+.46)
    var interior := Vector3(truck.position.x,.478,rear-.44)
    var handling := Node3D.new()
    effects.add_child(handling)
    var bridge := G.box(handling,Vector3.ZERO,Vector3(2.58,.15,.18),"f4bd48")
    var winch := G.box(handling,Vector3.ZERO,Vector3(.30,.18,.27),"345775")
    var cable := G.box(handling,Vector3.ZERO,Vector3(.032,1.0,.032),"263d48")
    var grip := Node3D.new()
    handling.add_child(grip)
    G.box(grip,Vector3(0,.035,0),Vector3(.90,.055,.055),"adc3d1")
    G.box(grip,Vector3(0,.09,0),Vector3(.11,.11,.11),"f4bd48")
    for x in [-.44,.44]:
        G.box(grip,Vector3(x,-.12,0),Vector3(.035,.29,.10),"29465a")
        G.box(grip,Vector3(x-signf(x)*.045,-.25,0),Vector3(.12,.035,.16),"adc3d1")
    var falling_rocks: Array[Node3D] = []
    if kind == "schakt":
        for index in range(7):
            var stone := G.sphere(handling,Vector3.ZERO,.08,"778392")
            stone.visible = false
            falling_rocks.append(stone)
    var tween := _load_tween()
    # Lift vertically, travel along a visible bridge, then lower. The item
    # never bobs independently or flies along an unsupported ballistic arc.
    tween.tween_method(func(t: float):
        if generation != my_generation or not is_instance_valid(cargo):
            return
        var p: Vector3
        if refrigerated:
            if t < .16:
                p = start.lerp(Vector3(start.x,1.40,start.z),smoothstep(0.0,.16,t))
            elif t < .52:
                p = Vector3(start.x,1.40,start.z).lerp(Vector3(staging.x,1.40,staging.z),smoothstep(.16,.52,t))
            elif t < .77:
                p = Vector3(staging.x,1.40,staging.z).lerp(staging,smoothstep(.52,.77,t))
            else:
                p = staging.lerp(interior,smoothstep(.77,1.0,t))
        elif t < .22:
            p = start.lerp(Vector3(start.x,1.55,start.z),smoothstep(0.0,.22,t))
        elif t < .75:
            p = Vector3(start.x,1.55,start.z).lerp(Vector3(target.x,1.55,target.z),smoothstep(.22,.75,t))
        else:
            p = Vector3(target.x,1.55,target.z).lerp(target,smoothstep(.75,1.0,t))
        cargo.position = p
        bridge.position = Vector3(BAY_X[bay],3.30,p.z)
        winch.position = Vector3(p.x,3.46,p.z)
        grip.position = p+Vector3.UP*(top+.13)
        if refrigerated and t > .77:
            # The roller lift now pushes the pallet through the open back
            # door; the crane releases and retracts above the loading deck.
            grip.position = (staging+Vector3.UP*(top+.13)).lerp(Vector3(staging.x,2.88,staging.z),smoothstep(.77,1.0,t))
            bridge.position.z = staging.z
            winch.position.z = staging.z
        var cable_bottom := grip.position+Vector3.UP*.09
        var cable_top := Vector3(grip.position.x,3.28,grip.position.z)
        cable.position = cable_bottom.lerp(cable_top,.5)
        cable.scale.y = maxf(.04,cable_top.y-cable_bottom.y)
        # Open-bulk bins tip only when held over the actual trailer.
        if kind == "schakt" and t > .82:
            cargo.rotation.z = smoothstep(.82,1.0,t)*-.72
        for index in range(falling_rocks.size()):
            var stone: Node3D = falling_rocks[index]
            stone.visible = t > .78
            var fall := fposmod((t-.78)*5.0+float(index)/7.0,1.0)
            stone.position = target+Vector3(sin(float(index)*2.3)*.20,.53-fall*.88,cos(float(index)*2.3)*.30)
    ,0.0,1.0,.80).set_trans(Tween.TRANS_LINEAR)
    tween.tween_callback(func():
        if generation == my_generation and truck_nodes.has(id):
            _show_load(id,landed_loads)
            _puff(target,Color("d0f0ff") if kind == "frys" else Color(TYPE_COLORS[kind]),5)
            loading_in_flight[id] = maxi(0,int(loading_in_flight.get(id,1))-1)
            bay_machines[bay].trolley.visible = int(loading_in_flight[id]) == 0
            var model: Node3D = truck.get_meta("model")
            truck.set_meta("settling",true)
            var bounce := _tween()
            bounce.tween_property(model,"position:y",-.035,.08)
            bounce.tween_property(model,"position:y",0,.18).set_trans(Tween.TRANS_SINE)
            bounce.tween_callback(func():
                if generation == my_generation and is_instance_valid(truck):
                    truck.set_meta("settling",false)
            )
        cargo.queue_free()
        handling.queue_free()
        if generation == my_generation:
            _finish_load(bay,event)
    )
    _sound("load",kind)

func _animate_fuel(cargo: Node3D, id: int, bay: int, start: Vector3, target: Vector3, my_generation: int, landed_loads: int, event: Dictionary = {}) -> void:
    var rig := Node3D.new()
    effects.add_child(rig)
    var pump: Node3D = bay_machines[bay].arm
    pump.visible = true
    var manifold: Vector3 = pump.global_position+Vector3.UP*1.10
    var inlet := start+Vector3.UP*(float(cargo.get_meta("lift_height",.51))*cargo.scale.y)
    var outlet := target+Vector3.UP*.14
    var path: Array[Vector3] = [inlet,Vector3(inlet.x,1.65,inlet.z),manifold,Vector3(outlet.x+.45,1.55,outlet.z),outlet]
    for index in range(path.size()-1):
        var from: Vector3 = path[index]
        var to: Vector3 = path[index+1]
        var hose := G.cylinder(rig,from.lerp(to,.5),.045,from.distance_to(to),"20314b")
        hose.quaternion = Quaternion(Vector3.UP,(to-from).normalized())
        G.sphere(rig,to,.065,"e60064")
    var flow: Array[Node3D] = []
    for i in range(3):
        flow.append(G.sphere(rig,start,.065,"ffd35c"))
    var tween := _load_tween()
    tween.tween_method(func(t: float):
        if generation != my_generation:
            return
        for i in range(flow.size()):
            var f := fposmod(t*2.0+float(i)/3.0,1.0)*float(path.size()-1)
            var section := mini(int(f),path.size()-2)
            flow[i].position = path[section].lerp(path[section+1],f-float(section))
    ,0.0,1.0,.80)
    tween.tween_callback(func():
        if generation == my_generation and truck_nodes.has(id):
            _show_load(id,landed_loads)
            loading_in_flight[id] = maxi(0,int(loading_in_flight.get(id,1))-1)
            bay_machines[bay].trolley.visible = int(loading_in_flight[id]) == 0
        cargo.queue_free()
        rig.queue_free()
        if generation == my_generation:
            _finish_load(bay,event)
    )
    _sound("load","bransle")

func _show_load(id: int, displayed: int = -1) -> void:
    if not truck_nodes.has(id):
        return
    var data: Dictionary = state.trucks[id]
    var model: Node3D = truck_nodes[id].get_meta("model")
    var amount := int(data.loaded) if displayed < 0 else displayed
    truck_nodes[id].set_meta("displayed_load",amount)
    var ratio := float(amount)/float(data.capacity)
    Models.set_load_fraction(model,ratio)

func _span(item: Node3D, from: Vector3, to: Vector3) -> void:
    item.position = from.lerp(to,.5)
    if from.distance_to(to) > .001:
        item.look_at(to,Vector3.UP)
        item.scale = Vector3(.075,.09,from.distance_to(to))

func _dispatch(id: int) -> void:
    if paused or won or failed or rescue_busy or (driving and not campaign_mode) or modal.visible:
        return
    if id < 0 or id >= state.trucks.size():
        return
    var snapshot := {"state":state.duplicate(true),"elapsed":elapsed,"earned":earned,"combo":combo,"last_departure":last_departure_time}
    var result: Dictionary = Rules.dispatch(state,id)
    if not result.ok:
        if str(result.reason) == "blocked":
            _wiggle(id)
            _toast("Lastbilen kommer inte förbi.",3.0)
        elif str(result.reason) == "obstacle":
            _wiggle(id)
            _toast("Utfarten blockeras av ett hinder.",2.2)
        elif str(result.reason) == "bays_full":
            _toast("Alla kajer är upptagna.",3.0)
        _sound("blocked")
        return
    history.append(snapshot)
    if not qa:
        _save_progress()
    if campaign_mode:
        var dispatched: Dictionary = state.trucks[id]
        var target := int(dispatched.get("target_load",dispatched.capacity))
        _toast(("%s · %d varor i ordern" % [str(TYPE_NAMES[dispatched.type]),target]) if target > 0 else "%s · ingen ledig order" % str(TYPE_NAMES[dispatched.type]),2.0)
    var node: Node3D = truck_nodes[id]
    var body: StaticBody3D = node.get_meta("body")
    body.collision_layer = 0
    var bay := int(result.bay)
    var points := _arrival_points(state.trucks[id],bay,node.position)
    if campaign_mode:
        traffic.register_merge(id,int(state.trucks[id].dir),node.position)
    driving = true
    moving_trucks[id] = "arrival"
    peak_moving = maxi(peak_moving,moving_trucks.size())
    _sound("engine")
    var my_generation := generation
    await _drive(node,points,false)
    if my_generation != generation:
        return
    Rules.arrive(state,id)
    moving_trucks.erase(id)
    traffic.finish_route(id)
    driving = not moving_trucks.is_empty()
    _sound("dock")
    var model: Node3D = node.get_meta("model")
    if model.has_meta("reefer_door"):
        var door: Node3D = model.get_meta("reefer_door")
        _tween().tween_property(door,"rotation:y",-PI*.55,.28)
        _position_tail_lift(bay,node)
    _puff(node.position+Vector3(0,.14,1.0),Color("d1d9d4"),6)
    _toast("%s · Kaj %02d" % [TYPE_NAMES[str(state.trucks[id].type)],bay+1],1.8)

func _arrival_points(truck: Dictionary, bay: int, start: Vector3) -> Array[Vector3]:
    var points: Array[Vector3] = [start]
    var direction := int(truck.dir)
    if direction == 0:
        points.append(Vector3(start.x,0,L.APRON_Z))
    elif direction == 1:
        points.append(Vector3(L.LANE_X,0,start.z))
        points.append(Vector3(L.LANE_X,0,L.BOTTOM_Z))
        points.append(Vector3(-L.LANE_X,0,L.BOTTOM_Z))
        points.append(Vector3(-L.LANE_X,0,L.APRON_Z))
    elif direction == 2:
        points.append(Vector3(start.x,0,L.BOTTOM_Z))
        points.append(Vector3(-L.LANE_X,0,L.BOTTOM_Z))
        points.append(Vector3(-L.LANE_X,0,L.APRON_Z))
    else:
        points.append(Vector3(-L.LANE_X,0,start.z))
        points.append(Vector3(-L.LANE_X,0,L.APRON_Z))
    points.append(Vector3(float(BAY_X[bay]),0,L.APRON_Z))
    points.append(Vector3(float(BAY_X[bay]),0,L.DOCK_Z))
    return points

func _rounded_curve(points: Array[Vector3]) -> Curve3D:
    var curve := Curve3D.new()
    curve.bake_interval = .08
    curve.add_point(points[0])
    for i in range(1,points.size()-1):
        var before: Vector3 = points[i-1]
        var corner: Vector3 = points[i]
        var after: Vector3 = points[i+1]
        if before.distance_to(corner) < .05 or corner.distance_to(after) < .05:
            continue
        var radius := minf(.80,minf(before.distance_to(corner),corner.distance_to(after))*.33)
        var entry: Vector3 = corner+(before-corner).normalized()*radius
        var leave: Vector3 = corner+(after-corner).normalized()*radius
        curve.add_point(entry,Vector3.ZERO,(corner-entry)*.57)
        curve.add_point(leave,(corner-leave)*.57,Vector3.ZERO)
    curve.add_point(points[-1])
    return curve

func _drive(node: Node3D, points: Array[Vector3], reverse: bool) -> void:
    if is_instance_valid(yard_batch):
        yard_batch.detach(node.get_meta("model"))
    if campaign_mode:
        await _drive_traffic(node,points,reverse)
        return
    var curve := _rounded_curve(points)
    var length := curve.get_baked_length()
    var duration := maxf(.35,length/15.0)
    var my_generation := generation
    var start_yaw := node.rotation.y
    var model: Node3D = node.get_meta("model")
    var last_distance := 0.0
    var tween := _tween()
    tween.tween_method(func(distance: float):
        if generation != my_generation or not is_instance_valid(node):
            return
        var p: Vector3 = curve.sample_baked(distance,true)
        var ahead: Vector3 = curve.sample_baked(minf(length,distance+.10),true)
        var behind: Vector3 = curve.sample_baked(maxf(0,distance-.10),true)
        var facing: Vector3 = (ahead-behind).normalized()
        var desired := atan2(-facing.x,-facing.z)+(PI if reverse else 0.0)
        if distance < .45:
            desired = lerp_angle(start_yaw,desired,clampf(distance/.45,0,1))
        node.position = p
        node.rotation.y = desired
        var step := distance-last_distance
        last_distance = distance
        if model.has_meta("wheels"):
            for wheel in model.get_meta("wheels"):
                if is_instance_valid(wheel):
                    wheel.rotate_x(step*5.5*( -1.0 if reverse else 1.0))
        if model.has_meta("trailer"):
            var trailer: Node3D = model.get_meta("trailer")
            var old: Vector3 = curve.sample_baked(maxf(0,distance-.7),true)
            var trailer_facing: Vector3 = (p-old).normalized()
            if trailer_facing.length() > .1:
                var trailer_yaw := atan2(-trailer_facing.x,-trailer_facing.z)+(PI if reverse else 0.0)
                trailer.rotation.y = clampf(angle_difference(desired,trailer_yaw),-.25,.25)
        model.position.y = sin(distance*9)*.008
    ,0.0,length,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    # A killed tween never emits finished. Frame polling also lets undo/reset
    # release the suspended dispatch instead of retaining its function state.
    while generation == my_generation and tween.is_valid():
        await get_tree().process_frame
    if generation == my_generation and is_instance_valid(node):
        model.position.y = 0
        if model.has_meta("trailer"):
            var trailer: Node3D = model.get_meta("trailer")
            trailer.rotation.y = 0

func _vehicle_shape(id: int, position: Vector3, yaw: float) -> PackedVector2Array:
    return Traffic.corners(position,yaw,float(state.trucks[id].len)*CELL-.08)

func _traffic_free(id: int, position: Vector3, yaw: float) -> bool:
    var shape := _vehicle_shape(id,position,yaw)
    var current: Node3D = truck_nodes[id]
    var moving_shapes: Array[PackedVector2Array] = []
    for other in truck_nodes:
        if int(other) == id or str(state.trucks[int(other)].status) == "done":
            continue
        var node: Node3D = truck_nodes[other]
        var other_shape := _vehicle_shape(int(other),node.position,node.rotation.y)
        if Traffic.overlaps(shape,other_shape):
            return false
        if str(state.trucks[int(other)].status) != "yard":
            moving_shapes.append(other_shape)
    for obstacle in state.get("obstacles",[]):
        if bool(obstacle.get("opened",false)):
            var opening_node: Node3D = obstacle_nodes.get(int(obstacle.id))
            if opening_node == null or not bool(opening_node.get_meta("opening",false)):
                continue
        var obstacle_id := int(obstacle.id)
        if obstacle_nodes.has(obstacle_id):
            var node: Node3D = obstacle_nodes[obstacle_id]
            var block := Traffic.corners(node.position,0,float(obstacle.h)*CELL-.10,float(obstacle.w)*CELL-.10)
            if Traffic.overlaps(shape,block):
                return false
    if not traffic.allow_merges(id,shape,moving_shapes):
        return false
    if not traffic.claim_apron(id,shape,_vehicle_shape(id,current.position,current.rotation.y)):
        return false
    return true

func _sync_barriers(animate := true) -> void:
    for obstacle in state.get("obstacles",[]):
        var id := int(obstacle.id)
        if str(obstacle.get("kind","")) not in ["boom","barrier"] or not obstacle_nodes.has(id):
            continue
        var node: Node3D = obstacle_nodes[id]
        var opened := bool(obstacle.get("opened",false))
        if not barrier_states.has(id) or bool(barrier_states[id]) != opened:
            Harbor.set_obstacle_open(node,opened,animate and barrier_states.has(id))
            if opened and barrier_states.has(id):
                _sound("boom_barrier")
            barrier_states[id] = opened
        if node.has_meta("counter"):
            var counter: Label3D = node.get_meta("counter")
            counter.visible = not opened
            counter.text = "%d / %d" % [mini(int(state.delivered),int(obstacle.get("opens_after",0))),int(obstacle.get("opens_after",0))]

func _check_failure() -> void:
    if not campaign_mode or not stage_active or failed or won or paused or rescue_busy or helicopter_mode or not moving_trucks.is_empty() or not departure_queue.is_empty():
        return
    for count in loading_in_flight.values():
        if int(count) > 0:
            return
    var reason: String = Rules.loss_reason(state)
    if reason.is_empty():
        return
    failed = true
    helicopter_mode = false
    paused = true
    for tween in active_tweens:
        if tween.is_valid(): tween.pause()
    _set_modal_view(false)
    modal_title.text = "Ordern har låst sig"
    var explanations := {"bays_full":"Kajerna är upptagna av bilar som inte kan lasta nästa gods.","belt_jam":"Bandet är fullt och ingen bil vid kaj kan ta godset.","blocked_exits":"Det finns gods kvar, men utfarten till de lediga kajerna är blockerad.","no_orders":"Alla kajer är upptagna utan en möjlig godsorder."}
    explanations["bays_blocked"] = "Kajerna är upptagna av bilar som inte kan ta godset på bandet."
    modal_text.text = str(explanations.get(reason,"Dina val har blockerat varuflödet."))+"\nBörja om gratis eller ångra ett drag för 100 guld."
    modal_action.text = "Börja om gratis"
    modal.visible = true
    _sound("lose")
    if not qa:
        _save_progress()

func _toggle_rescue() -> void:
    if rescue_busy or won or (harbor != null and harbor.visible):
        return
    if -1 not in state.bays:
        _toast("Helikoptern vänder bilar i depån. Frigör en kaj eller ångra först.",3.0)
        return
    var cost := 0 if int(state.get("rescue_used",0)) == 0 else 50
    if not helicopter_mode and balance < cost:
        _toast("En extra helivända kostar 50 guld. Ditt saldo är %d." % balance,3.0)
        return
    helicopter_mode = not helicopter_mode
    if helicopter_mode:
        failed = false
        paused = false
        modal.visible = false
        for tween in active_tweens:
            if tween.is_valid(): tween.play()
        _toast("Välj en parkerad lastbil att vända 180° · %s" % ("gratis" if cost == 0 else "50 guld"),5.0)
    _refresh_ui()

func _rescue_truck(id: int) -> bool:
    if rescue_busy or won or id < 0 or id >= state.trucks.size() or str(state.trucks[id].status) != "yard":
        return false
    var price := 0 if int(state.get("rescue_used",0)) == 0 else 50
    if balance < price:
        _toast("Du behöver 50 guld för en extra helivända.",3.0)
        return false
    var snapshot := {"state":state.duplicate(true),"elapsed":elapsed,"earned":earned,"combo":combo,"last_departure":last_departure_time}
    var old_balance := balance
    var result: Dictionary = Rules.rotate_truck(state,id)
    if not bool(result.get("ok",false)):
        return false
    state.rescue_used = int(state.get("rescue_used",0))+1
    balance -= price
    if not qa and _store_progress() != OK:
        state = snapshot.state
        balance = old_balance
        _toast("Köpet kunde inte sparas. Inget guld drogs.",3.0)
        return false
    history.append(snapshot)
    helicopter_mode = false
    rescue_busy = true
    var node: Node3D = truck_nodes[id]
    if is_instance_valid(yard_batch):
        yard_batch.detach(node.get_meta("model"))
    node.get_meta("body").collision_layer = 0
    var my_generation := generation
    var fx := RescueFX.new()
    if soundscape != null:
        soundscape.set_rescue_active(not qa)
    _sound("rescue")
    _refresh_ui()
    await fx.play(effects,node,_yard_yaw(int(state.trucks[id].dir)),func(): return generation == my_generation,func(): return paused)
    if generation != my_generation:
        return false
    rescue_busy = false
    if is_instance_valid(node):
        node.get_meta("body").collision_layer = 1
    if soundscape != null:
        soundscape.set_rescue_active(false)
    _toast("Lastbilen är vänd · %s" % ("gratisräddning använd" if price == 0 else "−50 guld"),2.5)
    _refresh_ui()
    return true

func _paid_undo() -> void:
    _undo()

func _toggle_test_mode() -> void:
    test_mode = not test_mode
    if not test_mode and speed > 1.0:
        _toggle_speed()
    if not test_mode and is_instance_valid(readable_view):
        readable_view.set_overview(false)
    _refresh_ui()

func _drive_traffic(node: Node3D, points: Array[Vector3], reverse: bool) -> void:
    var id := int(node.get_meta("truck_id"))
    var model: Node3D = node.get_meta("model")
    var curve := _rounded_curve(points)
    var length := curve.get_baked_length()
    var my_generation := generation
    var distance := 0.0
    var velocity := 0.0
    var start_yaw := node.rotation.y
    var previous_velocity := 0.0
    motion_actors[id] = {"node":node,"distance":0.0,"length":length,"waiting":false,"reverse":reverse,"curve":curve}
    Models.set_vehicle_lights(model,false)
    while generation == my_generation and distance < length-.0001:
        await get_tree().process_frame
        if generation != my_generation or not is_instance_valid(node):
            return
        if paused:
            continue
        var delta := maxf(get_process_delta_time(),.001)*speed*qa_multiplier
        var remaining := length-distance
        var target_speed := minf(13.0,sqrt(maxf(0.0,remaining*36.0)))
        previous_velocity = velocity
        velocity = move_toward(velocity,target_speed,delta*28.0)
        var budget := minf(velocity*delta,24.0)
        var waiting := false
        var moved := 0.0
        while budget > .00001 and distance < length-.0001:
            var step := minf(.09,minf(budget,length-distance))
            var next := distance+step
            var position := curve.sample_baked(next,true)
            var ahead := curve.sample_baked(minf(length,next+.10),true)
            var behind := curve.sample_baked(maxf(0,next-.10),true)
            var facing := (ahead-behind).normalized()
            var yaw := atan2(-facing.x,-facing.z)+(PI if reverse else 0.0)
            if next < .45:
                yaw = lerp_angle(start_yaw,yaw,clampf(next/.45,0,1))
            if not _traffic_free(id,position,yaw):
                waiting = true
                velocity = 0
                break
            var turn := angle_difference(node.rotation.y,yaw)
            node.position = position
            node.rotation.y = yaw
            for wheel in model.get_meta("wheels",[]):
                wheel.rotate_x(step*5.5*(-1.0 if reverse else 1.0))
            var trailer: Node3D = model.get_meta("trailer")
            var old := curve.sample_baked(maxf(0,next-.7),true)
            var trailer_facing := (position-old).normalized()
            if trailer_facing.length() > .1:
                var trailer_yaw := atan2(-trailer_facing.x,-trailer_facing.z)+(PI if reverse else 0.0)
                trailer.rotation.y = clampf(angle_difference(yaw,trailer_yaw),-.20,.20)
            model.rotation.z = lerpf(model.rotation.z,clampf(-turn*.35,-.055,.055),.3)
            distance = next
            budget -= step
            moved += step
        model.position.y = sin(distance*9)*minf(.009,velocity*.0008)
        var cab: Node3D = model.get_meta("cab")
        cab.position.y = sin(distance*17)*minf(.006,velocity*.0005)
        cab.rotation.x = lerpf(cab.rotation.x,clampf((previous_velocity-velocity)*.002,-.025,.035),.24)
        Models.set_vehicle_lights(model,waiting or remaining < 2.0)
        var future := minf(length,distance+2.2)
        var future_heading := (curve.sample_baked(minf(length,future+.10),true)-curve.sample_baked(maxf(0,future-.10),true)).normalized()
        var future_yaw := atan2(-future_heading.x,-future_heading.z)+(PI if reverse else 0.0)
        var indicator_delta := angle_difference(node.rotation.y,future_yaw)
        Models.set_turn_signal(model,(-1 if indicator_delta > 0 else 1) if absf(indicator_delta) > .12 else 0,fposmod(elapsed,.68) < .34)
        motion_actors[id] = {"node":node,"distance":distance,"length":length,"waiting":waiting,"reverse":reverse,"moved":moved,"curve":curve}
    if generation == my_generation and is_instance_valid(node):
        model.position.y = 0
        model.rotation.z = 0
        model.get_meta("cab").position.y = 0
        model.get_meta("cab").rotation.x = 0
        model.get_meta("trailer").rotation.y = 0
        Models.set_vehicle_lights(model,true)
        Models.set_turn_signal(model,0,false)
        motion_actors.erase(id)
        if not Traffic.bounds(_vehicle_shape(id,node.position,node.rotation.y)).intersects(Traffic.APRON):
            traffic.release(id)

func _move_obstacle(id: int) -> bool:
    if paused or won or modal.visible or obstacle_motion or not obstacle_nodes.has(id):
        return false
    var data: Dictionary = {}
    for item in state.get("obstacles",[]):
        if int(item.id) == id:
            data = item
            break
    if data.is_empty() or not data.get("movable",false):
        _toast("Containern är ett fast hinder.",2.0)
        _sound("blocked")
        return false
    var origin := Vector3(L.YARD_ORIGIN.x+float(data.positions[0].x)*CELL,0,L.YARD_ORIGIN.y+float(data.positions[0].y)*CELL)
    var destination := Vector3(L.YARD_ORIGIN.x+float(data.positions[1].x)*CELL,0,L.YARD_ORIGIN.y+float(data.positions[1].y)*CELL)
    var center := (origin+destination)*.5
    var swept := Traffic.corners(center,0,CELL+.08,origin.distance_to(destination)+CELL+.08)
    var future_position: Vector2i = data.positions[1-int(data.position_index)]
    var future_center := Vector3(L.YARD_ORIGIN.x+float(future_position.x)*CELL,0,L.YARD_ORIGIN.y+float(future_position.y)*CELL)
    var future_shape := Traffic.corners(future_center,0,CELL+.08,CELL+.08)
    for truck_id in moving_trucks:
        var truck: Node3D = truck_nodes[truck_id]
        if Traffic.overlaps(swept,_vehicle_shape(int(truck_id),truck.position,truck.rotation.y)):
            _toast("Vänta tills lastbilen har passerat porten.",2.0)
            return false
        # Dispatch reserves an exit immediately. A moving gate must respect
        # the rest of that exit, even while its truck is still several meters
        # away; checking only its current body can trap it behind a moved gate.
        if motion_actors.has(truck_id) and moving_trucks[truck_id] == "arrival":
            var actor: Dictionary = motion_actors[truck_id]
            var route: Curve3D = actor.curve
            var probe: float = float(actor.distance)
            while probe < float(actor.length):
                var point := route.sample_baked(probe,true)
                var ahead := route.sample_baked(minf(float(actor.length),probe+.1),true)
                var behind := route.sample_baked(maxf(0,probe-.1),true)
                var facing := (ahead-behind).normalized()
                var yaw := atan2(-facing.x,-facing.z)
                if Traffic.overlaps(future_shape,_vehicle_shape(int(truck_id),point,yaw)):
                    _toast("Utfarten används. Låt lastbilen passera porten.",2.0)
                    return false
                probe += .30
    var snapshot := {"state":state.duplicate(true),"elapsed":elapsed,"earned":earned,"combo":combo,"last_departure":last_departure_time}
    var result: Dictionary = Rules.move_obstacle(state,id)
    if not result.ok:
        _toast("Porten behöver en ledig ruta.",2.0)
        _sound("blocked")
        return false
    history.append(snapshot)
    var node: Node3D = obstacle_nodes[id]
    var target := Vector3(L.YARD_ORIGIN.x+float(data.x)*CELL,0,L.YARD_ORIGIN.y+float(data.y)*CELL)
    obstacle_motion = true
    var my_generation := generation
    var tween := _tween()
    tween.tween_property(node,"position",target,.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    tween.tween_callback(func():
        if generation == my_generation:
            obstacle_motion = false
    )
    _sound("gate")
    if not qa:
        _save_progress()
    return true

func _depart(id: int) -> void:
    if not truck_nodes.has(id) or str(state.trucks[id].status) != "departing" or moving_trucks.has(id):
        return
    driving = true
    moving_trucks[id] = "departure"
    peak_moving = maxi(peak_moving,moving_trucks.size())
    var my_generation := generation
    var node: Node3D = truck_nodes[id]
    var bay: int = state.bays.find(id)
    var model: Node3D = node.get_meta("model")
    bay_machines[bay].tail_lift.visible = false
    if model.has_meta("reefer_door"):
        var door: Node3D = model.get_meta("reefer_door")
        _tween().tween_property(door,"rotation:y",0,.20)
    # The cab faces the belt; reverse into the clear apron before leaving.
    await _drive(node,[node.position,Vector3(node.position.x,0,L.APRON_Z)],true)
    if my_generation != generation:
        return
    var route: Array[Vector3] = [node.position,Vector3(L.LANE_X,0,L.APRON_Z),Vector3(L.LANE_X,0,L.BOTTOM_Z),Vector3(0,0,L.BOTTOM_Z),Vector3(0,0,27.5)]
    await _drive(node,route,false)
    if my_generation != generation:
        return
    Rules.release_bay(state,id)
    _sync_barriers()
    truck_nodes.erase(id)
    node.queue_free()
    bay_machines[bay].arm.visible = false
    moving_trucks.erase(id)
    traffic.release(id)
    driving = not moving_trucks.is_empty()
    var reward := 0
    if campaign_mode:
        var kind: String = str(state.trucks[id].type)
        var proposal: Dictionary = P.cargo_reward(current_stage,kind,int(state.manifest_delivered.get(kind,0)),float(state.config.cargo_values[kind]),reward_claims)
        if bool(proposal.ok):
            reward_claims = proposal.ledger
            reward = int(proposal.reward)
    else:
        var claim := "v2:%d:%d" % [level_index,id]
        if not reward_claims.has(claim):
            reward_claims[claim] = true
            reward = 10
    balance += reward
    earned += reward
    if not qa:
        _save_progress()
    combo = combo+1 if elapsed-last_departure_time < 14.0 else 1
    last_departure_time = elapsed
    _sound("depart")
    if combo >= 2:
        _toast("Leveranskedja ×%d%s" % [combo,("  ·  +%d mynt" % reward) if reward > 0 else ""],3.0)
    else:
        _toast(("Levererat  ·  +%d mynt" % reward) if reward > 0 else "Levererat!",2.0)
    if Rules.is_won(state):
        _win()

func _undo() -> void:
    if rescue_busy or (harbor != null and harbor.visible) or ui.get_meta("cargo_legend").visible:
        return
    if history.is_empty():
        _toast("Det finns inget drag att ångra.",2.0)
        return
    var price := 0 if test_mode else 100
    if balance < price:
        _toast("Ångra kostar 100 guld. Omstart är gratis.",3.0)
        return
    var snapshot: Dictionary = history.back()
    var previous := {"state":state,"balance":balance,"elapsed":elapsed,"earned":earned,"combo":combo,"last_departure":last_departure_time,"stage_active":stage_active,"won":won,"failed":failed,"paused":paused}
    var used := int(state.get("rescue_used",0))
    state = snapshot.state.duplicate(true)
    state.rescue_used = maxi(used,int(state.get("rescue_used",0)))
    Rules.unlock_bays(state,unlocked_bays)
    balance -= price
    elapsed = float(snapshot.elapsed)
    earned = int(snapshot.earned)
    combo = int(snapshot.combo)
    last_departure_time = float(snapshot.last_departure)
    stage_active = campaign_mode and not Rules.is_won(state)
    won = false
    failed = false
    paused = false
    if not qa and _store_progress() != OK:
        state = previous.state
        balance = previous.balance
        elapsed = previous.elapsed
        earned = previous.earned
        combo = previous.combo
        last_departure_time = previous.last_departure
        stage_active = previous.stage_active
        won = previous.won
        failed = previous.failed
        paused = previous.paused
        _toast("Ångringen kunde inte sparas. Inget guld drogs.",3.0)
        return
    history.pop_back()
    generation += 1
    if is_instance_valid(yard_batch):
        yard_batch.restore()
        yard_batch.queue_free()
    yard_batch = null
    for tween in active_tweens:
        if tween.is_valid(): tween.kill()
    active_tweens.clear()
    for node in dynamic.get_children(): node.free()
    for node in effects.get_children(): node.free()
    truck_nodes.clear()
    cargo_nodes.clear()
    feed_nodes.clear()
    carrier_nodes.clear()
    departure_queue.clear()
    loading_in_flight.clear()
    load_queues.clear()
    load_busy.clear()
    moving_trucks.clear()
    motion_actors.clear()
    obstacle_nodes.clear()
    barrier_states.clear()
    feed_arrivals.clear()
    obstacle_motion = false
    helicopter_mode = false
    rescue_busy = false
    traffic.clear()
    clock = 0
    driving = false
    stalled = false
    modal.visible = false
    shop.visible = false
    _reset_machines()
    _build_dynamic()
    _update_docks()
    _refresh_ui()
    _toast("Draget är ångrat"+(" · testläge" if price == 0 else " · −100 guld"),2.0)

func _wiggle(id: int) -> void:
    if not truck_nodes.has(id):
        return
    var node: Node3D = truck_nodes[id]
    var model: Node3D = node.get_meta("model")
    if is_instance_valid(yard_batch):
        yard_batch.detach(model)
    var tween := _tween()
    tween.tween_property(model,"position:x",.06,.055)
    tween.tween_property(model,"position:x",-.06,.08)
    tween.tween_property(model,"position:x",0.0,.065)

func _puff(position_value: Vector3, color: Color, count: int) -> void:
    var root := Node3D.new()
    root.position = position_value
    effects.add_child(root)
    var tween := _tween()
    tween.set_parallel(true)
    for i in range(count):
        var angle := TAU*float(i)/float(count)
        var particle := G.sphere(root,Vector3.ZERO,.055,color.to_html(false))
        var target := Vector3(cos(angle)*.35,.20+float(i%3)*.08,sin(angle)*.35)
        tween.tween_property(particle,"position",target,.50).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.tween_property(particle,"scale",Vector3.ONE*.03,.50)
    tween.chain().tween_callback(root.queue_free)

func _tween() -> Tween:
    var tween := create_tween()
    tween.set_speed_scale(speed*qa_multiplier)
    active_tweens.append(tween)
    var reference: WeakRef = weakref(tween)
    tween.finished.connect(func():
        var finished_tween = reference.get_ref()
        if finished_tween != null:
            active_tweens.erase(finished_tween)
    ,CONNECT_ONE_SHOT)
    return tween

func _belt_interval() -> float:
    return TICK_TIME/P.belt_multiplier(int(active_upgrades.belt)) if campaign_mode else TICK_TIME

func _loading_rate() -> float:
    return P.loading_multiplier(int(active_upgrades.loader)) if campaign_mode else 1.0

func _load_tween() -> Tween:
    var tween := _tween()
    tween.set_meta("loading",true)
    tween.set_speed_scale(speed*qa_multiplier*_loading_rate())
    return tween

func _start_stage(stage: int = -1) -> bool:
    if stage < 0 and stage_active and not won:
        _close_harbor()
        return true
    var target := highest_stage+1 if stage < 0 else stage
    if target < 1 or target > highest_stage+1:
        return false
    _new_level(target-1,P.stage_config(target,upgrades))
    stage_active = true
    _refresh_ui()
    if not qa:
        _save_progress()
    return true

func _restart_current() -> void:
    if campaign_mode:
        _new_level(current_stage-1,P.stage_config(current_stage,upgrades))
        stage_active = true
    else:
        _new_level(level_index)
    if not qa:
        _save_progress()

func _open_harbor() -> void:
    if harbor == null or harbor.visible:
        return
    if ui.get_meta("cargo_legend").visible:
        _close_cargo_legend()
    harbor_was_paused = paused
    paused = true
    modal.visible = false
    shop.visible = false
    for tween in active_tweens:
        if tween.is_valid():
            tween.pause()
    harbor.visible = true
    _refresh_harbor()
    if not qa:
        _save_progress()

func _close_harbor() -> void:
    if not harbor.visible:
        return
    if not stage_active or won:
        _start_stage()
        return
    harbor.visible = false
    paused = harbor_was_paused
    if paused:
        _toggle_pause()
    else:
        for tween in active_tweens:
            if tween.is_valid():
                tween.play()

func _refresh_harbor() -> void:
    if harbor == null:
        return
    var between := not stage_active or won
    var next_stage := highest_stage+1
    _set_wallet(harbor.get_meta("balance"),balance,35)
    harbor.get_meta("stage").text = "Bana %d · %s" % [next_stage if between else current_stage,_stage_name(next_stage if between else current_stage)]
    if between:
        var preview: Dictionary = Rules.create_level(next_stage-1,P.stage_config(next_stage,upgrades))
        var income: int = P.remaining_income(next_stage,preview.manifest,preview.config.cargo_values,reward_claims)
        harbor.get_meta("subtitle").text = "%d lastbilar · %d varor · %d mynt att tjäna" % [int(preview.total),int(preview.cargo_total),income]
    else:
        harbor.get_meta("subtitle").text = "Din bana är pausad. Uppgradera efter skiftet."
    harbor.get_meta("play").text = "Spela bana %d" % next_stage if between else "Fortsätt bana %d" % current_stage
    harbor.get_meta("resume").visible = not between
    var cards: Dictionary = harbor.get_meta("upgrade_cards")
    for key in P.KEYS:
        var card: Control = cards[key]
        var rank := int(upgrades[key])
        var cost := P.cost(key,rank)
        card.get_meta("effect").text = P.effect_text(key,rank)
        card.get_meta("next_effect").text = "→ "+P.next_effect_text(key,rank)
        card.get_meta("rank").text = "%d / %d" % [rank,P.max_rank(key)]
        card.get_meta("price").text = "MAX" if cost == 0 else str(cost)
        card.get_meta("buy").text = "Maxnivå" if cost == 0 else ("Uppgradera" if between else "Efter banan")
        if between and cost > balance:
            card.get_meta("buy").text = "Saknar %d" % (cost-balance)
        card.get_meta("buy").disabled = cost == 0 or balance < cost or not between
        card.get_meta("buy").tooltip_text = "" if balance >= cost else "Du behöver %d mynt till." % (cost-balance)
    for kind in ["adr","bransle"]:
        var unlock_stage := 3 if kind == "adr" else 5
        harbor.set_type_locked(kind,next_stage < unlock_stage,unlock_stage)
    var campaign: Control = cards.campaign
    campaign.get_meta("effect").text = "ADR från bana 3" if next_stage < 3 else "ADR upplåst"
    campaign.get_meta("next_effect").text = "Bränsle från bana 5" if next_stage < 5 else "Alla sex godstyper"
    campaign.get_meta("price").text = "Ingår"
    campaign.get_meta("buy").text = "Spela vidare"
    campaign.get_meta("buy").disabled = true
    if campaign.has_meta("status"):
        campaign.get_meta("status").text = "Alla leveranser upplåsta" if next_stage >= 5 else "Låses upp när du spelar"

func _buy_upgrade(key: String) -> bool:
    if harbor == null or not harbor.visible or (stage_active and not won):
        return false
    if (key == "fleet_adr" and highest_stage+1 < 3) or (key == "fleet_bransle" and highest_stage+1 < 5):
        return false
    var proposal: Dictionary = P.purchase(upgrades,balance,key)
    if not proposal.ok:
        return false
    var old_ranks := upgrades.duplicate(true)
    var old_balance := balance
    upgrades = proposal.levels
    balance = int(proposal.balance)
    unlocked_bays = P.bay_count(int(upgrades.parking))
    if not qa and _store_progress() != OK:
        upgrades = old_ranks
        balance = old_balance
        unlocked_bays = P.bay_count(int(upgrades.parking))
        _toast("Köpet kunde inte sparas. Mynten är kvar.",4.0)
        return false
    Rules.unlock_bays(state,unlocked_bays)
    _update_docks()
    _refresh_harbor()
    _refresh_ui()
    _sound("purchase")
    var card: Control = harbor.get_meta("upgrade_cards")[key]
    var tween := create_tween()
    card.pivot_offset = card.size*.5
    tween.tween_property(card,"scale",Vector2.ONE*1.035,.09)
    tween.tween_property(card,"scale",Vector2.ONE,.17).set_trans(Tween.TRANS_BACK)
    return true

func _stage_name(stage: int) -> String:
    var names := ["Morgonskiftet","Kajrusningen","Farligt bra last","Full fart i hamnen","Bränsledepån","Stora leveranser","Kvällsskiftet","Hamnmästaren"]
    return str(names[mini(maxi(stage-1,0),names.size()-1)])

func _open_cargo_legend() -> void:
    var legend: Control = ui.get_meta("cargo_legend")
    if legend.visible or harbor.visible or won:
        return
    legend_was_paused = paused
    paused = true
    for tween in active_tweens:
        if tween.is_valid():
            tween.pause()
    var values: Dictionary = state.get("config",{}).get("cargo_values",P.BASE_VALUES)
    var kinds: Array = state.get("config",{}).get("types",Rules.TYPES)
    var remaining: Dictionary = Rules.remaining_by_type(state) if campaign_mode else {}
    for kind in Rules.TYPES:
        var available: bool = kind in kinds
        var value: float = float(values.get(kind,P.BASE_VALUES[kind]))
        var formatted := (str(int(value)) if is_equal_approx(value,roundf(value)) else str(snappedf(value,.01))).replace(".",",")
        legend.get_meta("values")[kind].text = "%s mynt / vara" % formatted
        var unlock_stage := 3 if kind == "adr" else (5 if kind == "bransle" else 2)
        legend.get_meta("locks")[kind].text = "%d kvar att lasta" % int(remaining.get(kind,0)) if available and campaign_mode else ("Med på den här banan" if available else "Låses upp på bana %d" % unlock_stage)
        legend.get_meta("symbols")[kind].modulate = Color.WHITE if available else Color(.62,.70,.82,.64)
    legend.get_meta("subtitle").text = "Fast order: större bilar ger färre resor.\nMynt betalas för godset som körs iväg." if campaign_mode else "Matcha varan med lastbilens färg och symbol.\nVarje full leverans ger 10 spelmynt."
    legend.visible = true

func _close_cargo_legend() -> void:
    var legend: Control = ui.get_meta("cargo_legend")
    if not legend.visible:
        return
    legend.visible = false
    paused = legend_was_paused
    for tween in active_tweens:
        if tween.is_valid() and not paused:
            tween.play()

func _reset_machines() -> void:
    for machine in bay_machines:
        machine.root.scale = Vector3.ONE
        machine.forklift.position = Vector3(-1.05,0,1.5)
        machine.arm.rotation.y = 0
        machine.arm.visible = false
        machine.trolley.visible = true
        machine.tail_lift.visible = false

func _update_docks() -> void:
    for bay in range(5):
        var is_open := bay < unlocked_bays
        bay_machines[bay].root.visible = is_open
        dock_targets[bay].collision_layer = 0 if is_open else 2
    if dock_button != null:
        dock_button.text = "Kajer  %d / 5" % unlocked_bays

func _open_shop() -> void:
    if campaign_mode:
        _open_harbor()
        return
    if won or shop.visible:
        return
    shop_was_paused = paused
    paused = true
    modal.visible = false
    for tween in active_tweens:
        if tween.is_valid():
            tween.pause()
    shop.visible = true
    pause_button.text = ">"
    _refresh_shop()

func _close_shop() -> void:
    if not shop.visible:
        return
    shop.visible = false
    paused = shop_was_paused
    if not paused:
        for tween in active_tweens:
            if tween.is_valid():
                tween.play()
    else:
        modal.visible = true
    pause_button.text = ">" if paused else "II"

func _refresh_shop() -> void:
    shop_balance.text = "%d spelmynt" % balance
    for extra in range(2):
        var bay := 3+extra
        var is_owned := bay < unlocked_bays
        var cost := int(L.DOCK_PRICES[bay])
        shop_prices[extra].text = "Upplåst" if is_owned else "%d mynt" % cost
        shop_marks[extra].texture = preload("res://ui_assets.gd").icon("check" if is_owned else "coin")
        shop_buttons[extra].text = "Din kaj" if is_owned else ("Öppna kaj %02d" % (bay+1))
        shop_buttons[extra].disabled = is_owned or bay != unlocked_bays or balance < cost

func _buy_dock(index: int = -1) -> bool:
    if campaign_mode:
        return _buy_upgrade("parking")
    var bay := unlocked_bays if index < 0 else index
    if bay != unlocked_bays or bay < 3 or bay >= 5:
        return false
    var price := int(L.DOCK_PRICES[bay])
    if balance < price:
        _toast("Du behöver %d mynt till för nästa kaj." % (price-balance),3.0)
        return false
    balance -= price
    unlocked_bays += 1
    Rules.unlock_bays(state,unlocked_bays)
    _update_docks()
    _refresh_shop()
    _close_shop()
    _refresh_ui()
    if not qa:
        _save_progress()
    var platform: Node3D = bay_machines[bay].root
    platform.scale = Vector3.ONE*.82
    _tween().tween_property(platform,"scale",Vector3.ONE,.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _puff(Vector3(BAY_X[bay],.15,L.DOCK_Z),Color("78dfb8"),12)
    _toast("Kaj %02d är öppen!  −%d mynt" % [bay+1,price],4.0)
    _sound("depart")
    return true

func _refresh_ui() -> void:
    if state == null or state.is_empty():
        return
    progress_label.text = ("%d / %d pallar" % [int(state.get("cargo_delivered",0)),int(state.cargo_total)]) if campaign_mode else "%d / %d avgångar" % [int(state.delivered),int(state.total)]
    var cargo_count := 0
    for truck in state.trucks:
        var id := int(truck.id)
        cargo_count += int(truck_nodes[id].get_meta("displayed_load",truck.loaded)) if truck_nodes.has(id) else int(truck.loaded)
    cargo_label.text = "%d / %d lastade" % [cargo_count,int(state.cargo_total)]
    progress_bar.max_value = float(state.cargo_total) if campaign_mode else float(state.total)
    progress_bar.value = float(state.get("cargo_delivered",0)) if campaign_mode else float(state.delivered)
    title_label.text = ("Bana %d · %s" % [current_stage,_stage_name(current_stage)]) if campaign_mode else (("Morgonpasset" if level_index == 0 else "Kajrusningen")+"  ·  depå %02d" % (level_index+1))
    _set_wallet(money_label,balance,31)
    dock_button.text = "Kajer  %d / 5" % unlocked_bays
    if ui.has_meta("incoming_count"):
        var incoming: Label = ui.get_meta("incoming_count")
        incoming.text = "%d på väg" % moving_trucks.size()
        incoming.visible = not moving_trucks.is_empty()
    undo_button.disabled = history.is_empty() or (harbor != null and harbor.visible)
    for i in range(2):
        level_buttons[i].modulate = Color("8fe0c4") if i == level_index else Color.WHITE
    for bay in range(5):
        var id := int(state.bays[bay])
        if id == -2:
            bay_labels[bay].text = ""
            bay_labels[bay].modulate = Color("ffd35c")
        elif id == -1:
            bay_labels[bay].text = ""
            bay_labels[bay].modulate = Color("fff9eb")
        else:
            var truck: Dictionary = state.trucks[id]
            var shown := int(truck_nodes[id].get_meta("displayed_load",truck.loaded)) if truck_nodes.has(id) else int(truck.loaded)
            var target := int(truck.get("target_load",truck.capacity))
            bay_labels[bay].text = "%d / %d" % [shown,target] if target > 0 else "Ingen order"
            bay_labels[bay].modulate = Color("fff9eb") if target > 0 else Color("ffb9b1")
        bay_labels[bay].visible = id >= 0 and truck_nodes.has(id) and str(state.trucks[id].status) in ["loading","departing"]
    if ui.has_meta("mission_label"):
        var delivered_cargo := int(state.get("cargo_delivered",0))
        var empty_slots: int = state.belt.count(null)
        var limit := int(state.get("config",{}).get("belt_limit",L.BELT_SLOTS))
        ui.get_meta("mission_label").text = "%sORDER  %d / %d pallar   ·   Band: %d pallar, max %d" % ["BOSS · " if bool(state.get("config",{}).get("boss",false)) else "",delivered_cargo,int(state.cargo_total),L.BELT_SLOTS-empty_slots,limit]
    status_label.visible = (stalled or driving or cargo_focus != "") and not toast_label.visible
    if is_instance_valid(readable_view) and readable_view.legend != null:
        readable_view.legend.visible = not toast_label.visible and not (stalled or driving or cargo_focus != "")
    if stalled:
        status_label.text = "Alla kajer är upptagna av gods som saknas på bandet."
        status_label.add_theme_color_override("font_color",Color("f3b38d"))
    elif driving:
        status_label.text = "På väg till kajen …"
        status_label.add_theme_color_override("font_color",MUTED)
    elif cargo_focus != "":
        var descriptions := {"kyl":"Grön termometer · kylvaror", "frys":"Blå snöflinga · frysta varor", "adr":"Orange faromärke · farligt gods", "timmer":"Lila ram och stockar · timmer", "schakt":"Gult flak · sten och schakt", "bransle":"Rosa tank och droppe · bränsle"}
        status_label.text = str(descriptions.get(cargo_focus,""))
        status_label.add_theme_color_override("font_color",Color(TYPE_COLORS.get(cargo_focus,"bdd0d5")))
    else:
        status_label.text = ""
        status_label.add_theme_color_override("font_color",MUTED)
    preload("res://interface.gd").refresh_support(self)

func _toast(message: String, duration := 3.5) -> void:
    toast_label.text = message
    toast_label.visible = true
    toast_left = duration

func _set_wallet(label: Label, amount: int, base_size: int) -> void:
    if label.get_meta("coin_value",-1) == amount:
        return
    label.set_meta("coin_value",amount)
    var available_width: float = float(label.get_meta("coin_width",label.size.x))
    label.set_meta("coin_width",available_width)
    label.clip_text = true
    label.size.x = available_width
    var digits := str(maxi(amount,0))
    var formatted := ""
    while digits.length() > 3:
        formatted = " "+digits.right(3)+formatted
        digits = digits.left(digits.length()-3)
    label.text = digits+formatted
    var size := base_size
    var face := label.get_theme_font("font")
    while size > 18 and face.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > available_width-4:
        size -= 1
    label.add_theme_font_size_override("font_size",size)

func _toggle_pause() -> void:
    if ui.get_meta("cargo_legend").visible:
        _close_cargo_legend()
        return
    if harbor != null and harbor.visible:
        _close_harbor()
        return
    if won:
        return
    if failed:
        modal.visible = true
        return
    if shop.visible:
        _close_shop()
        return
    paused = not paused
    pause_button.text = ">" if paused else "II"
    for tween in active_tweens:
        if tween.is_valid():
            if paused:
                tween.pause()
            else:
                tween.play()
    if paused:
        _set_modal_view(false)
        modal_title.text = "Skiftet är pausat"
        modal_text.text = ("Bana %d · %d pallar · %d lastbilar\nLeverera godsordern. Bilar kan bli kvar." % [current_stage,int(state.cargo_total),int(state.total)]) if campaign_mode else "Dina lastbilar står kvar.\nFortsätt skiftet eller välj en annan depå."
        modal_action.text = "Fortsätt spela"
        modal.visible = true
        if not qa:
            _save_progress()
    else:
        modal.visible = false

func _set_modal_view(victory: bool, bonus: int = 0) -> void:
    if not modal.has_meta("card"):
        return
    var card: Control = modal.get_meta("card")
    var art: TextureRect = modal.get_meta("harbor_art")
    var reward: Label = modal.get_meta("win_reward")
    card.position = Vector2(90,360) if victory else Vector2(90,288)
    card.size = Vector2(720,600) if victory else Vector2(720,846)
    art.texture = preload("res://ui_assets.gd").icon("medal") if victory else preload("res://ui_assets.gd").harbor_card()
    art.position = Vector2(282,20) if victory else Vector2(204,20)
    art.size = Vector2(156,153) if victory else Vector2(312,153)
    modal.get_meta("cargo_library").visible = not victory
    for item in modal.get_meta("pause_only",[]):
        item.visible = not victory
    if campaign_mode and not victory:
        var pause_only: Array = modal.get_meta("pause_only",[])
        for i in range(mini(3,pause_only.size())):
            pause_only[i].visible = false
        card.position = Vector2(90,325)
        card.size = Vector2(720,750)
    for item in modal.get_meta("pause_actions",[]):
        item.position.y = 620 if campaign_mode else 716
    reward.visible = victory
    reward.text = "+%d spelmynt i skiftbonus" % bonus if bonus > 0 else "Alla leveranser är på väg!"
    if victory and campaign_mode:
        reward.text = "%d spelmynt intjänat\nVaror %d · skiftbonus %d" % [earned,maxi(0,earned-bonus),bonus]
    preload("res://interface.gd").configure_modal(self,victory)

func _modal_continue() -> void:
    if failed:
        _restart_current()
    elif won:
        if campaign_mode:
            _open_harbor()
        else:
            _new_level(1-level_index)
    elif paused:
        _toggle_pause()
    else:
        modal.visible = false

func _toggle_speed() -> void:
    if not test_mode and is_equal_approx(speed,1.0):
        return
    speed = 2.0 if speed == 1.0 else 1.0
    speed_button.text = "2×" if speed > 1 else "1×"
    for tween in active_tweens:
        if tween.is_valid():
            tween.set_speed_scale(speed*qa_multiplier*(_loading_rate() if tween.get_meta("loading",false) else 1.0))

func _change_zoom(amount: float) -> void:
    if campaign_mode and is_instance_valid(readable_view) and not readable_view.is_overview():
        zoom = clampf(zoom+amount,1.0,1.9)
        readable_view.set_zoom(zoom)
        return
    zoom = clampf(zoom+amount,1.0,1.9)
    if is_equal_approx(zoom,1.0):
        _reset_camera()
    else:
        camera.size = base_camera_size/zoom

func _reset_camera() -> void:
    zoom = 1
    camera.size = base_camera_size
    camera.position = Vector3(0,45,41.0)
    camera.look_at(Vector3(0,0,3.6))
    if is_instance_valid(readable_view):
        readable_view.set_zoom(1.0)

func _toggle_view() -> void:
    if not campaign_mode or not is_instance_valid(readable_view):
        _reset_camera()
        return
    readable_view.set_overview(not readable_view.is_overview())
    _reset_camera()
    if ui.has_meta("view_button"):
        ui.get_meta("view_button").text = "Närvy" if readable_view.is_overview() else "Hela"

func _view_ray(screen_position: Vector2) -> Dictionary:
    if is_instance_valid(readable_view):
        return readable_view.screen_ray(screen_position)
    return {"camera":camera,"point":screen_position}

func _screen_position(world_position: Vector3, section := "yard") -> Vector2:
    if is_instance_valid(readable_view):
        return readable_view.project(world_position,section)
    return camera.unproject_position(world_position)

func _input(event: InputEvent) -> void:
    if OS.has_feature("web") and paused and is_instance_valid(modal) and modal.visible and (event is InputEventScreenTouch or event is InputEventMouseButton):
        var hovered := get_viewport().gui_get_hovered_control()
        print("WEB_SETTINGS_POINTER t=",Time.get_ticks_msec()," event=",event.get_class()," device=",event.device," pressed=",event.pressed," pos=",event.position," hovered=",str(hovered.get_path()) if hovered != null else "none"," effects_rect=",sound_button.get_global_rect()," music_rect=",ui.get_meta("music_toggle").get_global_rect())
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_SPACE: _toggle_pause()
            KEY_Z: _undo()
            KEY_R: _restart_current()
            KEY_ESCAPE:
                if paused:
                    _toggle_pause()
            KEY_M: _toggle_sound()
            KEY_F: _toggle_view()
            KEY_0: _reset_camera()
    if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and zoom > 1:
        var movement: Vector2 = event.relative
        if campaign_mode and is_instance_valid(readable_view) and not readable_view.is_overview():
            readable_view.pan(movement)
        else:
            camera.position += Vector3(-movement.x*.035/zoom,0,-movement.y*.035/zoom)
    elif event is InputEventMouseMotion and not paused and not won:
        _hover_type(event.position)

func _unhandled_input(event: InputEvent) -> void:
    # GUI buttons retain mouse emulation. World picking handles the original
    # pointer only, preventing one mobile tap from also activating its copy.
    if event.device == InputEvent.DEVICE_ID_EMULATION:
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _change_zoom(.10)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _change_zoom(-.10)
        elif event.button_index == MOUSE_BUTTON_LEFT:
            _pick(event.position)
    elif event is InputEventScreenTouch and event.pressed:
        _pick(event.position)

func _pick(screen_position: Vector2) -> void:
    if paused or won or modal.visible:
        return
    var ray := _view_ray(screen_position)
    if ray.is_empty():
        return
    var view_camera: Camera3D = ray.camera
    var origin := view_camera.project_ray_origin(ray.point)
    var direction := view_camera.project_ray_normal(ray.point)
    var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*150.0,7)
    var result := get_world_3d().direct_space_state.intersect_ray(query)
    if not result.is_empty() and result.collider.has_meta("truck_id"):
        var id := int(result.collider.get_meta("truck_id"))
        if helicopter_mode:
            _rescue_truck(id)
        else:
            _dispatch(id)
    elif not result.is_empty() and result.collider.has_meta("obstacle_id"):
        _move_obstacle(int(result.collider.get_meta("obstacle_id")))
    elif not result.is_empty() and result.collider.has_meta("buy_bay"):
        _open_shop()

func _hover_type(screen_position: Vector2) -> void:
    cargo_focus = ""
    if screen_position.y < 140 or screen_position.y > 1200:
        return
    var ray := _view_ray(screen_position)
    if ray.is_empty():
        return
    var view_camera: Camera3D = ray.camera
    var origin := view_camera.project_ray_origin(ray.point)
    var direction := view_camera.project_ray_normal(ray.point)
    var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*150.0,1)
    var result := get_world_3d().direct_space_state.intersect_ray(query)
    if not result.is_empty() and result.collider.has_meta("truck_id"):
        cargo_focus = str(state.trucks[int(result.collider.get_meta("truck_id"))].type)
        return
    for id in cargo_nodes:
        var node: Node3D = cargo_nodes[id]
        if _screen_position(node.global_position+Vector3.UP*.4,"dock").distance_to(screen_position) < 24:
            cargo_focus = str(node.get_meta("kind",""))
            return

func _win() -> void:
    won = true
    toast_left = 0
    toast_label.visible = false
    var bonus := 0
    var bonus_key := ("campaign:v1:win:%d" % current_stage) if campaign_mode else ("v2:win:%d" % level_index)
    if not reward_claims.has(bonus_key):
        reward_claims[bonus_key] = true
        bonus = P.stage_bonus(current_stage) if campaign_mode else 100
        balance += bonus
        earned += bonus
    if campaign_mode:
        highest_stage = maxi(highest_stage,current_stage)
        stage_active = false
    _refresh_ui()
    if not qa:
        _save_progress()
    _set_modal_view(true,bonus)
    modal_title.text = "Skiftet klart!"
    var minutes := int(elapsed)/60
    var seconds := int(elapsed)%60
    modal_text.text = "%d pallar · %d körningar\nSkifttid %d:%02d" % [int(state.cargo_total),int(state.delivered),minutes,seconds]
    modal_action.text = "Till hamnen & uppgraderingarna" if campaign_mode else "Spela %d-lastbilarsdepån" % int(L.COUNTS[1-level_index])
    modal.visible = true
    preload("res://interface.gd").celebrate(ui)
    _sound("win")

func _progress_path() -> String:
    if v4_round == "07":
        return "res://qa/v4/_native-resume.cfg"
    return "user://hamnskiftet.cfg"

func _load_progress() -> void:
    var config := ConfigFile.new()
    if config.load(_progress_path()) == OK:
        balance = maxi(0,int(config.get_value("progress","coins",120)))
        if int(config.get_value("progress","schema",1)) < 2:
            balance = maxi(120,balance)
        unlocked_bays = clampi(int(config.get_value("progress","bays",3)),3,5)
        var claims = config.get_value("progress","rewards",{})
        reward_claims = claims if claims is Dictionary else {}
        upgrades = P.sanitize(config.get_value("campaign","upgrades",{}))
        upgrades.parking = maxi(int(upgrades.parking),unlocked_bays-3)
        unlocked_bays = P.bay_count(int(upgrades.parking))
        highest_stage = maxi(0,int(config.get_value("campaign","highest_stage",0)))
        saved_active_upgrades = P.sanitize(config.get_value("campaign","active_upgrades",upgrades))
        saved_campaign_state = CampaignSave.validate(config.get_value("campaign","state",{}),saved_active_upgrades,highest_stage)
        saved_elapsed = maxf(0.0,float(config.get_value("campaign","elapsed",0.0)))
        saved_earned = maxi(0,int(config.get_value("campaign","earned",0)))
        sound_enabled = bool(config.get_value("settings","sound",true))
        music_enabled = bool(config.get_value("settings","music",true))
        _refresh_audio_settings()
    _save_progress()

func _restore_campaign() -> bool:
    if saved_campaign_state.is_empty():
        return false
    var snapshot := saved_campaign_state.duplicate(true)
    _new_level(int(snapshot.stage)-1,snapshot.config,snapshot)
    active_upgrades = saved_active_upgrades.duplicate(true)
    elapsed = saved_elapsed
    earned = saved_earned
    stage_active = true
    saved_campaign_state.clear()
    _refresh_ui()
    return true

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and not qa and not state.is_empty():
        _save_progress()

func _save_progress() -> void:
    var error := _store_progress()
    if _web_settings_save_pending:
        _web_settings_save_pending = false
        print("WEB_SETTINGS_STORE t=",Time.get_ticks_msec()," result=",error," sound=",sound_enabled," music=",music_enabled," persistent=",OS.is_userfs_persistent())
    if error != OK:
        push_warning("Progress could not be saved: %s" % error_string(error))

func _store_progress() -> Error:
    var config := ConfigFile.new()
    config.set_value("progress","coins",balance)
    config.set_value("progress","schema",7)
    config.set_value("progress","bays",unlocked_bays)
    config.set_value("progress","rewards",reward_claims)
    config.set_value("campaign","upgrades",upgrades)
    config.set_value("campaign","highest_stage",highest_stage)
    var active := campaign_mode and stage_active and not won
    var snapshot: Dictionary = state if active else saved_campaign_state
    if not snapshot.is_empty():
        config.set_value("campaign","state",snapshot)
        config.set_value("campaign","active_upgrades",active_upgrades if active else saved_active_upgrades)
        config.set_value("campaign","elapsed",elapsed if active else saved_elapsed)
        config.set_value("campaign","earned",earned if active else saved_earned)
    config.set_value("settings","sound",sound_enabled)
    config.set_value("settings","music",music_enabled)
    var path := ProjectSettings.globalize_path(_progress_path())
    var error := config.save(path+".tmp")
    if error != OK:
        return error
    return DirAccess.rename_absolute(path+".tmp",path)

func _build_audio() -> void:
    soundscape = AudioKit.build(self)
    _refresh_audio_settings()

func _sound(name_value: String, cargo_type: String = "") -> void:
    if not sound_enabled or qa or soundscape == null:
        return
    soundscape.play_event(name_value,cargo_type)

func _refresh_audio_settings() -> void:
    if sound_button != null:
        sound_button.text = "Effekter på" if sound_enabled else "Effekter av"
    if ui != null and ui.has_meta("music_toggle"):
        ui.get_meta("music_toggle").text = "Musik på" if music_enabled else "Musik av"
    if soundscape != null:
        soundscape.set_sfx_enabled(sound_enabled and not qa)
        soundscape.set_music_enabled(music_enabled and not qa)

func _web_settings_debug_setup() -> void:
    if not OS.has_feature("web"):
        return
    for key in ["effects","music"]:
        var button: Button = sound_button if key == "effects" else ui.get_meta("music_toggle")
        button.button_down.connect(_web_settings_button_trace.bind(key,"down"))
        button.button_up.connect(_web_settings_button_trace.bind(key,"up"))

func _web_settings_button_trace(key: String, phase: String) -> void:
    print("WEB_SETTINGS_BUTTON t=",Time.get_ticks_msec()," key=",key," phase=",phase," sound=",sound_enabled," music=",music_enabled)

func _toggle_sound() -> void:
    sound_enabled = not sound_enabled
    _refresh_audio_settings()
    if OS.has_feature("web"):
        print("WEB_SETTINGS_TOGGLE t=",Time.get_ticks_msec()," key=effects sound=",sound_enabled," music=",music_enabled," qa=",qa)
        _web_settings_save_pending = true
    if not qa:
        _save_progress()

func _toggle_music() -> void:
    music_enabled = not music_enabled
    _refresh_audio_settings()
    if OS.has_feature("web"):
        print("WEB_SETTINGS_TOGGLE t=",Time.get_ticks_msec()," key=music sound=",sound_enabled," music=",music_enabled," qa=",qa)
        _web_settings_save_pending = true
    if not qa:
        _save_progress()

func _shot(name_value: String) -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    # macOS can skip draws for an occluded game window. Request one real
    # render before waiting so native QA never stalls behind another app.
    RenderingServer.call_deferred("force_draw",false,0.0)
    await RenderingServer.frame_post_draw
    var image_value := get_viewport().get_texture().get_image()
    var path := ProjectSettings.globalize_path("res://qa/%s.png" % name_value)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    image_value.save_png(path)
    print("QA_SCREENSHOT ",path)

func _capture_handoff() -> void:
    await get_tree().create_timer(.8).timeout
    await _shot("v7/live-spel")
    print("HANDOFF_READY campaign=",campaign_mode," stage=",current_stage," balance=",balance)

func _v7_new(stage: int) -> void:
    upgrades = P.defaults()
    unlocked_bays = 3
    balance = 500
    test_mode = false
    qa_multiplier = 1.0
    _new_level(stage-1,P.stage_config(stage,upgrades))
    stage_active = true
    _refresh_ui()
    await get_tree().physics_frame
    await get_tree().physics_frame

func _v7_play_certificate(supplied_steps: Array = []) -> void:
    var steps: Array = state.solution_steps.duplicate(true) if supplied_steps.is_empty() else supplied_steps.duplicate(true)
    for step in steps:
        if str(step.action) == "dispatch":
            assert(Rules.can_dispatch(state,int(step.id)),"Certified next dispatch is physically unblocked in the logical yard")
            _dispatch(int(step.id))
        elif str(step.action) == "wait":
            var guard := 0
            while not Rules.step_ready(state,step):
                await get_tree().process_frame
                guard += 1
                assert(guard < 9000 and not failed,"A rescue-free certified route must complete in the real controller")
        elif str(step.action) == "move_obstacle":
            assert(_move_obstacle(int(step.id)))
    assert(won and Rules.is_won(state),"The real controller ships the full fixed order with spare trucks left")

func _run_v7_review() -> void:
    await get_tree().create_timer(.4).timeout
    match int(v7_round):
        1:
            await _v7_new(3)
            await _shot("v7/01-normalspel-utan-bottenmeny")
            assert(not ui.get_meta("test_toolbar").visible)
            assert(bay_labels.all(func(label): return not label.visible))
            _open_cargo_legend()
            await _shot("v7/01-gods-fast-order")
            _close_cargo_legend()
            _toggle_pause()
            await _shot("v7/02-paus-priser")
            _toggle_test_mode()
            _toggle_pause()
            await _shot("v7/03-endast-testverktyg")
            assert(ui.get_meta("test_toolbar").visible)
        2:
            await _v7_new(3)
            var id := int(state.solution[0])
            _rescue_truck(id)
            await get_tree().create_timer(1.45).timeout
            paused = true
            await _shot("v7/04-helikopter-lyft")
            paused = false
            while rescue_busy: await get_tree().process_frame
            assert(balance == 500 and state.rescue_used == 1)
            assert(await _rescue_truck(id))
            assert(balance == 450 and state.rescue_used == 2)
            _paid_undo()
            assert(balance == 350 and state.rescue_used == 2)
            await _shot("v7/05-helikopter-och-betald-angra")
        3:
            await _v7_new(3)
            qa_multiplier = 6.0
            for id in [0,1,2]:
                assert(Rules.can_dispatch(state,id))
                _dispatch(id)
            var guard := 0
            while not failed:
                await get_tree().process_frame
                guard += 1
                assert(guard < 6000,"Bad legal choices must reach an actual failure screen")
            await _shot("v7/06-verklig-forlust")
            assert(not ui.get_meta("test_toolbar").visible)
            _modal_continue()
            assert(not failed and state.cargo_delivered == 0)
            await _shot("v7/07-gratis-omstart")
        4,5:
            var stage := 5 if int(v7_round) == 4 else 8
            await _v7_new(stage)
            await _shot("v7/%02d-boss-eller-stor-order" % stage)
            qa_multiplier = 8.0
            var first_id := int(state.solution_steps[0].id)
            _dispatch(first_id)
            await get_tree().create_timer(.18).timeout
            await _shot("v7/%02d-korning-pa-asfalt" % stage)
            var guard := 0
            while str(state.trucks[first_id].status) != "done":
                await get_tree().process_frame
                guard += 1
                assert(guard < 9000 and not failed)
            var steps: Array = state.solution_steps.duplicate(true)
            steps.remove_at(0)
            if not steps.is_empty() and str(steps[0].action) == "wait": steps.remove_at(0)
            await _v7_play_certificate(steps)
            assert(state.rescue_used == 0 and state.delivered < state.total)
            assert(balance == 500+P.remaining_income(stage,state.manifest,state.config.cargo_values,{}),"Real departures pay the fixed manifest value, independent of surplus truck count")
            await _shot("v7/%02d-order-klar-utan-heli" % stage)
            if int(v7_round) == 4:
                _open_harbor()
                var next_config: Dictionary = P.stage_config(stage+1,upgrades)
                var expected: int = P.remaining_income(stage+1,next_config.manifest,next_config.cargo_values,reward_claims)
                assert(("%d mynt att tjäna" % expected) in harbor.get_meta("subtitle").text)
                await _shot("v7/09-dyrare-uppgraderingar")
        _:
            assert(false,"Unknown V7 review case")
    print("V7_NATIVE_REVIEW_OK case=",v7_round," delivered_goods=",state.get("cargo_delivered",0)," parked_trucks=",state.trucks.filter(func(truck): return str(truck.status) == "yard").size()," rescue_used=",state.get("rescue_used",0)," wallet=",balance)
    get_tree().quit()

func _run_v6_review() -> void:
    await get_tree().create_timer(.6).timeout
    if v6_round == "04":
        await _run_v6_motion_review()
        get_tree().quit()
        return
    upgrades = P.defaults()
    balance = 120
    unlocked_bays = 3
    _new_level(0,P.stage_config(1,upgrades))
    paused = true
    await _shot("readability/01-forsta-depan")
    var board: Rect2i = state.config.spawn_bounds
    var lower := Vector3(L.YARD_BOUNDS.position.x+float(board.position.x)*CELL,0,L.YARD_BOUNDS.position.y+float(board.position.y)*CELL)
    var upper := lower+Vector3(float(board.size.x)*CELL,0,float(board.size.y)*CELL)
    var screen_span := (_screen_position(upper)-_screen_position(lower)).abs()
    assert(screen_span.x > 600 and screen_span.y > 500,"First depot fills most of the playable area")
    print("READABILITY_FIRST_FLOOR_PIXELS ",screen_span)
    _toggle_view()
    await _shot("readability/02-hela-hamnen")
    _toggle_view()
    var all_upgrades := P.defaults()
    for key in P.FLEET_KEYS: all_upgrades[key] = 3
    all_upgrades.parking = 2
    upgrades = all_upgrades
    unlocked_bays = 5
    _new_level(7,P.stage_config(8,upgrades))
    paused = true
    await _shot("readability/03-trettio-lastbilar")
    _open_harbor()
    harbor.select_tab("trucks")
    await _shot("readability/04-lastbilar-i-hamnen")
    print("READABILITY_REVIEW_OK ",v6_round," first=10 largest=30 views=shared-world glyphs=6")
    get_tree().quit()

func _run_v6_motion_review() -> void:
    upgrades = P.defaults()
    unlocked_bays = 3
    assert(_start_stage(1))
    qa_multiplier = 1.0
    await get_tree().physics_frame
    await get_tree().physics_frame
    var first_wave: Array = []
    for id in state.solution.duplicate():
        if first_wave.size() >= 3: break
        if Rules.can_dispatch(state,int(id)):
            var point := _screen_position(truck_nodes[int(id)].global_position+Vector3.UP*.55)
            _pick(point)
            assert(str(state.trucks[int(id)].status) == "driving","Real enlarged-view picking dispatches the selected truck")
            first_wave.append(int(id))
    assert(first_wave.size() == 3 and moving_trucks.size() == 3)
    await get_tree().create_timer(.4).timeout
    await _shot("readability/05-tre-lastbilar-i-rorelse")
    qa_multiplier = 6.0
    var guard := 0
    while loading_in_flight.values().all(func(value): return int(value) == 0):
        await get_tree().process_frame
        guard += 1
        assert(guard < 5000,"A real compatible cargo reaches its crane")
    paused = true
    for tween in active_tweens:
        if tween.is_valid(): tween.pause()
    await _shot("readability/06-verklig-lastning")
    paused = false
    for tween in active_tweens:
        if tween.is_valid(): tween.play()
    qa_multiplier = 12.0
    await _v5_wait_done(first_wave)
    for id in state.solution.duplicate():
        if str(state.trucks[int(id)].status) == "done": continue
        assert(Rules.can_dispatch(state,int(id)))
        _dispatch(int(id))
        await _v5_wait_done([int(id)])
    assert(won and Rules.is_won(state) and state.delivered == 10 and balance == 249,"Real first stage delivers all30 goods and pays exactly129 coins")
    await _shot("readability/07-spelad-bana-klar")
    print("READABILITY_MOTION_OK actual-picks=3 simultaneous=",peak_moving," delivered=",state.delivered," goods=",state.cargo_total," balance=",balance)

func _run_v5_review() -> void:
    await get_tree().create_timer(.6).timeout
    if int(v5_round) >= 2:
        await _run_v5_case(int(v5_round))
        print("V5_REVIEW_OK ",v5_round," peak_moving=",peak_moving," peak_load_queue=",peak_load_queue)
        get_tree().quit()
        return
    assert(_start_stage(1) and state.total == 10)
    qa_multiplier = 1
    var starts: Dictionary = {}
    for id in state.solution.duplicate():
        if moving_trucks.size() >= 3:
            break
        if Rules.can_dispatch(state,int(id)):
            starts[int(id)] = truck_nodes[int(id)].position
            _dispatch(int(id))
    assert(moving_trucks.size() == 3 and state.bays.count(-1) == 0,"Three same-frame selections reserve three distinct docks")
    await get_tree().create_timer(.45).timeout
    var changed := 0
    for id in starts:
        if truck_nodes[id].position.distance_to(starts[id]) > .05:
            changed += 1
    assert(changed >= 2,"Multiple trucks actually move together, not just logical queue entries")
    await _shot("v5/%s-samtidig-trafik" % v5_round)
    qa_multiplier = 12
    var guard := 0
    while starts.keys().any(func(id): return str(state.trucks[int(id)].status) != "done"):
        await get_tree().process_frame
        guard += 1
        if guard%600 == 0:
            print("V5_TRAFFIC_WAIT ",guard," status=",starts.keys().map(func(id): return state.trucks[int(id)].status)," apron=",traffic.apron_owner," actors=",motion_actors)
        assert(guard < 6000,"Parallel arrivals and departures must finish")
    await _shot("v5/%s-tre-leveranser" % v5_round)
    print("V5_REVIEW_OK ",v5_round," simultaneous=",peak_moving," delivered=",state.delivered)
    get_tree().quit()

func _v5_wait_done(ids: Array) -> void:
    var guard := 0
    while ids.any(func(id): return str(state.trucks[int(id)].status) != "done"):
        await get_tree().process_frame
        guard += 1
        assert(guard < 10000,"Reviewed deliveries must finish")

func _run_v5_case(number: int) -> void:
    if number == 2:
        highest_stage = 7
        upgrades.parking = 2
        for key in P.FLEET_KEYS:
            upgrades[key] = 3
        assert(_start_stage(8) and state.total == 30)
        var chosen: Array = []
        for id in state.solution:
            if chosen.size() == 5:
                break
            if Rules.can_dispatch(state,int(id)):
                chosen.append(int(id))
                _dispatch(int(id))
        assert(chosen.size() == 5 and moving_trucks.size() == 5)
        await get_tree().create_timer(.5).timeout
        await _shot("v5/02-fem-samtidiga")
        qa_multiplier = 14
        await _v5_wait_done(chosen)
        assert(state.delivered == 5)
        await _shot("v5/02-kajer-och-korbanor")
    elif number == 3:
        for key in P.FLEET_KEYS:
            upgrades[key] = 3
        upgrades.belt = 6
        assert(_start_stage(1))
        qa_multiplier = 6
        var first := int(state.solution[0])
        _dispatch(first)
        var guard := 0
        while int(loading_in_flight.get(first,0)) < 2 and state.trucks[first].status != "done":
            await get_tree().process_frame
            guard += 1
            assert(guard < 6000)
        _toggle_pause()
        modal.visible = false
        _change_zoom(.45)
        camera.position.z -= 8
        await _shot("v5/03-stottad-lastko")
        var held: Dictionary = state.duplicate(true)
        await get_tree().create_timer(.12).timeout
        assert(state == held)
        _toggle_pause()
        _reset_camera()
        await _v5_wait_done([first])
        assert(int(state.trucks[first].loaded) == 6 and int(loading_in_flight[first]) == 0)
        assert(peak_load_queue >= 1)
        await _shot("v5/03-sista-lyftet-klart")
    elif number == 4:
        highest_stage = 2
        assert(_start_stage(3) and state.total == 14 and obstacle_nodes.size() == 3)
        await _shot("v5/04-hinder-och-port")
        var before: Dictionary = state.duplicate(true)
        assert(_move_obstacle(2))
        await get_tree().create_timer(.17).timeout
        await _shot("v5/04-port-mitt-i-rorelse")
        await get_tree().create_timer(.25).timeout
        _undo()
        assert(state == before and not obstacle_motion)
        await _shot("v5/04-aterstalld-port")
        qa_multiplier = 18
        for step in state.solution_steps.duplicate(true):
            var guard := 0
            if step.action == "move_obstacle":
                while not _move_obstacle(int(step.id)):
                    await get_tree().process_frame
                    guard += 1
                    assert(guard < 10000)
            else:
                while not Rules.can_dispatch(state,int(step.id)):
                    await get_tree().process_frame
                    guard += 1
                    assert(guard < 10000)
                _dispatch(int(step.id))
        await _v5_wait_done(state.solution)
        assert(won and Rules.is_won(state))
        await _shot("v5/04-hinderbana-lost")
    elif number == 5:
        harbor.select_tab("trucks")
        await _shot("v5/05-resursspecifika-lastbilar")
        balance = 1000
        assert(_buy_upgrade("fleet_timmer") and upgrades.fleet_timmer == 1 and upgrades.fleet_kyl == 0)
        _refresh_harbor()
        await _shot("v5/05-endast-timmer-uppgraderad")
        assert(_start_stage(1))
        for truck in state.trucks:
            assert(int(truck.capacity) == (4 if truck.type == "timmer" else 3))
        _toggle_pause()
        soundscape.set_sfx_enabled(true)
        soundscape.set_music_enabled(true)
        for kind in Rules.TYPES:
            assert(soundscape.play_event("load",str(kind)))
        await get_tree().create_timer(.08).timeout
        var mix: Dictionary = soundscape.get_mix_state()
        assert(mix.music_playing and int(mix.active_voices) >= 6)
        await _shot("v5/05-musik-och-effekter")
        soundscape.set_sfx_enabled(false)
        assert(soundscape.get_mix_state().music_playing)
        soundscape.set_music_enabled(false)
        print("V5_AUDIO_NATIVE_OK ",mix)
    elif number == 6:
        await _shot("v5/06-slutlig-hamn")
        assert(_start_stage(1))
        qa_multiplier = 20
        for step in state.solution_steps.duplicate(true):
            var guard := 0
            while not Rules.can_dispatch(state,int(step.id)):
                await get_tree().process_frame
                guard += 1
                assert(guard < 10000)
            _dispatch(int(step.id))
        await _v5_wait_done(state.solution)
        assert(won and state.delivered == 10 and balance == 249)
        await _shot("v5/06-seger-kort-bana")
        modal_action.pressed.emit()
        harbor.select_tab("trucks")
        assert(_buy_upgrade("fleet_timmer") and _buy_upgrade("fleet_kyl"))
        harbor.select_tab("harbor")
        assert(_buy_upgrade("loader") and balance == 44)
        await get_tree().create_timer(.3).timeout
        await _shot("v5/06-kop-for-intjanade-mynt")
        harbor.get_meta("play").pressed.emit()
        assert(current_stage == 2 and state.total == 12)
        for truck in state.trucks:
            assert(truck.capacity == (4 if truck.type in ["timmer","kyl"] else 3))
        qa_multiplier = 1
        await get_tree().create_timer(.25).timeout
        await _shot("v5/06-bana-tva")

func _run_qa() -> void:
    await get_tree().create_timer(1.2).timeout
    await _shot("v3-01-64-lastbilar")
    var blocked := -1
    for truck in state.trucks:
        if Rules.blocker_id(state,int(truck.id)) >= 0:
            blocked = int(truck.id)
            break
    _dispatch(blocked)
    assert(int(state.moves) == 0,"Blocked truck must remain in the yard")
    var first := int(state.solution[0])
    _dispatch(first)
    await get_tree().create_timer(.12).timeout
    _undo()
    assert(int(state.moves) == 0 and not driving,"Undo cancels active driving")
    await get_tree().create_timer(.3).timeout
    _dispatch(first)
    while driving:
        await get_tree().process_frame
    assert(str(state.trucks[first].status) == "loading","Arrival reaches a reserved loading bay")
    await get_tree().create_timer(1.0).timeout
    await _shot("v3-02-lastning")
    _toggle_pause()
    var old_ticks := int(state.ticks)
    await get_tree().create_timer(.15).timeout
    assert(int(state.ticks) == old_ticks,"Pause freezes the belt")
    _toggle_pause()
    _new_level(1)
    assert(state.trucks.size() == int(L.COUNTS[1]) and not driving and history.is_empty(),"Level change clears active traffic")
    await get_tree().create_timer(.7).timeout
    await _shot("v3-03-88-lastbilar")
    _open_shop()
    await _shot("v3-04-kajbutik")
    balance = 400
    assert(_buy_dock(3),"Fourth dock can be bought with coins")
    assert(_buy_dock(4),"Fifth dock can be bought with coins")
    await get_tree().create_timer(.6).timeout
    await _shot("v3-05-fem-kajer")
    if "--qa-full" in OS.get_cmdline_user_args():
        unlocked_bays = 3
        _new_level(0)
        qa_multiplier = 14.0
        var solution: Array = state.solution.duplicate()
        for id in solution:
            var guard := 0
            while driving or -1 not in state.bays:
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000,"Traffic must settle")
            _dispatch(int(id))
            guard = 0
            while str(state.trucks[int(id)].status) != "done":
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000,"A known solution truck must depart")
        assert(Rules.is_won(state) and won,"The real animated controller completes the entire depot")
        await _shot("v3-06-klar-depa")
        print("TRUCK_CONTROLLER_FULL_WIN_OK ",state.delivered," trucks ",state.cargo_total," loads")
    print("TRUCK_VISUAL_QA_OK")
    get_tree().quit()

func _run_review() -> void:
    await get_tree().create_timer(.8).timeout
    print("REVIEW_RENDER ",get_viewport().get_texture().get_size()," window ",DisplayServer.window_get_size()," usable ",DisplayServer.screen_get_usable_rect())
    await _shot("review/r%s-depa" % review_round)
    _open_shop()
    await _shot("review/r%s-kajer" % review_round)
    _close_shop()
    _toggle_pause()
    await _shot("review/r%s-paus" % review_round)
    _toggle_pause()
    _new_level(1)
    await get_tree().create_timer(.5).timeout
    await _shot("review/r%s-stor-depa" % review_round)
    _new_level(0)
    var first := int(state.solution[0])
    _dispatch(first)
    while driving:
        await get_tree().process_frame
    var guard := 0
    while int(state.trucks[first].loaded) == 0:
        await get_tree().process_frame
        guard += 1
        assert(guard < 6000,"Review must see an actual compatible belt load")
    await get_tree().create_timer(.40).timeout
    await _shot("review/r%s-lastning" % review_round)
    if "--motion-all" in OS.get_cmdline_user_args():
        _new_level(0)
        qa_multiplier = 8.0
        for id in state.solution.duplicate():
            guard = 0
            while driving or -1 not in state.bays:
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000,"Motion review traffic must settle")
            _dispatch(int(id))
            guard = 0
            while str(state.trucks[int(id)].status) != "done":
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000,"Motion review must deliver its truck")
            if review_motion_done.size() == 6:
                break
        assert(review_motion_done.size() == 6,"All six cargo transfer animations were captured")
    if "--review-docks" in OS.get_cmdline_user_args():
        qa_multiplier = 1.0
        balance = 400
        _open_shop()
        _buy_dock(3)
        _buy_dock(4)
        await get_tree().create_timer(.8).timeout
        await _shot("review/r%s-fem-kajer" % review_round)
        _open_shop()
        await _shot("review/r%s-agda-kajer" % review_round)
        _close_shop()
    if "--review-victory" in OS.get_cmdline_user_args():
        # Isolated UI-state fixture. The actual full controller win is covered
        # separately by --review-full, not claimed by this layout-only image.
        _new_level(0)
        for truck in state.trucks:
            truck.status = "done"
            truck.loaded = truck.capacity
        state.delivered = state.total
        for node in truck_nodes.values():
            node.free()
        truck_nodes.clear()
        for node in cargo_nodes.values():
            node.free()
        cargo_nodes.clear()
        for node in feed_nodes:
            node.free()
        feed_nodes.clear()
        state.belt.fill(null)
        state.feed_left.clear()
        state.feed_right.clear()
        for bay in range(state.bays.size()):
            state.bays[bay] = -1 if bay < unlocked_bays else -2
        _win()
        await _shot("review/r%s-seger-layout" % review_round)
        _new_level(0)
        _toggle_pause()
        await _shot("review/r%s-paus-efter-seger" % review_round)
    if "--review-full" in OS.get_cmdline_user_args():
        # Capture the final door-entry stage at real speed, before completing
        # a full authored depot with the actual controller and animations.
        for kind in ["kyl","frys"]:
            qa_multiplier = 1.0
            unlocked_bays = 3
            _new_level(0)
            var cold_id := -1
            for truck in state.trucks:
                if str(truck.type) == kind and Rules.can_dispatch(state,int(truck.id)):
                    cold_id = int(truck.id)
                    break
            assert(cold_id >= 0,"Both cold types have a free route for the door-entry review")
            _dispatch(cold_id)
            while driving:
                await get_tree().process_frame
            while int(state.trucks[cold_id].loaded) == 0:
                await get_tree().process_frame
            await get_tree().create_timer(.65).timeout
            await _shot("review/r%s-baklastning-%s" % [review_round,kind])
        qa_multiplier = 14.0
        unlocked_bays = 3
        _new_level(0)
        for id in state.solution.duplicate():
            guard = 0
            while driving or -1 not in state.bays:
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000,"Final review traffic must settle")
            _dispatch(int(id))
            guard = 0
            while str(state.trucks[int(id)].status) != "done":
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000,"Final review truck must finish")
        assert(won and Rules.is_won(state),"Final visual review completes the whole depot")
        await _shot("review/r%s-seger" % review_round)
        print("TRUCK_REVIEW_FULL_WIN_OK ",state.delivered," trucks ",state.cargo_total," loads")
    print("REVIEW_FPS ",Engine.get_frames_per_second()," draw_calls ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
    print("VISUAL_REVIEW_CAPTURED ",review_round)
    get_tree().quit()

func _capture_review_motion(kind: String) -> void:
    await get_tree().create_timer(.34/(speed*qa_multiplier)).timeout
    await _shot("review/r%s-lyft-%s" % [review_round,kind])
    review_motion_done[kind] = true

func _run_v4_review() -> void:
    await get_tree().create_timer(.8).timeout
    if int(v4_round) >= 3:
        await _run_v4_case(int(v4_round))
        print("V4_REVIEW_OK ",v4_round," draw_calls ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," fps ",Engine.get_frames_per_second())
        get_tree().quit()
        return
    await _shot("v4/%s-hamn" % v4_round)
    var old_balance := balance
    assert(_buy_upgrade("fleet"),"First fleet upgrade is affordable")
    assert(balance == old_balance-70 and int(upgrades.fleet) == 1,"Upgrade charges exact earned-coin price")
    await get_tree().create_timer(.4).timeout
    await _shot("v4/%s-kop" % v4_round)
    _start_stage()
    assert(campaign_mode and state.trucks.size() == 28,"Real campaign starts stage one")
    await get_tree().create_timer(.5).timeout
    await _shot("v4/%s-bana" % v4_round)
    _toggle_pause()
    await _shot("v4/%s-paus" % v4_round)
    _toggle_pause()
    _open_harbor()
    assert(not _buy_upgrade("belt"),"Upgrades are bought only between stages")
    await _shot("v4/%s-pausad-hamn" % v4_round)
    _close_harbor()
    print("V4_REVIEW_OK ",v4_round," draw_calls ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," fps ",Engine.get_frames_per_second())
    get_tree().quit()

func _run_v4_case(round_number: int) -> void:
    if round_number == 3:
        assert(_start_stage(1))
        await _shot("v4/03-aktiv-depa")
        ui.get_meta("cargo_legend_button").pressed.emit()
        assert(ui.get_meta("cargo_legend").visible and paused)
        var frozen: Dictionary = state.duplicate(true)
        await get_tree().create_timer(.15).timeout
        assert(state == frozen,"Goods legend freezes actual inventory")
        await _shot("v4/03-gods-och-mynt")
        ui.get_meta("cargo_legend").get_meta("close").pressed.emit()
        assert(not paused and not ui.get_meta("cargo_legend").visible)
        qa_multiplier = 6
        var first: int = int(state.solution[0])
        _dispatch(first)
        var guard := 0
        while str(state.trucks[first].status) == "driving":
            await get_tree().process_frame
            guard += 1
            assert(guard < 6000)
        await _shot("v4/03-lastning")
        while str(state.trucks[first].status) != "done":
            await get_tree().process_frame
            guard += 1
            assert(guard < 12000)
        assert(balance == 120+P.delivery_reward(state.trucks[first]))
        await _shot("v4/03-levererat")
    elif round_number == 4:
        await _shot("v4/04-inkomst-fore")
        assert(_buy_upgrade("warehouse") and balance == 20)
        await get_tree().create_timer(.3).timeout
        await _shot("v4/04-vardeuppgradering")
        assert(_start_stage(1))
        await get_tree().process_frame
        await _shot("v4/04-direkt-spelstart")
        _open_cargo_legend()
        assert(ui.get_meta("cargo_legend").get_meta("values").kyl.text == "3,75 mynt / vara")
        await _shot("v4/04-uppgraderade-varuvarden")
        _close_cargo_legend()
        qa_multiplier = 10
        var first: int = int(state.solution[0])
        _dispatch(first)
        var guard := 0
        while str(state.trucks[first].status) != "done":
            await get_tree().process_frame
            guard += 1
            assert(guard < 12000)
        assert(balance == 20+P.delivery_reward(state.trucks[first]))
        await _shot("v4/04-uppgraderad-leverans")
    elif round_number == 5:
        # Visual fixtures for later unlocks; no player profile is modified.
        assert(not _start_stage(3),"An actual new campaign cannot skip to ADR")
        highest_stage = 2
        assert(_start_stage(3) and "adr" in state.config.types and "bransle" not in state.config.types)
        qa_multiplier = 12
        await get_tree().create_timer(.8).timeout
        await _shot("v4/05-adr-bana")
        _open_cargo_legend()
        await _shot("v4/05-adr-upplast")
        _close_cargo_legend()
        highest_stage = 4
        upgrades.warehouse = 2
        assert(_start_stage(5) and "bransle" in state.config.types and state.total == 64)
        await get_tree().create_timer(.8).timeout
        assert(cargo_nodes.values().any(func(node): return int(node.get_meta("quality",0)) == 2))
        await _shot("v4/05-alla-godstyper")
        _open_cargo_legend()
        assert(ui.get_meta("cargo_legend").get_meta("values").bransle.text == "12 mynt / vara")
        await _shot("v4/05-premium-gods")
    elif round_number == 6:
        highest_stage = 7
        balance = 1000
        upgrades.fleet = P.max_rank("fleet")
        _refresh_harbor()
        for key in ["parking","parking","loader","belt"]:
            assert(_buy_upgrade(key))
        assert(balance == 635 and unlocked_bays == 5)
        await get_tree().create_timer(.35).timeout
        await _shot("v4/06-fem-kajer-meny")
        assert(_start_stage(8) and state.total == 88 and state.bays == [-1,-1,-1,-1,-1])
        qa_multiplier = 10
        await get_tree().create_timer(1.0).timeout
        assert(is_instance_valid(yard_batch) and yard_batch.get_meta("model_count") == 88)
        print("V4_BATCH_88 source=",yard_batch.get_meta("source_mesh_count")," groups=",yard_batch.get_meta("draw_group_count"))
        await _shot("v4/06-full-depa-88")
        var first: int = int(state.solution[0])
        var screen := camera.unproject_position(truck_nodes[first].global_position+Vector3.UP*.55)
        _pick(screen)
        assert(state.trucks[first].status == "driving","Native physics picking works with batched parked geometry")
        await _shot("v4/06-vald-lastbil")
        var guard := 0
        while state.trucks[first].status != "done":
            await get_tree().process_frame
            guard += 1
            assert(guard < 12000)
        await _shot("v4/06-leverans-fem-kajer")
    elif round_number == 7:
        assert(_buy_upgrade("fleet"))
        assert(_start_stage(1))
        qa_multiplier = 6
        var first: int = int(state.solution[0])
        _dispatch(first)
        var guard := 0
        while int(state.trucks[first].loaded) == 0:
            await get_tree().process_frame
            guard += 1
            assert(guard < 12000)
        _open_harbor()
        var snapshot: Dictionary = state.duplicate(true)
        var time_before := elapsed
        var money_before := balance
        assert(_store_progress() == OK)
        await _shot("v4/07-sparad-pa-banan")
        _new_level(0,P.stage_config(1,upgrades))
        _load_progress()
        assert(_restore_campaign(),"Actual ConfigFile roundtrip restores native session")
        assert(state == snapshot and is_equal_approx(elapsed,time_before) and balance == money_before)
        _open_harbor()
        assert(stage_active and not _buy_upgrade("belt"),"Resumed board retains between-stage purchase lock")
        await _shot("v4/07-aterupptagen-hamn")
        _close_harbor()
        await _shot("v4/07-aterupptagen-last")
        while state.trucks[first].status != "done":
            await get_tree().process_frame
            guard += 1
            assert(guard < 18000)
        assert(balance == money_before+P.delivery_reward(state.trucks[first]))
        assert(_store_progress() == OK)
        await _shot("v4/07-aterupptagen-leverans")
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_progress_path()))
    elif round_number == 8:
        # Layout stress fixtures use virtual QA currency only.
        balance = 125000
        highest_stage = 9
        for key in P.KEYS:
            upgrades[key] = P.max_rank(key)
        unlocked_bays = 5
        _refresh_harbor()
        await _shot("v4/08-maxnivaer")
        for key in P.KEYS:
            var card: Control = harbor.get_meta("upgrade_cards")[key]
            assert(card.get_meta("buy").disabled and card.get_meta("buy").text == "Maxnivå")
            assert(not _buy_upgrade(key))
        var wallet: Label = harbor.get_meta("balance")
        assert(wallet.get_theme_font("font").get_string_size(wallet.text,HORIZONTAL_ALIGNMENT_LEFT,-1,wallet.get_theme_font_size("font_size")).x <= wallet.size.x)
        assert(_start_stage(10))
        await get_tree().process_frame
        _toggle_pause()
        await _shot("v4/08-sent-skift-paus")
        _toggle_pause()
        _open_cargo_legend()
        await _shot("v4/08-maximala-varuvarden")
        assert(ui.get_meta("cargo_legend").get_meta("values").bransle.text == "18 mynt / vara")
    elif round_number == 9:
        assert(_start_stage(1))
        qa_multiplier = 75
        var starting_coins := balance
        var expected_income := P.stage_bonus(1)
        for truck in state.trucks:
            expected_income += roundi(float(truck.expected_value))
        for id in state.solution.duplicate():
            var guard := 0
            while driving:
                await get_tree().process_frame
                guard += 1
                assert(guard < 12000)
            _dispatch(int(id))
            while state.trucks[int(id)].status != "done":
                await get_tree().process_frame
                guard += 1
                assert(guard < 18000)
        assert(won and Rules.is_won(state) and highest_stage == 1)
        assert(balance == starting_coins+expected_income and earned == expected_income)
        await get_tree().create_timer(.35).timeout
        await _shot("v4/09-riktig-seger")
        modal_action.pressed.emit()
        assert(harbor.visible)
        await _shot("v4/09-intjanade-mynt")
        for key in ["parking","loader","belt","fleet"]:
            assert(_buy_upgrade(key),"Real stage earnings pay for next improvements")
        await get_tree().create_timer(.35).timeout
        await _shot("v4/09-uppgraderingar-efter-seger")
        qa_multiplier = 1
        harbor.get_meta("play").pressed.emit()
        assert(current_stage == 2 and state.total == 36 and unlocked_bays == 4)
        assert(active_upgrades.loader == 1 and active_upgrades.belt == 1 and active_upgrades.fleet == 1)
        await get_tree().create_timer(.5).timeout
        await _shot("v4/09-nasta-bana")
        print("V4_FULL_CAMPAIGN_JOURNEY_OK earned=",expected_income," balance=",balance," next_stage=",current_stage)
    elif round_number == 10:
        await _shot("v4/10-slutlig-hamn")
        assert(_start_stage(1))
        await get_tree().create_timer(.5).timeout
        await _shot("v4/10-slutlig-spelplan")
        _open_cargo_legend()
        var snapshot: Dictionary = state.duplicate(true)
        _undo()
        await get_tree().create_timer(.1).timeout
        assert(state == snapshot and paused,"Legend shields board input and freezes inventory")
        _close_cargo_legend()
        _toggle_pause()
        _open_cargo_legend()
        _close_cargo_legend()
        assert(paused and modal.visible,"Closing legend preserves a previously paused session")
        _toggle_pause()
        assert(not paused)
        _open_harbor()
        assert(harbor.get_meta("stage").text.begins_with("Bana 1"))
        assert(not _buy_upgrade("parking"))
        _close_harbor()
        _change_zoom(.4)
        await _shot("v4/10-zoom-och-symboler")
        _reset_camera()
        assert(is_equal_approx(camera.size,base_camera_size))
        await _shot("v4/10-testklar")
