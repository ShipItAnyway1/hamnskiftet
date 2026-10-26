extends SceneTree
const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const L = preload("res://layout.gd")
var failures: Array[String] = []
var completed := 0
var shipped := 0
var ticks := 0
var partial_jobs := 0

func check(value: bool, message: String) -> void:
    if not value:
        if failures.size() < 30: push_error(message)
        failures.append(message)

func _initialize() -> void:
    _prices_and_legacy()
    var base_trips: Dictionary = {}
    for stage in range(1,11):
        var signature: Array = []
        for mode in range(5):
            var ranks: Dictionary = P.defaults()
            for index in range(P.KEYS.size()):
                var key: String = P.KEYS[index]
                if mode == 1: ranks[key] = P.max_rank(key)
                elif mode == 2 and key in P.FLEET_KEYS: ranks[key] = (stage+index)%4
                elif mode in [3,4] and key in P.FLEET_KEYS: ranks[key] = mode-2
            var config: Dictionary = P.stage_config(stage,ranks)
            var state: Dictionary = R.create_level(stage-1,config)
            check(state.certificate_valid and state == R.create_level(stage-1,config),"Deterministic rescue-free generator certificate")
            check(state.total == [10,12,14,16,18,22,26,30][mini(stage-1,7)],"Short fixed fleet count")
            check(state.cargo_total == [8,10,12,14,16,18,20,24][mini(stage-1,7)] and state.cargo_total < state.total,"Fixed cargo pool has surplus physical trucks")
            check(config.boss == (stage%5 == 0) and state.belt_limit == (6 if config.boss else 8),"Boss flag and finite circulating cargo limit")
            check(("adr" in config.types) == (stage>=3) and ("bransle" in config.types) == (stage>=5),"Resource unlock stages preserved")
            if stage == 1: check(config.manifest == {"schakt":4,"kyl":4},"Tutorial manifest is exactly4+4")
            var current: Array = _signature(state)
            if mode == 0: signature = current
            else: check(signature == current,"Fleet/warehouse upgrades never add goods or reorder their identity/type sequence")
            _geometry(state,config)
            if stage in [3,5]: check(_has_chain(state,2),"Required geometry has at least a two-edge dependency chain on ordinary3 and boss5")
            if stage == 5:
                var fuel := 0
                for truck in state.trucks:
                    if truck.type == "bransle":
                        fuel += 1
                        check(truck.id in state.required_route and R.blocker_id(state,truck.id) == -2 and not R.can_dispatch(state,truck.id),"Boss boom independently blocks every necessary fuel option")
                        var without_boom: Dictionary = state.duplicate(true)
                        without_boom.obstacles[0].opened = true
                        check(R.can_dispatch(without_boom,truck.id),"Removing only the counter restriction immediately frees necessary fuel: boom is nonredundant")
                check(fuel > 0 and config.manifest.bransle > 0,"Boss fuel lock cannot be skipped as an optional decoy")
            var result: Dictionary = _play(state)
            check(result.won,"Entire stage%d mode%d completes without helicopter/rotation" % [stage,mode])
            if mode == 0: base_trips[stage] = result.trips
            if mode == 1:
                check(result.trips <= int(base_trips[stage]),"Larger capacities never require more trips for the same fixed order")
                if stage == 1: check(result.trips == 2 and base_trips[stage] == 4,"Capacity3→6 cuts first manifest from4 real trips to2")
            var warm: Dictionary = R.create_level(stage-1,config)
            for _tick in range(8): R.tick(warm)
            check(R.simulate(warm).ok,"The exact normal controller8-tick warmup retains the certificate")
    _loss_and_reservations()
    _backtracking()
    _exit_loss_cases()
    _last_capacity_thresholds()
    check(partial_jobs > 0,"Tests really exercised positive partial departures")
    if failures.is_empty():
        print("V7_RULES_TESTS_OK:50 complete fixed-manifest stages+50 normal warmups,%d trips/%d shipped units/%d ticks; capacity3/4/5/6,mixed ranks,required chains,boss counters,partial reservations,empty traps,finite recirculation,backtracking and legacy" % [completed,shipped,ticks])
    else: print("V7_RULES_TESTS_FAILED ",failures.size())
    quit(0 if failures.is_empty() else 1)

func _prices_and_legacy() -> void:
    for key in P.FLEET_KEYS:
        check(P.COSTS[key] == ([230,500,1000] if key in ["fleet_adr","fleet_bransle"] else [200,450,900]),"Requested per-resource prices")
    check(P.COSTS.loader == [180,360,700,1100,1600,2200] and P.COSTS.belt == [220,440,800,1250,1800,2500],"Requested crane/belt prices")
    check(P.COSTS.warehouse == [260,520,900,1500,2300] and P.COSTS.parking == [650,1400],"Requested warehouse/dock prices")
    for key in P.KEYS:
        var ranks: Dictionary = P.defaults()
        for rank in range(P.max_rank(key)):
            var price: int = P.cost(key,rank)
            check(not P.purchase(ranks,price-1,key).ok,"Unaffordable proposal cannot spend coins")
            var proposal: Dictionary = P.purchase(ranks,price,key)
            check(proposal.ok and proposal.balance == 0 and proposal.levels[key] == rank+1,"Exact cost advances one rank")
            ranks = proposal.levels
        check(not P.purchase(ranks,100000,key).ok,"Max rank cannot be bought twice")
    var old: Dictionary = P.sanitize({"fleet":7,"parking":2,"loader":4})
    for key in P.FLEET_KEYS: check(old[key] == 3,"Old fleet ownership survives migration")
    check(old.parking == 2 and old.loader == 4,"Existing general purchases are preserved")
    for index in range(2):
        var legacy: Dictionary = R.create_level(index)
        check(legacy == R.create_level(index,{}) and not legacy.has("campaign") and legacy.total == L.COUNTS[index],"Empty config keeps exact legacy contract")
        for truck in legacy.trucks: check(not truck.has("target_load") and truck.capacity in [2,3,4],"Legacy full-truck schema remains intact")

func _signature(state: Dictionary) -> Array:
    var cargo: Array = state.feed_left+state.feed_right
    cargo.sort_custom(func(a,b): return int(a.id)<int(b.id))
    var signature: Array = []
    for item in cargo: signature.append([item.id,item.type])
    return signature

func _geometry(state: Dictionary, config: Dictionary) -> void:
    var occupied: Dictionary = {}
    for truck in state.trucks:
        check(truck.capacity == config.capacities[truck.type] and truck.len == (3 if truck.capacity>=5 else 2),"Actual per-type capacity and physical length")
        for cell in R._cells(truck):
            check(config.spawn_bounds.has_point(cell) and not occupied.has(cell),"Truck footprint fits without overlap")
            occupied[cell] = truck.id
    for id in state.required_route:
        for cell in R._ray(state.trucks[id],state.width,state.height):
            if occupied.has(cell): check(occupied[cell] in state.required_route,"No zero-target decoy must be removed to reach a required truck")

func _has_chain(state: Dictionary, edges: int) -> bool:
    for id in state.required_route:
        if _chain(state,int(id),edges,[]): return true
    return false

func _chain(state: Dictionary, id: int, edges: int, seen: Array) -> bool:
    if edges <= 0: return true
    if id in seen: return false
    var ray: Array = R._ray(state.trucks[id],state.width,state.height)
    for other in state.required_route:
        if int(other) == id: continue
        for cell in R._cells(state.trucks[int(other)]):
            if cell in ray and _chain(state,int(other),edges-1,seen+[id]): return true
    return false

func _play(initial: Dictionary) -> Dictionary:
    var state: Dictionary = initial.duplicate(true)
    var consumed: Dictionary = {}
    for step in state.solution_steps:
        if R.is_won(state): break
        if step.action == "dispatch":
            var target: int = R.preview_target(state,int(step.id))
            check(target > 0 and R.dispatch(state,int(step.id)).ok,"Certificate dispatch is legal and never deliberately empty")
            check(state.trucks[int(step.id)].target_load == target,"Dispatch reserves actual remaining stock")
            R.arrive(state,int(step.id))
        elif step.action == "wait":
            var guard := 0
            while not R.step_ready(state,step) and guard < 800:
                var event: Dictionary = R.tick(state)
                ticks += 1
                guard += 1
                for load_event in event.loads:
                    check(not consumed.has(load_event.cargo_id),"A physical cargo identity is never loaded twice")
                    consumed[load_event.cargo_id] = true
                    check(load_event.value == state.config.cargo_values[load_event.type] and load_event.quality == state.config.quality,"Actual cargo value/quality survives loading")
                for id in event.departures:
                    var truck: Dictionary = state.trucks[int(id)]
                    check(truck.loaded == truck.target_load and truck.target_load > 0 and truck.loaded <= truck.capacity,"Positive jobs finish at target, including partial capacity")
                    if truck.loaded < truck.capacity: partial_jobs += 1
                    var before: int = int(state.cargo_delivered)
                    R.release_bay(state,int(id))
                    check(state.cargo_delivered == before+int(truck.loaded),"Actual departure alone credits shipped units")
                    completed += 1
                    shipped += int(truck.loaded)
                _audit(state,consumed)
                check(R.loss_reason(state) == "","Certified progress is never falsely reported as a proven loss")
            check(R.step_ready(state,step),"Certificate wait completes")
    check(R.is_won(state) and state.cargo_delivered == state.cargo_total and state.delivered < state.total,"Win ships all goods while surplus vehicles remain")
    check(state.rescue_used == 0,"No certificate needs rescue currency or rotation")
    return {"won":R.is_won(state),"trips":int(state.delivered)}

func _audit(state: Dictionary, consumed: Dictionary) -> void:
    var remaining: Dictionary = {}
    var count := 0
    var value := 0.0
    for cargo in state.feed_left+state.feed_right+state.belt:
        if cargo == null: continue
        check(not remaining.has(cargo.id) and not consumed.has(cargo.id),"Cargo identities conserved between both queues/ring/trucks")
        remaining[cargo.id] = true
        count += 1
        value += float(cargo.value)
    var loaded := 0
    var receipt_value := 0.0
    for truck in state.trucks:
        loaded += int(truck.loaded)
        receipt_value += float(truck.delivery_value)
    check(count+loaded == state.cargo_total and loaded == consumed.size(),"Fixed units never disappear or multiply")
    check(is_equal_approx(value+receipt_value,float(state.cargo_value_total)),"Cargo monetary value is conserved before receipts")
    check(R.belt_count(state) <= state.belt_limit,"At most6/8 actual goods circulate on18 physical slots")
    for obstacle in state.obstacles:
        check(obstacle.opened == (state.delivered >= obstacle.opens_after),"Boom opens only after actual positive departures")

func _loss_and_reservations() -> void:
    for stage in [3,5]:
        var state: Dictionary = R.create_level(stage-1,P.stage_config(stage,{}))
        for _tick in range(8): R.tick(state)
        var path: Array = [0,1,2]
        var before: Dictionary = state.duplicate(true)
        for index in range(path.size()):
            var id: int = int(path[index])
            check(R.dispatch(state,id).ok,"Explicit bad choice is physically legal")
            check(state.trucks[id].target_load == (mini(int(state.trucks[id].capacity),int(state.manifest[state.trucks[id].type])) if index == 0 else 0),"Unfilled reservations prevent duplicate freight allocation")
            check(R.loss_reason(state) == "","Driving job is not falsely declared lost before it can arrive")
            R.arrive(state,id)
        for _tick in range(80): R.tick(state)
        var frozen: Dictionary = state.duplicate(true)
        check(R.loss_reason(state) == "bays_blocked" and R.is_stuck(state),"Three wrong/empty jobs produce a genuine nonpaywalled loss")
        check(state == frozen,"Loss detection never mutates a snapshot")
        state = before.duplicate(true)
        check(R.loss_reason(state) == "" and R.simulate(state).ok,"A free deep undo/restart restores a real winning continuation")
    var state: Dictionary = R.create_level(0,P.stage_config(1,{}))
    var id: int = int(state.solution[0])
    var cells: Array = R._cells(state.trucks[id])
    var original: Dictionary = state.trucks[id].duplicate(true)
    check(R.rotate_truck(state,id).ok and R._cells(state.trucks[id]) == cells and state.trucks[id].dir == (int(original.dir)+2)%4,"180degree rescue retains exact footprint")
    check(R.rotate_truck(state,id).ok and state.trucks[id].dir == original.dir,"Second rescue rotation returns original heading")
    check(not R.rotate_truck(state,-1).ok,"Invalid rescue is rejected")
    R.dispatch(state,id)
    var snapshot: Dictionary = state.duplicate(true)
    check(not R.rotate_truck(state,id).ok and state == snapshot,"Moving/loading vehicles cannot be rotated behind controller")

func _backtracking() -> void:
    # A/B/C first is a true6-item deadlock. Backtracking must replace that
    # third choice with D, ship its6 goods, and then complete A/B/C.
    var kinds := ["schakt","timmer","kyl","frys"]
    var manifest := {"schakt":2,"timmer":2,"kyl":2,"frys":6}
    var state := {"width":18,"height":20,"trucks":[],"bays":[-1,-1,-1,-2,-2],"total":4,"delivered":0,
        "cargo_total":12,"cargo_delivered":0,"moves":0,"ticks":0,"campaign":true,"stage":99,"manifest":manifest,
        "manifest_delivered":{},"departures_by_type":{},"rescue_used":0,"belt_limit":6,"belt":[],"feed_left":[],"feed_right":[],
        "obstacles":[],"solution":[0,1,2,3],"required_route":[0,1,2,3],"config":{"cargo_values":P.BASE_VALUES}}
    state.belt.resize(18)
    for index in range(kinds.size()):
        var kind: String = kinds[index]
        state.trucks.append({"id":index,"x":index*4,"y":10,"dir":0,"len":3,"type":kind,"capacity":6,"target_load":-1,"loaded":0,"status":"yard","delivery_value":0.0,"expected_value":float(manifest[kind])*float(P.BASE_VALUES[kind]),"quality":0})
    var order := ["frys","frys","frys","frys","frys","frys","schakt","schakt","timmer","timmer","kyl","kyl"]
    for index in range(order.size()):
        var kind: String = order[index]
        var cargo := {"id":index,"type":kind,"quality":0,"value":float(P.BASE_VALUES[kind])}
        if index%2: state.feed_right.append(cargo)
        else: state.feed_left.append(cargo)
    var solution: Array = R.solve(state,2000)
    check(not solution.is_empty() and R.simulate(state,solution).ok,"Bounded genuine backtracking escapes bad preferred choices and certifies an alternative")

func _exit_loss_cases() -> void:
    var state: Dictionary = R.create_level(0,P.stage_config(1,{}))
    state.trucks = state.trucks.slice(0,2)
    for id in range(2):
        state.trucks[id].id = id
        state.trucks[id].x = 3 if id == 0 else 7
        state.trucks[id].y = 10
        state.trucks[id].dir = 1 if id == 0 else 3
    state.total = 2
    state.solution = [0,1]
    state.required_route = [0,1]
    check(not R.can_dispatch(state,0) and not R.can_dispatch(state,1) and R.loss_reason(state) == "blocked_exits","A genuine opposing-truck cycle with free docks is a proven ordinary-play loss")
    var snapshot: Dictionary = state.duplicate(true)
    check(R.loss_reason(state) == "blocked_exits" and state == snapshot,"Exit-loss proof runs only on an automatic copy")
    var pending: Dictionary = state.duplicate(true)
    var loader: Dictionary = pending.trucks[0].duplicate(true)
    loader.id = 2
    loader.status = "loading"
    loader.target_load = 1
    loader.x = 12
    loader.y = 12
    pending.trucks.append(loader)
    pending.bays[0] = 2
    check(R.loss_reason(pending) == "","A finite positive automatic delivery can still release/open something; do not declare exit loss")
    var movable: Dictionary = state.duplicate(true)
    movable.obstacles = [{"id":7,"kind":"gate","x":16,"y":16,"w":1,"h":1,"movable":true,"position_index":0,"positions":[Vector2i(16,16),Vector2i(17,16)]}]
    check(R.loss_reason(movable) == "","A legal clickable obstacle move remains a possible escape")
    check(R.rotate_truck(state,0).ok and R.can_dispatch(state,0) and R.loss_reason(state) == "","External180degree rescue genuinely restores a normal continuation")

func _last_capacity_thresholds() -> void:
    var appeared: Dictionary = {}
    for stage in range(8,14):
        var max_ranks: Dictionary = P.defaults()
        for key in P.FLEET_KEYS: max_ranks[key] = 3
        var config: Dictionary = P.stage_config(stage,max_ranks)
        var quantities: Array = config.manifest.values()
        quantities.sort()
        check(quantities == [3,3,3,4,5,6],"Later fixed24pool exposes each3→4→5→6 upgrade threshold")
        for kind in config.manifest:
            if int(config.manifest[kind]) == 6:
                appeared[kind] = true
                var lower: Dictionary = max_ranks.duplicate(true)
                lower["fleet_"+kind] = 2
                var capacity5: Dictionary = R.create_level(stage-1,P.stage_config(stage,lower))
                var capacity6: Dictionary = R.create_level(stage-1,config)
                check(R.simulate(capacity5).ok and R.simulate(capacity6).ok and capacity5.solution.size() == capacity6.solution.size()+1,"Top fleet rank saves an actual additional trip for its6-unit resource")
                check(_signature(capacity5) == _signature(capacity6),"Top upgrade benefit never comes from spawning more freight")
    check(appeared.size() == 6,"Every resource receives the6-unit threshold across future stages")
