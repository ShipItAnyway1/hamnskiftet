extends SceneTree
## Reproducible, disposable-profile test of the actual V7 controller.
## Godot --headless --path truck-depot --script res://tests/test_v7_controller.gd
## No player user:// profile, native window, accelerated rescue or external assets.
class StoredGame:
    extends "res://main.gd"
    var fail_store := false
    func _progress_path() -> String:
        return "res://qa/_ci/controller.cfg"
    func _store_progress() -> Error:
        return ERR_FILE_CANT_WRITE if fail_store else super._store_progress()
    func _sound(_kind: String, _cargo_type: String = "") -> void:
        pass
    func _refresh_audio_settings() -> void:
        super._refresh_audio_settings()
        if soundscape != null:
            soundscape.set_sfx_enabled(false)
            soundscape.set_music_enabled(false)

const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const Save = preload("res://campaign_save.gd")
const PROFILE := "res://qa/_ci/controller.cfg"
var failures: Array[String] = []
var checks := 0
var runs: Dictionary = {}
var game
var began := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _guard(_delta: float) -> bool:
    if began > 0 and Time.get_ticks_msec()-began > 60000:
        push_error("V7 controller wall-time guard: coroutine failed to finish in60s")
        quit(2)
    return false

func _rescue(id: int, key: String) -> void:
    runs[key] = await game._rescue_truck(id)

func _flight(id: int, key: String) -> bool:
    var start := Time.get_ticks_msec()
    _rescue(id,key)
    while not runs.has(key) and Time.get_ticks_msec()-start < 7000:
        await process_frame
    check(runs.has(key),"Rescue coroutine finishes within7s: "+key)
    return bool(runs.get(key,false))

func _frames(count: int = 3) -> void:
    for _frame in range(count):
        await process_frame

func _dispose(current) -> void:
    current.set_process(false)
    current.generation += 1
    for tween in current.active_tweens:
        if tween.is_valid(): tween.kill()
    if current.soundscape != null:
        current.soundscape.shutdown()
    await _frames()
    current.queue_free()
    await _frames()
    await create_timer(.06).timeout

func _run() -> void:
    began = Time.get_ticks_msec()
    process_frame.connect(func(): _guard(0.0))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa/_ci"))
    for suffix in ["",".tmp"]:
        if FileAccess.file_exists(PROFILE+suffix):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE+suffix))
    game = StoredGame.new()
    root.add_child(game)
    await _frames()
    game.qa = true # Must follow normal boot so QA presets never replace stage1.
    game._refresh_audio_settings()
    game.set_process(false)
    check(game.harbor.visible and game.current_stage == 1 and not game.test_mode,"Normal boot enters stage1 harbor without test tools")
    check(game._start_stage(1),"Real controller starts campaign stage1")
    game.set_process(false)
    game.balance = 500
    check(game.state.rescue_used == 0,"A new stage supplies exactly one unused free rescue")
    check(not game.ui.get_meta("test_toolbar").visible,"Normal-mode footer remains hidden")
    game._toggle_speed()
    check(is_equal_approx(game.speed,1.0),"Normal-mode2x command is a no-op")
    game._toggle_test_mode()
    game._toggle_speed()
    check(game.test_mode and game.speed == 2.0 and game.ui.get_meta("test_toolbar").visible,"Explicit test mode exposes footer and2x")
    game._toggle_test_mode()
    check(not game.test_mode and game.speed == 1.0 and not game.ui.get_meta("test_toolbar").visible,"Leaving test mode restores normal1x and hides footer")
    for label in game.bay_labels:
        check(not label.visible and label.text.is_empty(),"Unoccupied and locked docks have no floating fraction")
    check("100" in game.modal.get_meta("paid_undo").text and "gratis" in game.modal.get_meta("rescue_button").text,"Help discloses undo100 and first heli free")
    var id := 0
    var initial: Dictionary = game.state.duplicate(true)
    var pose: Transform3D = game.truck_nodes[id].transform
    game._toggle_rescue()
    check(game.helicopter_mode,"HUD action enters target selection")
    check(await _flight(id,"free"),"First real helicopter succeeds")
    check(game.balance == 500 and game.state.rescue_used == 1,"First rescue is free and consumes entitlement exactly once")
    check(game.state.trucks[id].dir == (initial.trucks[id].dir+2)%4 and game.history.size() == 1,"Helicopter changes logical direction180 and records one undo snapshot")
    check(game.truck_nodes[id].position.is_equal_approx(pose.origin) and absf(angle_difference(game.truck_nodes[id].rotation.y,game._yard_yaw(game.state.trucks[id].dir))) < .001,"Same actual model lands at its exact cell with matching direction")
    check(not game.rescue_busy and not game.helicopter_mode and game.effects.get_child_count() == 0,"Completed rescue clears busy/selection and helicopter visuals")
    check(game.truck_nodes[id].get_meta("body").collision_layer == 1,"Landed vehicle is selectable again")
    check("50" in game.modal.get_meta("rescue_button").text,"Next rescue visibly costs50")

    game.balance = 49
    var before: Dictionary = game.state.duplicate(true)
    var history_count: int = game.history.size()
    game._toggle_rescue()
    check(not game.helicopter_mode,"Unaffordable selection cannot be entered")
    check(not await _flight(id,"insufficient") and game.balance == 49 and game.state == before and game.history.size() == history_count,"Insufficient rescue does not charge, rotate or append history")
    game.balance = 500
    game.qa = false
    game.fail_store = true
    var file_before := FileAccess.get_file_as_string(PROFILE)
    check(not await _flight(id,"save_failure") and game.state == before and game.balance == 500 and game.history.size() == history_count,"Failed persistent rescue rolls back direction, use counter, wallet and history")
    check(FileAccess.get_file_as_string(PROFILE) == file_before,"Failed rescue leaves the prior save untouched")
    game.fail_store = false
    check(await _flight(id,"paid"),"Paid real helicopter succeeds with actual durable save")
    check(game.balance == 450 and game.state.rescue_used == 2 and game.state.trucks[id].dir == initial.trucks[id].dir,"Second rescue charges exactly50 and returns initial orientation")
    var cfg := ConfigFile.new()
    check(cfg.load(PROFILE) == OK and cfg.get_value("campaign","state").rescue_used == 2 and cfg.get_value("progress","coins") == 450,"Real saved profile contains paid rescue and wallet")
    before = game.state.duplicate(true)
    game.fail_store = true
    game._paid_undo()
    check(game.state == before and game.balance == 450 and game.history.size() == 2,"Failed persistent undo does not debit100 or consume history")
    game.fail_store = false
    game._paid_undo()
    check(game.balance == 350 and game.history.size() == 1,"Normal undo charges100 exactly once")
    check(game.state.trucks[id].dir == (initial.trucks[id].dir+2)%4 and game.state.rescue_used == 2,"Undo reverses direction while rescue entitlement stays monotonic")
    game.balance = 99
    before = game.state.duplicate(true)
    game._paid_undo()
    check(game.balance == 99 and game.state == before and game.history.size() == 1,"Unaffordable undo preserves wallet/state/history")
    game.balance = 350
    game._save_progress()
    var valid: Dictionary = Save.validate(game.state,game.active_upgrades,game.highest_stage)
    check(not valid.is_empty() and valid.rescue_used == 2,"Rotated active snapshot validates with used rescues")
    for mutation in ["dir","target_load","rescue_used"]:
        var corrupt: Dictionary = game.state.duplicate(true)
        if mutation == "dir": corrupt.trucks[id].dir = (int(initial.trucks[id].dir)+1)%4
        elif mutation == "target_load": corrupt.trucks[id].target_load = 1
        else: corrupt.rescue_used = -1
        check(Save.validate(corrupt,game.active_upgrades,game.highest_stage).is_empty(),"Snapshot validator rejects corrupt "+mutation)
    await _dispose(game)
    game = StoredGame.new()
    root.add_child(game)
    await _frames()
    game.qa = true
    game._refresh_audio_settings()
    game.set_process(false)
    check(game.stage_active and game.current_stage == 1 and game.state.rescue_used == 2 and game.balance == 350,"Fresh normal boot restores the same used entitlement and wallet")
    game._close_harbor()
    check("50" in game.modal.get_meta("rescue_button").text,"Reload cannot regain a free rescue")
    check(game.history.is_empty(),"Restart does not fabricate undo history")

    # Dispatch through real controller. The label must wait for physical arrival.
    var first: int = int(game.state.solution[0])
    if not R.can_dispatch(game.state,first):
        game._new_level(0,P.stage_config(1,game.upgrades))
        game.stage_active = true
        first = int(game.state.solution[0])
    game._dispatch(first)
    var bay: int = game.state.bays.find(first)
    check(str(game.state.trucks[first].status) == "driving" and bay >= 0,"Real dispatch reserves a dock before driving")
    check(not game.bay_labels[bay].visible,"Driving reservation does not display a premature0/3 loading label")
    var driving_before: Dictionary = game.state.duplicate(true)
    check(not await _flight(first,"driving_target") and game.state == driving_before,"Helicopter rejects a truck already driving")
    game.generation += 1
    for tween in game.active_tweens:
        if tween.is_valid(): tween.kill()
    game.moving_trucks.clear()
    game.motion_actors.clear()
    R.arrive(game.state,first)
    game._refresh_ui()
    check(game.bay_labels[bay].visible,"Loading status exposes its actual loading counter")
    before = game.state.duplicate(true)
    check(not await _flight(first,"loading_target") and game.state == before,"Helicopter rejects a truck already loading")
    await _frames()

    # Valid stage3 wrong choices, independently proved by pure rules test.
    game._new_level(2,P.stage_config(3,P.defaults()))
    game.stage_active = true
    game.set_process(false)
    for wrong in [0,1,2]:
        check(R.dispatch(game.state,wrong).ok,"Real legal wrong-choice sequence dispatches truck%d" % wrong)
        R.arrive(game.state,wrong)
    for _tick in range(40): R.tick(game.state)
    check(R.loss_reason(game.state) == "bays_blocked","Three legal kyl choices cause a genuine stable resource deadlock")
    game._check_failure()
    check(game.failed and game.paused and game.modal.visible and game.modal_title.text == "Ordern har låst sig","Controller presents actual terminal deadlock with restart action")
    check("100" in game.modal_text.text and "gratis" in game.modal_action.text,"Failure discloses free restart and100-gold undo")
    game._restart_current()
    game.set_process(false)
    check(not game.failed and not game.paused and not game.modal.visible and game.state.rescue_used == 0,"Free stage restart clears failure and supplies its own first rescue")

    # Opposing real truck footprints create blocked exits despite three free
    # docks. Reset through the controller so both visuals/colliders match the
    # reduced rule fixture; QA avoids saving this intentionally uncertified map.
    var trapped: Dictionary = R.create_level(0,P.stage_config(1,P.defaults()))
    trapped.trucks = trapped.trucks.slice(0,2)
    for truck_id in range(2):
        trapped.trucks[truck_id].id = truck_id
        trapped.trucks[truck_id].x = 3 if truck_id == 0 else 7
        trapped.trucks[truck_id].y = 10
        trapped.trucks[truck_id].dir = 1 if truck_id == 0 else 3
    trapped.total = 2
    trapped.solution = [0,1]
    trapped.required_route = [0,1]
    game._new_level(0,P.stage_config(1,P.defaults()),trapped)
    game.stage_active = true
    game.set_process(false)
    await _frames()
    check(game.truck_nodes.size() == 2 and -1 in game.state.bays and R.loss_reason(game.state) == "blocked_exits","Opposing two-truck fixture has actual models and a proven exit loss with free docks")
    game._check_failure()
    check(game.failed and game.paused and game.modal.visible,"Blocked exits display a real failure dialog")
    game._toggle_rescue()
    check(game.helicopter_mode and not game.failed and not game.paused and not game.modal.visible,"Helicopter selection dismisses blocked-exit loss")
    for _frame in range(5):
        await process_frame
        game._check_failure()
        check(game.helicopter_mode and not game.failed and not game.modal.visible,"Failure detection leaves an armed rescue selectable across frames")
    game._toggle_rescue()
    game._check_failure()
    check(not game.helicopter_mode and game.failed and game.modal.visible,"Cancelling selection re-detects the unresolved exit loss")
    game._toggle_rescue()
    var trapped_origin: Vector3 = game.truck_nodes[0].position
    check(await _flight(0,"blocked_exit_recovery"),"Actual selected helicopter rescues the blocked-exit fixture")
    game._check_failure()
    check(not game.failed and not game.paused and not game.modal.visible and not game.helicopter_mode,"Successful recovery remains in ordinary play without reopening the loss")
    check(R.can_dispatch(game.state,0) and R.loss_reason(game.state).is_empty(),"The180degree rescue genuinely opens an ordinary legal dispatch")
    check(game.truck_nodes[0].position.is_equal_approx(trapped_origin) and game.state.trucks[0].dir == 3,"Recovered model and rule direction agree at the same physical position")
    await _dispose(game)
    for child in root.get_children():
        check(child.name != "HelicopterRescueController","No helicopter controllers survive teardown")
    for suffix in ["",".tmp"]:
        if FileAccess.file_exists(PROFILE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE+suffix))
    print("V7_CONTROLLER_TESTS_OK: %d checks; real normal boot, heli0/50, paid undo100, failed-save rollback, monotonic/reloaded rescue, snapshot validation, test-mode gating, dock labels, genuine loss/restart and blocked-exit rescue recovery" % checks if failures.is_empty() else "V7_CONTROLLER_TESTS_FAILED: %d" % failures.size())
    quit(0 if failures.is_empty() else 1)
