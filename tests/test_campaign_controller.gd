extends SceneTree
class ReviewGame:
    extends "res://main.gd"
    func _ready() -> void:
        super._ready()
    func _load_progress() -> void:
        pass
    func _save_progress() -> void:
        pass
    func _sound(_kind: String, _cargo_type: String = "") -> void:
        pass

const P = preload("res://progression.gd")
const Rules = preload("res://puzzle.gd")
var game
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    _run.call_deferred()

func _delay(seconds: float) -> void:
    await create_timer(seconds).timeout

func _settle_truck(id: int) -> bool:
    var frames := 0
    while str(game.state.trucks[id].status) != "done" and frames < 12000:
        await process_frame
        frames += 1
    check(str(game.state.trucks[id].status) == "done","Animated campaign truck must load and leave")
    return str(game.state.trucks[id].status) == "done"

func _run() -> void:
    game = ReviewGame.new()
    root.add_child(game)
    game.qa = true
    game._refresh_audio_settings()
    await process_frame
    check(game.harbor.visible and not game.stage_active and game.highest_stage == 0,"Normal isolated boot opens campaign harbor before stage1")
    check(game.state.total == 10 and game.current_stage == 1,"Campaign boot previews10 clustered trucks")
    var original: Dictionary = game.state.duplicate(true)
    check(not game._start_stage(2) and game.state == original,"Future stages cannot be skipped")
    game.balance = 100000
    var locked_ranks: Dictionary = game.upgrades.duplicate(true)
    check(not game._buy_upgrade("fleet_adr") and not game._buy_upgrade("fleet_bransle") and game.upgrades == locked_ranks and game.balance == 100000,"Unintroduced ADR/fuel upgrades are locked by real purchase API before their stages")
    game.balance = 59
    check(not game._buy_upgrade("belt") and game.balance == 59 and game.upgrades.belt == 0,"Insufficient funds rejects real purchase")
    game.upgrades.fleet_kyl = P.max_rank("fleet_kyl")
    game.balance = 100000
    check(not game._buy_upgrade("fleet_kyl") and game.balance == 100000,"Max rank cannot consume currency")
    game.upgrades = P.defaults()
    game.balance = 1000
    game._refresh_harbor()
    for key in ["fleet_kyl","loader","belt","warehouse","parking","parking"]:
        var price: int = P.cost(key,int(game.upgrades[key]))
        var before: int = int(game.balance)
        check(game._buy_upgrade(key) and int(game.balance) == before-price,"Real purchase debits exactly P.cost")
    var expected_ranks: Dictionary = P.defaults()
    for key in ["fleet_kyl","loader","belt","warehouse"]: expected_ranks[key] = 1
    expected_ranks.parking = 2
    check(game.upgrades == expected_ranks,"Each requested campaign rank is committed independently")
    var purchased: Dictionary = game.upgrades.duplicate(true)
    var start_balance: int = int(game.balance)
    game.harbor.hide()
    check(not game._buy_upgrade("belt"),"Purchases require visible harbor")
    game.harbor.show()
    check(game._start_stage(1) and game.stage_active and not game.harbor.visible,"Harbor starts real stage1")
    check(game.active_upgrades == purchased and game.state.config.quality == 1 and game.state.config.capacities.kyl == 4 and game.state.config.capacities.frys == 3,"Fleet and warehouse ranks reach generated trucks and cargo")
    check(game.state.bays == [-1,-1,-1,-1,-1],"Parking rank2 opens all five docks")
    for cargo in game.state.feed_left+game.state.feed_right+game.state.belt:
        if cargo != null:
            check(cargo.quality == 1 and is_equal_approx(cargo.value,float(P.BASE_VALUES[cargo.type])*1.25),"Real campaign goods carry purchased quality/value")
    check(is_equal_approx(game._belt_interval(),game.TICK_TIME/1.08) and is_equal_approx(game._loading_rate(),1.12),"Purchased ranks change actual tempo helpers")
    var motion := {"loading":0.0,"normal":0.0}
    var load_tween: Tween = game._load_tween()
    load_tween.tween_method(func(value: float): motion.loading = value,0.0,1.0,10.0)
    var normal_tween: Tween = game._tween()
    normal_tween.tween_method(func(value: float): motion.normal = value,0.0,1.0,10.0)
    for _frame in range(4):
        await process_frame
    print("LOADING_TEMPO_PROBE: ",motion.loading," / ",motion.normal)
    check(float(motion.normal) > 0 and absf(float(motion.loading)/float(motion.normal)-1.12) < .001,"Real loading tween advances1.12 times faster than ordinary animation")
    load_tween.kill()
    normal_tween.kill()
    game.set_process(false)
    var old_ticks: int = int(game.state.ticks)
    game.clock = 0
    game._process(game._belt_interval()*.99)
    check(int(game.state.ticks) == old_ticks,"Belt has not ticked before upgraded interval")
    game._process(game._belt_interval()*.02)
    check(int(game.state.ticks) == old_ticks+1,"Real belt ticks at upgraded interval")
    game.set_process(true)
    var first: int = int(game.state.solution[0])
    game._dispatch(first)
    await _delay(.025)
    game._open_harbor()
    var paused_state: Dictionary = game.state.duplicate(true)
    var position: Vector3 = game.truck_nodes[first].position
    check(not game._buy_upgrade("belt") and game.upgrades == purchased,"In-stage harbor cannot buy or change ongoing rank config")
    await _delay(.08)
    check(game.state == paused_state and game.truck_nodes[first].position.is_equal_approx(position),"Harbor freezes real campaign belt and driving tween")
    game._close_harbor()
    game._toggle_pause()
    var pause_ticks: int = int(game.state.ticks)
    await _delay(.06)
    check(game.state.ticks == pause_ticks,"Campaign pause freezes belt")
    game._toggle_pause()
    game.qa_multiplier = 75
    game._toggle_speed()
    game._toggle_speed()
    if not await _settle_truck(first):
        _finish()
        return
    var first_reward: int = P.delivery_reward(game.state.trucks[first])
    check(game.balance == start_balance+first_reward and game.reward_claims.has(P.claim_key(1,first)),"Actual departure pays exact accumulated value once")
    game._undo()
    await process_frame
    check(game.balance == start_balance+first_reward and game.upgrades == purchased,"Undo preserves wallet, ranks and permanent receipt")
    game._dispatch(first)
    if not await _settle_truck(first):
        _finish()
        return
    check(game.balance == start_balance+first_reward,"Replaying claimed campaign delivery cannot farm coins")
    var expected_total := 0
    for truck in game.state.trucks:
        expected_total += roundi(float(truck.expected_value))
    var solution: Array = game.state.solution.duplicate()
    for id in solution:
        if str(game.state.trucks[int(id)].status) == "done": continue
        while game.driving:
            await process_frame
        game._dispatch(int(id))
        if not await _settle_truck(int(id)):
            _finish()
            return
    check(Rules.is_won(game.state) and game.won and game.highest_stage == 1 and not game.stage_active,"Full animated stage1 unlocks stage2 only on real completion")
    check(game.balance == start_balance+expected_total+P.stage_bonus(1),"Actual full stage pays all unique truck values and one stage bonus")
    var won_balance: int = int(game.balance)
    game._win()
    check(game.balance == won_balance,"Repeated win callback cannot duplicate stage bonus")
    # Reopen a finished board via undo: it is an active stage again, so harbor
    # purchases must remain locked until its last delivery completes again.
    game._undo()
    check(not game.won and game.stage_active,"Undo after victory returns to an active campaign stage")
    if not game.stage_active:
        _finish()
        return
    game._open_harbor()
    var ranks_before: Dictionary = game.upgrades.duplicate(true)
    var balance_before: int = int(game.balance)
    check(not game._buy_upgrade("belt") and game.balance == balance_before and game.upgrades == ranks_before,"Undo-after-win cannot bypass between-stage purchase lock")
    game._close_harbor()
    var last: int = int(solution[-1])
    if str(game.state.trucks[last].status) == "yard":
        game._dispatch(last)
        await _settle_truck(last)
    game._open_harbor()
    check(game.harbor.visible and not game.stage_active,"Finished stage returns to between-stage harbor")
    var next_cost: int = P.cost("belt",int(game.upgrades.belt))
    var next_before: int = int(game.balance)
    check(game._buy_upgrade("belt") and game.balance == next_before-next_cost,"Between-stage purchase uses earned campaign money")
    check(game._start_stage() and game.current_stage == 2 and game.state.total == 12 and game.stage_active,"Next button starts stage2 with12 trucks")
    check(game.active_upgrades.belt == game.upgrades.belt and game.highest_stage == 1,"New stage applies new ranks without pre-awarding completion")
    check(not game._start_stage(3),"Still cannot skip beyond highest plus one")
    var restart_balance: int = int(game.balance)
    game._restart_current()
    check(game.current_stage == 2 and game.stage_active and game.balance == restart_balance,"Campaign restart preserves permanent economy")
    await _v5_concurrency_and_gate()
    _finish()

func _v5_concurrency_and_gate() -> void:
    game.highest_stage = 2
    check(game._start_stage(3),"Isolated earned-stage fixture starts first gate stage")
    game.qa_multiplier = 1
    game.speed = 1
    game.set_process(false)
    var before: Dictionary = game.state.duplicate(true)
    var wallet: int = int(game.balance)
    var gate_position: Vector3 = game.obstacle_nodes[2].position
    check(game._move_obstacle(2) and game.state.obstacles[2].position_index == 1,"Real controller moves the free sliding gate")
    check(not game._move_obstacle(2),"Already animating gate cannot be double-triggered")
    var guard := 0
    while game.obstacle_motion and guard < 1200:
        await process_frame
        guard += 1
    check(not game.obstacle_motion and not game.obstacle_nodes[2].position.is_equal_approx(gate_position),"Gate's real visual animation reaches the alternate cell")
    check(game.balance == wallet,"Moving a gate never charges virtual coins")
    game._undo()
    check(game.state == before and game.obstacle_nodes[2].position.is_equal_approx(gate_position),"Free undo restores logical gate and its rendered body")
    game._toggle_pause()
    check(not game._move_obstacle(2),"Paused game cannot alter gate")
    game._toggle_pause()
    game.set_process(true)
    var starts: Dictionary = {}
    var selected: Array[int] = []
    for id in game.state.solution.duplicate():
        if selected.size() == 3: break
        if Rules.can_dispatch(game.state,int(id)):
            starts[int(id)] = game.truck_nodes[int(id)].position
            selected.append(int(id))
            game._dispatch(int(id))
    check(selected.size() == 3 and game.moving_trucks.size() == 3,"Three valid same-frame selections create three live traffic actors")
    var reserved: Dictionary = {}
    for id in selected:
        var bay: int = game.state.bays.find(id)
        check(bay >= 0 and not reserved.has(bay) and str(game.state.trucks[id].status) == "driving","Each same-frame dispatch immediately reserves a distinct dock")
        reserved[bay] = true
    var moves: int = int(game.state.moves)
    game._dispatch(selected[0])
    check(game.state.moves == moves and game.moving_trucks.size() == 3,"Repeated dispatch cannot duplicate a moving vehicle")
    await _delay(.30)
    var moved := 0
    for id in selected:
        if game.truck_nodes[id].position.distance_to(starts[id]) > .02: moved += 1
    check(moved >= 2,"At least two trucks visibly move concurrently")
    game._open_harbor()
    var frozen: Dictionary = game.state.duplicate(true)
    var frozen_positions: Dictionary = {}
    for id in selected: frozen_positions[id] = game.truck_nodes[id].position
    await _delay(.08)
    check(game.state == frozen,"Harbor pause freezes simultaneous traffic model")
    for id in selected:
        check(game.truck_nodes[id].position.is_equal_approx(frozen_positions[id]),"Harbor pause freezes every active traffic actor")
    game._close_harbor()
    game.qa_multiplier = 35
    guard = 0
    while selected.any(func(id): return str(game.state.trucks[id].status) != "done") and guard < 4000:
        await process_frame
        guard += 1
    check(selected.all(func(id): return str(game.state.trucks[id].status) == "done"),"Parallel selected trucks all load and depart without traffic deadlock")
    if not selected.all(func(id): return str(game.state.trucks[id].status) == "done"):
        print("V5_TEST_TRAFFIC_FAILURE: ",selected.map(func(id): return game.state.trucks[id].status)," actors=",game.motion_actors)
        return
    var after_payments: int = int(game.balance)
    game._undo()
    check(game.moving_trucks.is_empty() and not game.driving and game.balance == after_payments,"Undo cancels all old traffic actors while preserving permanent money")
    check(str(game.state.trucks[selected[-1]].status) == "yard","Undo returns the last same-frame selection to the yard")
    for id in [selected[0],selected[1]]:
        check(str(game.state.trucks[id].status) == "loading" and id in game.state.bays,"Earlier in-transit snapshot trucks normalize to live loading docks")
    var generation: int = int(game.generation)
    game.set_process(false)
    var restored: Dictionary = game.state.duplicate(true)
    await _delay(.05)
    check(game.generation == generation and game.state == restored,"Canceled parallel coroutines cannot mutate the restored snapshot later")

func _finish() -> void:
    game._new_level(0)
    game.set_process(false)
    game.queue_free()
    call_deferred("_quit_later")

func _quit_later() -> void:
    await process_frame
    await process_frame
    if failures.is_empty():
        print("CAMPAIGN_CONTROLLER_TESTS_OK: real harbor purchases, upgrade effects, stage locks,10 animated deliveries, receipts/undo/bonus, next stage, pause, concurrent traffic and sliding-gate undo")
        quit(0)
    else:
        print("CAMPAIGN_CONTROLLER_TESTS_FAILED: ",failures.size())
        quit(1)
