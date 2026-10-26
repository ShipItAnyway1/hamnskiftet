extends SceneTree
const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const L = preload("res://layout.gd")
var failures: Array[String] = []
var ticks := 0
var loaded_units := 0
var completed_trucks := 0

func check(value: bool, message: String) -> void:
    if not value:
        if failures.size() < 24:
            push_error(message)
        failures.append(message)

func _initialize() -> void:
    _ranks_and_purchases()
    _legacy_contract()
    _resource_capacities()
    _obstacles_and_saves()
    for stage in range(1,11):
        _complete_stage(stage,P.defaults(),"base")
        var maximum: Dictionary = P.defaults()
        for key in P.KEYS:
            maximum[key] = P.max_rank(key)
        _complete_stage(stage,maximum,"max")
        for rank in [1,2]:
            var middle: Dictionary = P.defaults()
            for key in P.FLEET_KEYS: middle[key] = rank
            _complete_stage(stage,middle,"capacity%d" % (3+rank))
        var mixed: Dictionary = P.defaults()
        for index in range(P.FLEET_KEYS.size()): mixed[P.FLEET_KEYS[index]] = (stage+index)%4
        _complete_stage(stage,mixed,"mixed")
    if failures.is_empty():
        print("PROGRESSION_TESTS_OK: all ranks and purchase outcomes, per-resource capacity3→6 and V4 migration, 50 full V5 campaign runs, %d trucks, %d units, %d ticks, value/identity conservation, snapshots and legacy compatibility" % [completed_trucks,loaded_units,ticks])
        quit(0)
    else:
        print("PROGRESSION_TESTS_FAILED: ",failures.size())
        quit(1)

func _ranks_and_purchases() -> void:
    check(P.defaults().size() == 10 and P.FLEET_KEYS.size() == 6 and P.GENERAL_KEYS.size() == 4,"Six independent resources plus four general ranks")
    check(P.sanitize(null) == P.defaults() and P.sanitize([]) == P.defaults(),"Invalid save shapes sanitize safely")
    for old_rank in range(11):
        var migrated: Dictionary = P.sanitize({"fleet":old_rank})
        for key in P.FLEET_KEYS:
            check(migrated[key] == mini(3,ceili(float(old_rank)/3.0)),"Every V4 global fleet rank migrates into all resource fleets")
    check(P.sanitize({"fleet":9,"fleet_kyl":1}).fleet_kyl == 1,"Explicit new rank overrides migration")
    var dirty := {"fleet_kyl":999,"loader":-2,"belt":"six","warehouse":true,"parking":2.8,"alien":90}
    var clean: Dictionary = P.sanitize(dirty)
    check(clean.fleet_kyl == 3 and clean.loader == 0 and clean.belt == 0 and clean.warehouse == 0 and clean.parking == 2 and not clean.has("alien"),"Corrupt save ranks clamp safely")
    check(dirty.fleet_kyl == 999,"Sanitize never mutates source")
    check(P.sanitize({"fleet_kyl":1.0e100,"loader":NAN,"belt":INF}).fleet_kyl == 3,"Extreme numerical ranks cannot overflow")
    check(P.max_rank("fleet_kyl") == 3 and P.max_rank("loader") == 6 and P.max_rank("warehouse") == 5 and P.max_rank("parking") == 2,"Rank caps")
    check(P.cost("parking",0) == 80 and P.cost("parking",1) == 140,"Existing dock prices preserved")
    check(P.cost("missing",0) == 0 and P.effect_text("missing",0) == "","Unknown upgrade keys are safe")
    for key in P.KEYS:
        var ranks: Dictionary = P.defaults()
        var previous_cost := 0
        for rank in range(P.max_rank(key)):
            var price: int = P.cost(key,rank)
            check(price > previous_cost,"Upgrade prices rise rather than repeat or turn negative")
            previous_cost = price
            var snapshot: Dictionary = ranks.duplicate(true)
            var rejected: Dictionary = P.purchase(ranks,price-1,key)
            check(not rejected.ok and rejected.reason == "funds" and ranks == snapshot,"Unaffordable purchase is pure and returns false")
            var accepted: Dictionary = P.purchase(ranks,price,key)
            check(accepted.ok and accepted.balance == 0 and accepted.cost == price and int(accepted.levels[key]) == rank+1,"Exact-price purchase increments one rank and debits exact price")
            check(ranks == snapshot,"Accepted proposal never mutates its input")
            check(not P.effect_text(key,rank).is_empty() and not P.next_effect_text(key,rank).is_empty(),"UI copy is available at every rank")
            ranks = accepted.levels
        check(P.cost(key,P.max_rank(key)) == 0 and P.next_effect_text(key,P.max_rank(key)) == "Maxnivå","Max rank has no further price or effect")
        check(not P.purchase(ranks,100000,key).ok,"Max rank cannot be bought again")
    check(not P.purchase(P.defaults(),100,"missing").ok,"Unknown purchase returns false")
    for rank in range(7):
        check(is_equal_approx(P.loading_multiplier(rank),1.0+.12*float(rank)),"Every loader rank has the documented speed")
        check(is_equal_approx(P.belt_multiplier(rank),1.0+.08*float(rank)),"Every belt rank has the documented speed")
    for rank in range(6):
        check(is_equal_approx(P.value_multiplier(rank),1.0+.25*float(rank)),"Every warehouse rank has the documented value multiplier")
    check(is_equal_approx(P.loading_multiplier(6),1.72) and is_equal_approx(P.belt_multiplier(6),1.48),"Speed effects follow exact linear formulas")
    check(is_equal_approx(P.value_multiplier(5),2.25) and P.bay_count(2) == 5,"Warehouse and parking effects cap correctly")
    check(P.bay_count(-10) == 3 and P.bay_count(200) == 5,"Effect inputs clamp")
    check(P.claim_key(1,2) != P.claim_key(2,2) and P.claim_key(1,2) != P.claim_key(1,3),"Receipt keys distinguish stage and truck identity")
    check(P.delivery_reward({}) == 0 and P.delivery_reward({"delivery_value":-10}) == 0,"No value means no reward")

func _legacy_contract() -> void:
    for level in range(2):
        var old: Dictionary = R.create_level(level)
        check(old == R.create_level(level,{}),"Omitted and empty config preserve the exact legacy level")
        check(old.total == L.COUNTS[level] and not old.has("campaign"),"Legacy64/88 levels have no campaign-only state")
        for truck in old.trucks:
            check(int(truck.capacity) in [2,3,4] and not truck.has("delivery_value"),"Legacy truck capacities and schema preserved")
        for cargo in old.feed_left+old.feed_right:
            check(not cargo.has("value") and not cargo.has("quality"),"Legacy cargo schema preserved")

func _resource_capacities() -> void:
    for kind in R.TYPES:
        for rank in range(4):
            var ranks: Dictionary = P.defaults()
            ranks["fleet_"+kind] = rank
            var config: Dictionary = P.stage_config(5,ranks)
            var s: Dictionary = R.create_level(4,config)
            check(P.capacity(kind,rank) == 3+rank,"Resource capacity increases by one at each rank")
            for truck in s.trucks:
                var expected: int = 3+rank if truck.type == kind else 3
                check(truck.capacity == expected and truck.len == (3 if expected >= 5 else 2),"Only purchased resource receives capacity and physical length")
    check(P.capacity("kyl",-10) == 3 and P.capacity("kyl",900) == 6,"Capacity inputs clamp")

func _obstacles_and_saves() -> void:
    var Save = load("res://campaign_save.gd")
    var ranks: Dictionary = P.defaults()
    var state: Dictionary = R.create_level(2,P.stage_config(3,ranks))
    check(state.obstacles.size() == 3,"Stage3 introduces two containers and a sliding gate")
    var original: Dictionary = state.duplicate(true)
    check(R.obstacle_blocker(state,0) == 2 and not R.can_dispatch(state,0),"Real gate blocks the first northbound truck")
    var isolated: Dictionary = state.duplicate(true)
    for truck in isolated.trucks:
        if int(truck.id) > 1: truck.status = "done"
    check(R.dispatch(isolated,0).reason == "obstacle","Dispatch explains gate blockage once parked trucks clear")
    check(state == original,"Rejected obstacle dispatch does not mutate snapshot")
    check(not R.move_obstacle(state,0).ok and not R.move_obstacle(state,999).ok,"Static/invalid obstacles cannot move")
    check(R.move_obstacle(state,2).ok and R.obstacle_blocker(state,1) == 2,"Sliding into other corridor blocks its truck instead")
    check(not Save.validate(state,ranks,2).is_empty(),"Moved gate state is a resumable canonical V5 snapshot")
    var moved: Dictionary = state.duplicate(true)
    check(R.move_obstacle(state,2).ok,"Gate can be moved back for a different planning choice")
    state = moved.duplicate(true)
    check(state.obstacles[2].position_index == 1 and R.obstacle_blocker(state,1) == 2,"Deep snapshot restores exact obstacle choice")
    var container_probe: Dictionary = state.duplicate(true)
    var fixed: Dictionary = container_probe.obstacles[0]
    container_probe.trucks[2].dir = 0
    container_probe.trucks[2].x = fixed.x
    container_probe.trucks[2].y = int(fixed.y)+2
    check(R.obstacle_blocker(container_probe,2) == 0,"Static containers physically block straight grid exit rays")
    var roundtrip := ConfigFile.new()
    roundtrip.set_value("test","state",state)
    roundtrip.set_value("test","ranks",ranks)
    check(roundtrip.save("/private/tmp/truck-v5-rules-roundtrip.cfg") == OK,"Rules snapshot serializes")
    var reload := ConfigFile.new()
    reload.load("/private/tmp/truck-v5-rules-roundtrip.cfg")
    check(not Save.validate(reload.get_value("test","state"),ranks,2).is_empty(),"Moved gate survives actual ConfigFile roundtrip")
    var bad: Dictionary = state.duplicate(true)
    bad.obstacles[2].x += 1
    check(Save.validate(bad,ranks,2).is_empty(),"Forged gate position rejected")
    bad = state.duplicate(true)
    bad.trucks[0].capacity += 1
    check(Save.validate(bad,ranks,2).is_empty(),"Forged resource capacity rejected")
    bad = state.duplicate(true)
    bad.config.version = 4
    check(Save.validate(bad,ranks,2).is_empty(),"V4 active snapshot safely falls back to fresh V5 stage")
    state = original.duplicate(true)
    var gate: Dictionary = state.obstacles[2]
    var blocker: Dictionary = state.trucks[2]
    var target: Vector2i = gate.positions[1]
    blocker.x = target.x
    blocker.y = target.y
    var occupied_snapshot: Dictionary = state.duplicate(true)
    check(not R.move_obstacle(state,2).ok and state == occupied_snapshot,"Gate cannot slide through a parked truck, rejected action stays pure")

func _complete_stage(stage: int, ranks: Dictionary, label: String) -> void:
    var config: Dictionary = P.stage_config(stage,ranks)
    var s: Dictionary = R.create_level(stage-1,config)
    check(s == R.create_level(stage-1,config),"Campaign stage generation is deterministic")
    var expected_counts := [10,12,14,16,18,22,26,30]
    check(s.total == expected_counts[mini(stage-1,7)] and s.trucks.size() == s.total,"Campaign ramps fleet size at the authored stages")
    check(s.width == L.WIDTH and s.height == L.HEIGHT,"Spawn cluster does not change physical yard coordinates")
    var bounds: Rect2i = config.spawn_bounds
    check(Rect2i(0,0,L.WIDTH,L.HEIGHT).encloses(bounds),"Spawn cluster remains inside the real yard")
    check(absf(float(bounds.get_center().x)-float(L.WIDTH)*.5) <= .5 and absf(float(bounds.get_center().y)-float(L.HEIGHT)*.5) <= .5,"Truck cluster is centered")
    check(("adr" in config.types) == (stage >= 3) and ("bransle" in config.types) == (stage >= 5),"Cargo categories unlock at the documented stages")
    check(config.types.size() == (4 if stage < 3 else (5 if stage < 5 else 6)),"Early stage has four categories for three default docks")
    check(s.bays.count(-1) == P.bay_count(int(ranks.parking)),"Parking rank opens correct number of bays")
    var occupied: Dictionary = {}
    var units := 0
    var large := 0
    var expected_reward := 0
    for truck in s.trucks:
        check(str(truck.type) in config.types,"Truck uses an unlocked category")
        check(int(truck.capacity) == int(config.capacities[truck.type]) and int(truck.len) == (3 if int(truck.capacity) >= 5 else 2),"Every resource receives exact upgraded capacity and physical length")
        units += int(truck.capacity)
        large += 1 if int(truck.len) == 3 else 0
        check(float(truck.delivery_value) == 0 and P.delivery_reward(truck) == 0,"An empty truck earns nothing")
        expected_reward += roundi(float(truck.expected_value))
        for cell in _cells(truck):
            check(bounds.has_point(cell) and not occupied.has(cell),"Truck fits its centered cluster without overlap")
            occupied[cell] = int(truck.id)
    check(units == int(s.cargo_total),"All required units are generated exactly once")
    var consumed: Dictionary = {}
    var loaded_value := 0.0
    var reward := 0
    for step in s.solution_steps:
        if step.action == "move_obstacle":
            check(R.move_obstacle(s,int(step.id)).ok,"Proven sliding-gate step succeeds")
            continue
        var id: int = int(step.id)
        check(R.can_dispatch(s,int(id)),"Reverse placement route stays spatially valid")
        check(R.dispatch(s,int(id)).ok,"Proven campaign route dispatches")
        R.arrive(s,int(id))
        var guard := 0
        while str(s.trucks[int(id)].status) == "loading" and guard < 1200:
            var replay_from: Dictionary = {}
            if guard%17 == 0:
                replay_from = s.duplicate(true)
            var events: Dictionary = R.tick(s)
            ticks += 1
            if not replay_from.is_empty():
                var replay: Dictionary = replay_from.duplicate(true)
                check(R.tick(replay) == events and replay == s,"Snapshot/replay preserves cargo quality, money and ring motion")
            for event in events.loads:
                var cargo_id: int = int(event.cargo_id)
                check(not consumed.has(cargo_id),"Cargo cannot be paid/loaded twice")
                consumed[cargo_id] = float(event.value)
                check(int(event.quality) == int(ranks.warehouse) and is_equal_approx(float(event.value),float(config.cargo_values[str(event.type)])),"Load event retains exact quality and upgraded unit value")
                loaded_value += float(event.value)
                loaded_units += 1
            _audit(s,consumed,loaded_value)
            guard += 1
        if str(s.trucks[int(id)].status) != "departing":
            check(false,"Campaign route stalled: stage%d %s truck%d" % [stage,label,id])
            return
        var truck: Dictionary = s.trucks[int(id)]
        check(is_equal_approx(float(truck.delivery_value),float(truck.expected_value)),"Full truck's actual accumulated value equals forecast")
        reward += P.delivery_reward(truck)
        R.release_bay(s,int(id))
        completed_trucks += 1
    check(R.is_won(s) and consumed.size() == units,"Campaign completes with all goods and trucks accounted for")
    check(is_equal_approx(loaded_value,float(s.cargo_value_total)) and reward == expected_reward,"All generated cargo value reaches actual truck receipts")
    if stage == 1 and label == "base":
        check(reward+P.stage_bonus(stage) >= P.cost("fleet_kyl",0)+P.cost("belt",0),"First shift funds at least two distinct meaningful upgrades")
    print("CAMPAIGN_%02d_%s: %d trucks, %d units, %d large, %d coins plus%d bonus" % [stage,label,s.total,units,large,reward,P.stage_bonus(stage)])

func _audit(s: Dictionary, consumed: Dictionary, loaded_value: float) -> void:
    var seen: Dictionary = {}
    var remaining_value := 0.0
    for cargo in s.feed_left+s.feed_right+s.belt:
        if cargo == null: continue
        var id: int = int(cargo.id)
        check(not seen.has(id) and not consumed.has(id),"Finite cargo identities remain unique across both feeders, ring and trucks")
        seen[id] = true
        remaining_value += float(cargo.value)
    check(seen.size()+consumed.size() == int(s.cargo_total),"No campaign goods vanish while unmatched goods circulate")
    check(is_equal_approx(remaining_value+loaded_value,float(s.cargo_value_total)),"Monetary cargo value is conserved before payout rounding")
    var truck_value := 0.0
    for truck in s.trucks:
        truck_value += float(truck.delivery_value)
    check(is_equal_approx(truck_value,loaded_value),"Truck receipts contain only value actually loaded")

func _cells(truck: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for n in range(int(truck.len)):
        result.append(Vector2i(int(truck.x)+(n if int(truck.dir)%2 else 0),int(truck.y)+(0 if int(truck.dir)%2 else n)))
    return result
