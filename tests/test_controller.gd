extends SceneTree

# Real controller, models, colliders and tweens. Persistence and audio are
# isolated so this regression never touches the player's progress.
class ReviewGame:
    extends "res://main.gd"
    func _load_progress() -> void:
        pass
    func _save_progress() -> void:
        pass
    func _sound(_kind: String, _cargo_type: String = "") -> void:
        pass

const Rules = preload("res://puzzle.gd")
const L = preload("res://layout.gd")
var game
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _frames(count: int = 3) -> void:
    for _frame in range(count):
        await physics_frame

func _delay(seconds: float) -> void:
    await create_timer(seconds).timeout

func _free_id() -> int:
    for id in game.state.solution:
        if Rules.can_dispatch(game.state,int(id)):
            return int(id)
    return -1

func _yard_colliders() -> void:
    var count := 0
    for truck in game.state.trucks:
        var id: int = int(truck.id)
        if str(truck.status) == "done":
            check(not game.truck_nodes.has(id),"Done trucks have no clickable visual")
            continue
        check(game.truck_nodes.has(id),"Every live truck has a visual")
        var node: Node3D = game.truck_nodes[id]
        var body: StaticBody3D = node.get_meta("body")
        check(body.collision_layer == (1 if str(truck.status) == "yard" else 0),"Collider agrees with truck lifecycle")
        if str(truck.status) == "yard":
            count += 1
            check(node.position.is_equal_approx(game._yard_position(truck)),"Yard visual is restored to its exact cell")
    check(count > 0,"Regression retains a populated yard")

func _fresh(level: int = 0) -> void:
    game._new_level(level)
    game.set_process(false)
    await _frames()
    check(not game.driving and game.history.is_empty() and game.active_tweens.is_empty(),"New level clears traffic, undo history and tweens")
    check(game.state.trucks.size() == int(L.COUNTS[level]),"Level has requested fleet size")
    _yard_colliders()

func _run() -> void:
    game = ReviewGame.new()
    root.add_child(game)
    game.qa = true
    game._new_level(0)
    game.set_process(false)
    game.qa_multiplier = 8.0
    await _frames()
    check(game.state.trucks.size() == int(L.COUNTS[0]),"Real scene starts with the first authored fleet size")
    var blocked := -1
    for truck in game.state.trucks:
        if Rules.blocker_id(game.state,int(truck.id)) >= 0:
            blocked = int(truck.id)
            break
    var before: Dictionary = game.state.duplicate(true)
    game._dispatch(blocked)
    check(game.state == before and game.history.is_empty() and not game.driving,"Blocked click preserves yard and undo history")
    await _delay(.06)
    var first: int = _free_id()
    game._dispatch(first)
    check(game.driving and str(game.state.trucks[first].status) == "driving","Real dispatch starts asynchronous driving")
    var during: Dictionary = game.state.duplicate(true)
    game._dispatch(first)
    game._dispatch(_free_id())
    check(game.state == during and game.history.size() == 1,"Duplicate/second click cannot dispatch during active driving")
    await _delay(.035)
    game._undo()
    await _frames()
    check(game.state == before and not game.driving and game.history.is_empty(),"Undo during movement restores full model")
    _yard_colliders()
    await _delay(.55)
    check(game.state == before,"Killed arrival cannot mutate restored state later")

    # A camera-projected point is fed through the actual physics ray picker.
    for zoom_delta in [0.0,0.6]:
        game._change_zoom(zoom_delta)
        await _frames()
        first = _free_id()
        var node: Node3D = game.truck_nodes[first]
        var screen: Vector2 = game.camera.unproject_position(node.global_position+Vector3.UP*.6)
        game._pick(screen)
        check(game.driving and str(game.state.trucks[first].status) == "driving","Actual ray picking dispatches the intended truck at zoom %.1f" % game.zoom)
        game._undo()
        await _frames()
        _yard_colliders()

    # Cancelling a tween via reset and then changing fleet size must discard all
    # callbacks from its old generation, including disabled old colliders.
    first = _free_id()
    game._dispatch(first)
    await _delay(.025)
    await _fresh(0)
    var reset: Dictionary = game.state.duplicate(true)
    await _delay(.55)
    check(game.state == reset,"Reset during active tween has no late arrival mutation")
    game._dispatch(_free_id())
    await _delay(.025)
    await _fresh(1)
    var switched: Dictionary = game.state.duplicate(true)
    await _delay(.55)
    check(game.state == switched and game.truck_nodes.size() == int(L.COUNTS[1]),"Fleet size switch discards all old traffic and nodes")

    # Restore a snapshot that already contains a loading truck, not only an
    # initial yard. That truck must remain able to receive a real belt load.
    await _fresh(0)
    first = _free_id()
    game._dispatch(first)
    var guard := 0
    while game.driving and guard < 1800:
        await process_frame
        guard += 1
    check(not game.driving and str(game.state.trucks[first].status) == "loading","Arrival settles into an active loading bay")
    var loading: Dictionary = game.state.duplicate(true)
    var second: int = _free_id()
    game._dispatch(second)
    await _delay(.025)
    game._undo()
    await _frames()
    check(game.state == loading and str(game.state.trucks[first].status) == "loading","Undo preserves pre-existing loading truck and cargo")
    _yard_colliders()
    var loaded_before: int = int(game.state.trucks[first].loaded)
    for _step in range(40):
        game._step_belt()
        if int(game.state.trucks[first].loaded) > loaded_before:
            break
    check(int(game.state.trucks[first].loaded) > loaded_before,"Restored loading truck is live and receives circulating cargo")
    check(int(game.truck_nodes[first].get_meta("displayed_load")) == loaded_before,"Cargo counter waits while the crane still carries its load")
    check(int(game.loading_in_flight.get(first,0)) > 0,"Live cargo movement reserves its truck until landing")
    await _delay(.16)
    check(int(game.truck_nodes[first].get_meta("displayed_load")) == int(game.state.trucks[first].loaded),"Counter updates when the physical load lands")
    await _test_dock_purchases_and_rewards(first)

    await _fresh(0)
    first = _free_id()
    game._dispatch(first)
    game.set_process(true)
    await _delay(.035)
    game._toggle_pause()
    var pause_state: Dictionary = game.state.duplicate(true)
    var pause_clock: float = float(game.clock)
    var pause_position: Vector3 = game.truck_nodes[first].position
    await _delay(.18)
    check(game.paused and game.state == pause_state and is_equal_approx(game.clock,pause_clock),"Pause freezes real belt ticks and state")
    check(game.truck_nodes[first].position.is_equal_approx(pause_position),"Pause freezes active truck tween")
    game._toggle_pause()
    await _delay(.12)
    check(not game.paused and (not game.truck_nodes[first].position.is_equal_approx(pause_position)),"Resume restarts active tween")
    await _fresh(0)
    first = _free_id()
    game._dispatch(first)
    game.set_process(true)
    await _delay(.025)
    game._open_shop()
    var shop_state: Dictionary = game.state.duplicate(true)
    var shop_clock: float = float(game.clock)
    var shop_position: Vector3 = game.truck_nodes[first].position
    await _delay(.16)
    check(game.shop.visible and game.paused and game.state == shop_state and is_equal_approx(game.clock,shop_clock),"Shop freezes belt and all model state")
    check(game.truck_nodes[first].position.is_equal_approx(shop_position),"Shop freezes active truck tween")
    game._close_shop()
    await _delay(.07)
    check(not game.shop.visible and not game.paused and not game.truck_nodes[first].position.is_equal_approx(shop_position),"Closing shop resumes a previously running game")
    game._toggle_pause()
    game._open_shop()
    game._close_shop()
    check(game.paused and game.modal.visible,"Shop preserves an already paused game on closing")
    game._toggle_pause()
    game.set_process(false)
    await _fresh(0)
    # Cancellation resumes on process_frame; physics frames may be batched in
    # headless runs. Let suspended callers observe the new generation first.
    for _settle in range(4):
        await process_frame
    game.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("TRUCK_CONTROLLER_TESTS_OK: 64/88 fleet switching, blocked/duplicate clicks, mid-drive undo/reset, restored loading, pause/shop freeze and resume, two-zoom ray picking, real shop button purchases, permanent unlock overlays and delivery reward replay protection")
        quit(0)
    else:
        print("TRUCK_CONTROLLER_TESTS_FAILED: ",failures.size())
        quit(1)

func _test_dock_purchases_and_rewards(loading_id: int) -> void:
    if not game.has_method("_buy_dock"):
        check(false,"Current controller exposes the documented virtual dock purchase API")
        return
    check(game.unlocked_bays == 3,"New isolated player starts with three bays")
    game.balance = 79
    var before: Dictionary = game.state.duplicate(true)
    check(not game._buy_dock(3) and game.balance == 79 and game.state == before,"Insufficient virtual balance cannot buy a dock")
    game.balance = 220
    check(not game._buy_dock(4) and game.unlocked_bays == 3 and game.balance == 220,"Fifth dock cannot be bought before the fourth")
    game.balance = 120
    game._open_shop()
    check(not game.shop_buttons[0].disabled and game.shop_buttons[1].disabled,"Shop enables only the affordable next dock")
    game.shop_buttons[0].pressed.emit()
    check(game.unlocked_bays == 4 and game.balance == 40,"Actual first shop button buys dock4 for exactly80 coins")
    check(str(game.state.trucks[loading_id].status) == "loading" and loading_id in game.state.bays,"Buying a dock does not disturb an active loading truck")
    check(not game._buy_dock(3) and game.balance == 40,"Repeated purchase never charges twice")
    check(not game._buy_dock(4) and game.balance == 40,"Unaffordable fifth dock preserves balance")
    # This snapshot predates the purchase. Permanent entitlements are overlaid
    # after restoring gameplay, rather than being undone or refunded.
    game._undo()
    await _frames()
    check(game.unlocked_bays == 4 and game.balance == 40 and game.state.bays == [-1,-1,-1,-1,-2],"Undo of an older snapshot retains purchased dock and wallet")
    game.balance = 140
    game._open_shop()
    check(game.shop_buttons[0].disabled and not game.shop_buttons[1].disabled,"After buying dock4 the shop enables the correct second purchase")
    game.shop_buttons[1].pressed.emit()
    check(game.unlocked_bays == 5 and game.balance == 0,"Actual second shop button buys dock5 for exactly140 coins")
    check(not game._buy_dock() and game.balance == 0,"No sixth dock or repeat charge exists")
    await _fresh(1)
    check(game.unlocked_bays == 5 and game.state.bays == [-1,-1,-1,-1,-1],"Both purchased docks remain available across fleet changes")

    # Exercise the actual animated departure twice around a real undo. The
    # permanent claim ledger must prevent farming the same truck's reward.
    await _fresh(0)
    game.qa_multiplier = 18.0
    game.set_process(true)
    var id: int = int(game.state.solution[0])
    var initial_balance: int = int(game.balance)
    game._dispatch(id)
    var guard := 0
    while str(game.state.trucks[id].status) != "done" and guard < 2400:
        await process_frame
        guard += 1
    game.set_process(false)
    check(str(game.state.trucks[id].status) == "done","Real departure finishes for currency regression")
    check(int(game.balance) == initial_balance+10,"Unique delivered truck grants exactly ten real game coins immediately")
    game._undo()
    await _frames()
    check(int(game.balance) == initial_balance+10 and game.unlocked_bays == 5,"Undo does not refund or duplicate permanent rewards and purchases")
    game.set_process(true)
    game._dispatch(id)
    guard = 0
    while str(game.state.trucks[id].status) != "done" and guard < 2400:
        await process_frame
        guard += 1
    game.set_process(false)
    check(str(game.state.trucks[id].status) == "done" and int(game.balance) == initial_balance+10,"Replaying an already claimed truck cannot farm currency")
    game.qa_multiplier = 8.0
