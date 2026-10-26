extends SceneTree
const P = preload("res://puzzle.gd")
const L = preload("res://layout.gd")
var failures: Array[String] = []
var load_events := 0
var total_ticks := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    var left_level: Dictionary = P.create_level(0)
    var right_level: Dictionary = P.create_level(1)
    var ids: Dictionary = {}
    for cargo in left_level.feed_left+left_level.feed_right:
        ids[int(cargo.id)] = true
    for cargo in right_level.feed_left+right_level.feed_right:
        check(not ids.has(int(cargo.id)),"Cargo ids are unique across both authored levels")
    for level in range(2):
        for bay_count in [3,5]:
            _test_level(level,bay_count)
    _test_circulation()
    _test_bay_lifecycle()
    _test_unlocks_and_parallel_loading()
    _test_feeder_sides()
    if failures.is_empty():
        print("TRUCK_PUZZLE_TESTS_OK: 64/88 trucks with 3/5 bays, spatial proof, %d cargo loads, %d belt ticks, conservation, recirculation, locked bays, parallel loading and snapshot undo" % [load_events,total_ticks])
        quit(0)
    else:
        print("TRUCK_PUZZLE_TESTS_FAILED: ",failures.size())
        quit(1)

func _test_level(level: int, bay_count: int) -> void:
    var s: Dictionary = P.create_level(level)
    var expected: int = int(L.COUNTS[level])
    check(s.trucks.size() == expected and s.total == expected,"Requested truck count")
    check(s.width == L.WIDTH and s.height == L.HEIGHT and s.belt.size() == L.BELT_SLOTS,"Grid and finite belt dimensions")
    check(s == P.create_level(level),"Level generation is deterministic and instances are independent")
    check(s.bays == [-1,-1,-1,-2,-2],"Three default bays and two visibly locked spaces")
    P.unlock_bays(s,bay_count)
    var occupied: Dictionary = {}
    var expected_capacity := 0
    for truck in s.trucks:
        check(int(truck.id) >= 0 and int(truck.id) < expected,"Truck ids index the array")
        check(int(truck.len) in [2,3] and int(truck.capacity) in [2,3,4],"Small footprints and readable capacities")
        check(str(truck.type) in P.TYPES,"Every cargo category is supported")
        expected_capacity += int(truck.capacity)
        for cell in _cells(truck):
            check(cell.x >= 0 and cell.x < L.WIDTH and cell.y >= 0 and cell.y < L.HEIGHT,"Truck fits the board")
            check(not occupied.has(cell),"No overlapping truck footprints")
            occupied[cell] = int(truck.id)
    check(expected_capacity == int(s.cargo_total),"Cargo equals total capacity")
    var consumed: Dictionary = {}
    _audit(s,consumed)
    var invalid_before: Dictionary = s.duplicate(true)
    check(not P.dispatch(s,-1).ok and not P.dispatch(s,999).ok,"Invalid indices rejected")
    check(s == invalid_before,"Invalid input does not mutate state")
    var blocked_count := 0
    for truck in s.trucks:
        var oracle: int = _oracle_blocker(s,int(truck.id))
        check(P.blocker_id(s,int(truck.id)) == oracle,"Blocker ray agrees with independent occupancy oracle")
        if oracle >= 0:
            blocked_count += 1
            check(not P.dispatch(s,int(truck.id)).ok,"Blocked departure is rejected")
    check(blocked_count > expected/3,"Dense yard has meaningful exit dependencies")
    for id in s.solution:
        check(_oracle_blocker(s,int(id)) == -1,"Reverse placement proves each spatial exit")
        check(P.can_dispatch(s,int(id)),"Known route has a free gate and exit")
        var snapshot: Dictionary = s.duplicate(true)
        var dispatched: Dictionary = P.dispatch(s,int(id))
        check(dispatched.ok and int(dispatched.bay) >= 0,"Known route dispatches")
        var after_dispatch: Dictionary = s.duplicate(true)
        check(not P.dispatch(s,int(id)).ok and s == after_dispatch,"Duplicate dispatch is side-effect free")
        var replay: Dictionary = snapshot.duplicate(true)
        check(P.dispatch(replay,int(id)) == dispatched and replay == s,"Undo snapshot replays exact dispatch")
        # No loading before the controller's arrival callback.
        var before_loaded: int = int(s.trucks[int(id)].loaded)
        var drive_events: Dictionary = P.tick(s)
        _events(s,drive_events,consumed)
        check(int(s.trucks[int(id)].loaded) == before_loaded,"Driving truck cannot load early")
        P.arrive(s,int(id))
        var tick_count := 0
        while str(s.trucks[int(id)].status) == "loading" and tick_count < 1200:
            var before_tick: Dictionary = s.duplicate(true)
            var events: Dictionary = P.tick(s)
            var tick_replay: Dictionary = before_tick.duplicate(true)
            check(P.tick(tick_replay) == events and tick_replay == s,"Snapshot undo replays cargo rotation and loading exactly")
            _events(s,events,consumed)
            tick_count += 1
        check(str(s.trucks[int(id)].status) == "departing","Known route fills from genuinely circulating cargo")
        if str(s.trucks[int(id)].status) != "departing":
            print("STALLED_LEVEL_",level," truck=",id," loaded=",s.trucks[int(id)].loaded," belt=",s.belt," feeds=",s.feed_left.size(),"/",s.feed_right.size())
            break
        check(int(id) in s.bays,"Full truck retains bay during departure animation")
        var delivered_before: int = int(s.delivered)
        P.release_bay(s,int(id))
        check(int(s.delivered) == delivered_before+1 and str(s.trucks[int(id)].status) == "done","Departure completion delivers exactly once")
        var released: Dictionary = s.duplicate(true)
        P.release_bay(s,int(id))
        check(s == released,"Repeated release cannot duplicate deliveries")
        _audit(s,consumed)
    check(P.is_won(s) and consumed.size() == expected_capacity,"Both dense levels can deliver every generated cargo unit")
    check(not P.is_stuck(s),"Completed depot is not stuck")
    print("TRUCK_LEVEL_%d: %d trucks; %d bays; %d cargo units; %d initially blocked" % [level,expected,bay_count,expected_capacity,blocked_count])

func _events(s: Dictionary, events: Dictionary, consumed: Dictionary) -> void:
    total_ticks += 1
    for event in events.loads:
        var id: int = int(event.cargo_id)
        check(not consumed.has(id),"Each cargo id loads only once")
        consumed[id] = true
        load_events += 1
        check(str(s.trucks[int(event.truck_id)].type) == str(event.type),"Only compatible cargo loads")
    _audit(s,consumed)

func _audit(s: Dictionary, consumed: Dictionary) -> void:
    var present: Dictionary = {}
    for cargo in s.feed_left+s.feed_right+s.belt:
        if cargo == null:
            continue
        var id: int = int(cargo.id)
        check(not present.has(id) and not consumed.has(id),"Cargo cannot be duplicated across sources, belt and loaded trucks")
        present[id] = true
    var loaded := 0
    for truck in s.trucks:
        loaded += int(truck.loaded)
        check(int(truck.loaded) <= int(truck.capacity),"No overloading")
    check(loaded == consumed.size(),"Truck seat counts agree with unique loaded ids")
    check(present.size()+consumed.size() == int(s.cargo_total),"All finite cargo is conserved every tick")

func _fixture(types: Array, capacity: int = 2) -> Dictionary:
    var trucks: Array = []
    for id in range(types.size()):
        trucks.append({"id":id,"x":id*3,"y":1,"dir":0,"len":2,"type":types[id],"capacity":capacity,"loaded":0,"status":"yard"})
    var belt: Array = []
    belt.resize(L.BELT_SLOTS)
    return {"width":L.WIDTH,"height":L.HEIGHT,"trucks":trucks,"belt":belt,"feed_left":[],"feed_right":[],"bays":[-1,-1,-1,-2,-2],"total":types.size(),"delivered":0,"moves":0,"solution":range(types.size()),"cargo_total":0,"ticks":0}

func _test_circulation() -> void:
    var s: Dictionary = _fixture(["kyl"])
    check(P.dispatch(s,0).ok,"Circulation fixture dispatch")
    P.arrive(s,0)
    s.belt[P.GATES[0]-1] = {"id":0,"type":"adr"}
    s.belt[P.GATES[0]-2] = {"id":1,"type":"kyl"}
    s.cargo_total = 2
    var consumed: Dictionary = {}
    var first: Dictionary = P.tick(s)
    _events(s,first,consumed)
    check(first.loads.is_empty() and s.belt[P.GATES[0]].id == 0,"Mismatching goods pass a gate intact")
    var second: Dictionary = P.tick(s)
    _events(s,second,consumed)
    check(second.loads.size() == 1 and int(second.loads[0].cargo_id) == 1,"Compatible cargo behind mismatch can load; no FIFO shortcut")
    for _step in range(18):
        _events(s,P.tick(s),consumed)
    var remaining := -1
    for slot in range(18):
        if s.belt[slot] != null:
            remaining = slot
    check(remaining == P.GATES[0]+1 and s.belt[remaining].id == 0,"Unmatched cargo completes a full lap without vanishing")

func _test_bay_lifecycle() -> void:
    var s: Dictionary = _fixture(["kyl","frys","schakt","timmer"],1)
    for id in range(3):
        check(P.dispatch(s,id).ok,"Three bays can be reserved")
        P.arrive(s,id)
    check(not P.can_dispatch(s,3) and P.dispatch(s,3).reason == "bays_full","Fourth truck waits for a real bay release")
    for slot in range(18):
        s.belt[slot] = {"id":slot,"type":"adr"}
    s.feed_left = [{"id":18,"type":"kyl"}]
    s.cargo_total = 19
    check(P.is_stuck(s),"Full ring plus three mismatched occupied gates is a certain deadlock")
    var cargo_before: Array = s.belt.duplicate(true)
    for _step in range(18):
        var events: Dictionary = P.tick(s)
        check(events.spawned.is_empty() and events.loads.is_empty(),"Full mismatching ring does not overflow or consume hidden feed")
    check(s.belt == cargo_before and s.feed_left.size() == 1,"Finite ring really recirculates")
    s.belt[P.GATES[0]-1] = {"id":P.GATES[0]-1,"type":"kyl"}
    check(not P.is_stuck(s),"A match anywhere on the ring prevents declaring deadlock")
    var loaded: Dictionary = P.tick(s)
    check(loaded.departures == [0] and str(s.trucks[0].status) == "departing","Capacity transition emits departure once")
    check(not P.can_dispatch(s,3),"Departing truck still owns its bay")
    for _step in range(20):
        check(0 not in P.tick(s).departures,"Full truck cannot emit repeated departure events")
    P.release_bay(s,0)
    check(P.can_dispatch(s,3),"Controller release frees the loading bay")
    P.release_bay(s,1)
    check(str(s.trucks[1].status) == "loading" and int(s.delivered) == 1,"Unfinished truck cannot be marked done")

func _test_unlocks_and_parallel_loading() -> void:
    var s: Dictionary = _fixture(["kyl","frys","schakt","adr","timmer"],1)
    for id in range(3):
        check(P.dispatch(s,id).ok,"Default bay is assignable")
        P.arrive(s,id)
    check(not P.dispatch(s,3).ok and s.bays == [0,1,2,-2,-2],"Locked spaces cannot receive trucks")
    var snapshot: Dictionary = s.duplicate(true)
    P.unlock_bays(s,4)
    check(s.bays == [0,1,2,-1,-2],"Unlock during loading preserves all occupied bay ids")
    check(P.dispatch(s,3).bay == 3,"Fourth truck uses the newly unlocked space")
    P.arrive(s,3)
    P.unlock_bays(s,5)
    check(P.dispatch(s,4).bay == 4,"Fifth truck uses the fifth unlocked space")
    P.arrive(s,4)
    P.unlock_bays(s,3)
    check(s.bays == [0,1,2,3,4],"Unlock is monotonic and never overwrites active trucks")
    var restored: Dictionary = snapshot.duplicate(true)
    P.unlock_bays(restored,5)
    check(restored.bays == [0,1,2,-1,-1],"Persistent unlock overlay survives restoring an older snapshot")
    P.unlock_bays(restored,500)
    check(restored.bays == [0,1,2,-1,-1],"Unlock clamps to the five real spaces")
    for bay in range(5):
        s.belt[P.GATES[bay]-1] = {"id":bay,"type":str(s.trucks[bay].type)}
    s.cargo_total = 5
    var events: Dictionary = P.tick(s)
    check(events.loads.size() == 5 and events.departures == [0,1,2,3,4],"All five gates can load and finish independently in one belt tick")
    for id in range(5):
        P.release_bay(s,id)
    check(P.is_won(s) and s.bays == [-1,-1,-1,-1,-1],"Five parallel deliveries release real bays and win correctly")
    var stuck: Dictionary = _fixture(["kyl","frys","schakt"],1)
    for id in range(3):
        P.dispatch(stuck,id)
        P.arrive(stuck,id)
    for slot in range(L.BELT_SLOTS):
        stuck.belt[slot] = {"id":slot,"type":"adr"}
    check(P.is_stuck(stuck),"Locked bays do not hide a deadlock in all three unlocked bays")
    P.unlock_bays(stuck,4)
    check(not P.is_stuck(stuck),"A newly unlocked free bay removes certain deadlock")

func _test_feeder_sides() -> void:
    var s: Dictionary = _fixture(["kyl"])
    s.feed_left = [{"id":0,"type":"kyl"}]
    s.feed_right = [{"id":1,"type":"frys"}]
    s.cargo_total = 2
    var events: Dictionary = P.tick(s)
    check(events.spawned.size() == 2,"Both entry feeders can spawn into their physical sides")
    check(int(events.spawned[0].slot) == L.BELT_SLOTS/2 and int(events.spawned[0].cargo_id) == 0,"Left feeder enters at the negative-X side of the ring")
    check(int(events.spawned[1].slot) == 0 and int(events.spawned[1].cargo_id) == 1,"Right feeder enters at the positive-X side of the ring")

func _cells(truck: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for n in range(int(truck.len)):
        result.append(Vector2i(int(truck.x)+(n if int(truck.dir)%2 else 0),int(truck.y)+(0 if int(truck.dir)%2 else n)))
    return result

func _oracle_blocker(s: Dictionary, id: int) -> int:
    var truck: Dictionary = s.trucks[id]
    var step: Vector2i = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT][int(truck.dir)]
    var front := Vector2i(int(truck.x),int(truck.y))
    if int(truck.dir) in [1,2]:
        front += step*(int(truck.len)-1)
    var point: Vector2i = front+step
    while point.x >= 0 and point.x < int(s.width) and point.y >= 0 and point.y < int(s.height):
        for other in s.trucks:
            if int(other.id) != id and str(other.status) == "yard" and point in _cells(other):
                return int(other.id)
        point += step
    return -1
