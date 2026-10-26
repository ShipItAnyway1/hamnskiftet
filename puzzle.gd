extends RefCounted

const L = preload("res://layout.gd")
const TYPES := ["kyl","frys","schakt","adr","timmer","bransle"]
const BELT_SIZE := L.BELT_SLOTS
const GATES := L.BAY_GATES
const DIRECTIONS := [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]

static func create_level(index: int = 0, config: Dictionary = {}) -> Dictionary:
    if not config.is_empty():
        return _create_campaign(index,config)
    var level: int = clampi(index,0,1)
    var count: int = int(L.COUNTS[level])
    var trucks: Array = _generate_yard(count,level)
    var solution: Array[int] = []
    for id in range(trucks.size()-1,-1,-1):
        solution.append(id)
    var feed_left: Array = []
    var feed_right: Array = []
    var cargo_id := 0
    for id in solution:
        var truck: Dictionary = trucks[id]
        for _unit in range(int(truck.capacity)):
            var cargo := {"id":level*100000+cargo_id,"type":truck.type}
            if cargo_id%2 == 0:
                feed_left.append(cargo)
            else:
                feed_right.append(cargo)
            cargo_id += 1
    var belt: Array = []
    belt.resize(BELT_SIZE)
    return {"name":"Morgonens leveranser" if level == 0 else "Depån vid kajen", "width":L.WIDTH,"height":L.HEIGHT,
        "trucks":trucks,"belt":belt,"feed_left":feed_left,"feed_right":feed_right,
        "bays":[-1,-1,-1,-2,-2],"total":count,"delivered":0,"moves":0,"solution":solution,
        "cargo_total":cargo_id,"ticks":0}

static var _campaign_cache: Dictionary = {}

static func _resource_order(config: Dictionary) -> Array:
    var order: Array = config.types.duplicate()
    var rng := RandomNumberGenerator.new()
    rng.seed = int(config.seed)+7107
    for index in range(order.size()-1,0,-1):
        var other: int = rng.randi_range(0,index)
        var swap = order[index]
        order[index] = order[other]
        order[other] = swap
    var locked: String = str(config.get("gate_type",""))
    if locked in order:
        order.erase(locked)
        order.append(locked)
    return order

static func _create_campaign(index: int, config: Dictionary) -> Dictionary:
    var key: String = var_to_str(config)
    if _campaign_cache.has(key): return _campaign_cache[key].duplicate(true)
    var stage: int = maxi(1,int(config.get("stage",index+1)))
    var order: Array = _resource_order(config)
    var layout: Dictionary = _generate_manifest_yard(config,order)
    var trucks: Array = layout.trucks
    var left: Array = []
    var right: Array = []
    var cargo_order: Array = []
    var boundaries: Array[int] = []
    for kind in order:
        for _unit in range(int(config.manifest[kind])): cargo_order.append(kind)
        boundaries.append(cargo_order.size())
    # Mix neighboring resource blocks without hiding a needed last unit behind
    # an arbitrarily large unrelated prefix. The order is seed-only, never
    # derived from the purchased capacities or the number of available trucks.
    var rng := RandomNumberGenerator.new()
    rng.seed = int(config.seed)+7717
    for boundary in boundaries:
        if boundary < cargo_order.size() and rng.randf() < .7:
            var swap = cargo_order[boundary-1]
            cargo_order[boundary-1] = cargo_order[boundary]
            cargo_order[boundary] = swap
    var unit := 0
    var total_value := 0.0
    for kind in cargo_order:
        var value: float = float(config.cargo_values[kind])
        var cargo := {"id":stage*1000000+unit,"type":str(kind),"value":value,"quality":int(config.quality)}
        if unit%2 == 0: left.append(cargo)
        else: right.append(cargo)
        total_value += value
        unit += 1
    var belt: Array = []
    belt.resize(BELT_SIZE)
    var state := {"name":str(config.get("name","Skift %02d" % stage)),"width":L.WIDTH,"height":L.HEIGHT,
        "trucks":trucks,"belt":belt,"feed_left":left,"feed_right":right,
        "bays":[-1,-1,-1,-2,-2],"total":trucks.size(),"delivered":0,"moves":0,
        "solution":layout.route,"solution_steps":[],"cargo_total":unit,"cargo_delivered":0,
        "manifest":config.manifest.duplicate(true),"manifest_delivered":{},"departures_by_type":{},
        "belt_limit":int(config.belt_limit),"rescue_used":0,"ticks":0,"campaign":true,"stage":stage,
        "cargo_value_total":total_value,"config":config.duplicate(true),"obstacles":_campaign_obstacles(config),
        "required_route":layout.route.duplicate(),"certificate_version":7}
    unlock_bays(state,int(config.get("bay_count",3)))
    for id in layout.route:
        state.solution_steps.append({"action":"dispatch","id":int(id)})
        state.solution_steps.append({"action":"wait","trucks":[int(id)]})
    var proof: Dictionary = simulate(state,state.solution_steps)
    if not proof.ok:
        # Content changes must never ship an unproven manifest. The bounded
        # search can interleave jobs if the preferred spatial certificate fails.
        var alternate: Array = solve(state,3500)
        proof = simulate(state,alternate)
        if proof.ok:
            state.solution_steps = alternate
            state.solution = []
            for step in alternate:
                if step.action == "dispatch": state.solution.append(int(step.id))
        else:
            push_error("V7 generator produced no rescue-free certificate: stage%d %s" % [stage,str(proof.reason)])
    state["certificate_valid"] = bool(proof.ok)
    _campaign_cache[key] = state.duplicate(true)
    return state

static func _campaign_obstacles(config: Dictionary) -> Array:
    if not bool(config.get("obstacles_enabled",false)): return []
    var bounds: Rect2i = config.spawn_bounds
    var middle: int = bounds.position.x+int(bounds.size.x/2)
    return [{"id":2,"kind":"boom","x":middle,"y":bounds.position.y+1,"w":2,"h":1,
        "movable":false,"opened":false,"opens_after":int(config.get("opens_after",2)),"required_type":""}]

static func obstacle_cells(obstacle: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for x in range(int(obstacle.x),int(obstacle.x)+int(obstacle.w)):
        for y in range(int(obstacle.y),int(obstacle.y)+int(obstacle.h)):
            result.append(Vector2i(x,y))
    return result

static func _manifest_truck(id: int, kind: String, config: Dictionary) -> Dictionary:
    var cap: int = clampi(int(config.capacities[kind]),3,6)
    return {"id":id,"x":0,"y":0,"dir":0,"len":3 if cap >= 5 else 2,"type":kind,
        "capacity":cap,"target_load":-1,"loaded":0,"status":"yard","delivery_value":0.0,
        "quality":int(config.quality),"expected_value":float(mini(cap,int(config.manifest[kind])))*float(config.cargo_values[kind])}

static func _fits_required(truck: Dictionary, occupied: Dictionary, barriers: Dictionary, protected: Dictionary = {}) -> bool:
    for cell in _cells(truck):
        if protected.has(cell): return false
    for cell in _cells(truck)+_ray(truck,L.WIDTH,L.HEIGHT):
        if occupied.has(cell) or barriers.has(cell): return false
    return true

static func _generate_manifest_yard(config: Dictionary, order: Array) -> Dictionary:
    var bounds: Rect2i = config.spawn_bounds
    var count: int = int(config.count)
    var jobs: Array = []
    for kind in order:
        var needed: int = ceili(float(config.manifest[kind])/float(config.capacities[kind]))
        for _job in range(needed): jobs.append(str(kind))
    var extras: int = count-jobs.size()
    var locked: String = str(config.get("gate_type",""))
    var middle: int = bounds.position.x+int(bounds.size.x/2)
    for attempt in range(80):
        var rng := RandomNumberGenerator.new()
        rng.seed = int(config.seed)+attempt*104729
        var trucks: Array = []
        trucks.resize(count)
        var occupied: Dictionary = {}
        var barriers: Dictionary = {}
        for obstacle in _campaign_obstacles(config):
            for cell in obstacle_cells(obstacle): barriers[cell] = true
        var required: Array[int] = []
        var locked_corridor: Dictionary = {}
        var locked_index := 0
        var ordinary_index := 0
        var valid := true
        # Required vehicles are a reverse-placement suffix. Later required
        # vehicles may block earlier ones; extras are placed AFTER the entire
        # certificate and may never occupy one of its exit rays.
        for insertion in range(jobs.size()):
            var kind: String = str(jobs[jobs.size()-1-insertion])
            var id: int = extras+insertion
            var truck: Dictionary = _manifest_truck(id,kind,config)
            if kind == locked:
                truck.x = middle+locked_index
                truck.y = bounds.position.y+3
                truck.dir = 0
                locked_index += 1
            elif locked != "" and ordinary_index < 3:
                # A separate three-job chain supplies real spatial planning.
                # The locked fuel/ADR corridor stays otherwise clear, making
                # the departure counter a meaningful independent restriction.
                if ordinary_index == 0:
                    truck.x = bounds.position.x+1
                    truck.y = bounds.position.y+8
                    truck.dir = 0
                elif ordinary_index == 1:
                    truck.x = bounds.position.x
                    truck.y = bounds.position.y+6
                    truck.dir = 1
                else:
                    truck.x = middle+3
                    truck.y = bounds.position.y+6
                    truck.dir = 0
                ordinary_index += 1
            else:
                var found := false
                for _try in range(2500):
                    truck.dir = rng.randi_range(0,3)
                    var width: int = int(truck.len) if int(truck.dir)%2 else 1
                    var height: int = int(truck.len) if int(truck.dir)%2 == 0 else 1
                    truck.x = rng.randi_range(bounds.position.x,bounds.end.x-width)
                    truck.y = rng.randi_range(bounds.position.y,bounds.end.y-height)
                    if _fits_required(truck,occupied,barriers,locked_corridor):
                        found = true
                        break
                if not found:
                    valid = false
                    break
            for cell in _cells(truck):
                if occupied.has(cell) or barriers.has(cell) or not bounds.has_point(cell): valid = false
            if not valid: break
            if kind != locked and not _fits_required(truck,occupied,barriers,locked_corridor):
                valid = false
                break
            trucks[id] = truck
            required.append(id)
            for cell in _cells(truck): occupied[cell] = true
            if kind == locked:
                for cell in _ray(truck,L.WIDTH,L.HEIGHT): locked_corridor[cell] = true
        if not valid: continue
        var reserved: Dictionary = occupied.duplicate()
        for id in required:
            for cell in _ray(trucks[id],L.WIDTH,L.HEIGHT): reserved[cell] = true
        for cell in barriers: reserved[cell] = true
        var extra_kinds: Array = config.types.duplicate()
        if locked in extra_kinds: extra_kinds.erase(locked)
        for id in range(extras):
            var kind: String = str(order[maxi(0,order.size()-2)]) if id < 3 else str(extra_kinds[rng.randi_range(0,extra_kinds.size()-1)])
            var truck: Dictionary = _manifest_truck(id,kind,config)
            var found := false
            for _try in range(4500):
                truck.dir = rng.randi_range(0,3)
                var width: int = int(truck.len) if int(truck.dir)%2 else 1
                var height: int = int(truck.len) if int(truck.dir)%2 == 0 else 1
                truck.x = rng.randi_range(bounds.position.x,bounds.end.x-width)
                truck.y = rng.randi_range(bounds.position.y,bounds.end.y-height)
                if id < 3:
                    # Three visible, tempting surplus choices have clean exits.
                    # Choosing all of a later resource can genuinely fill the
                    # docks while its freight still waits behind a full belt.
                    if int(truck.dir) == 0: truck.y = bounds.position.y
                    elif int(truck.dir) == 1: truck.x = bounds.end.x-width
                    elif int(truck.dir) == 2: truck.y = bounds.end.y-height
                    else: truck.x = bounds.position.x
                var free := true
                for cell in _cells(truck):
                    if reserved.has(cell):
                        free = false
                        break
                if free and id < 3:
                    for cell in _ray(truck,L.WIDTH,L.HEIGHT):
                        if occupied.has(cell) or barriers.has(cell):
                            free = false
                            break
                if free:
                    found = true
                    break
            if not found:
                valid = false
                break
            trucks[id] = truck
            for cell in _cells(truck):
                reserved[cell] = true
                occupied[cell] = true
            if id < 3:
                for cell in _ray(truck,L.WIDTH,L.HEIGHT): reserved[cell] = true
        if valid:
            required.reverse()
            return {"trucks":trucks,"route":required}
    push_error("Could not place V7 required chain and surplus trucks")
    return {"trucks":[],"route":[]}

static func obstacle_blocker(s: Dictionary, id: int) -> int:
    var truck: Dictionary = _truck(s,id)
    if truck.is_empty() or str(truck.status) != "yard": return -1
    var ray: Array[Vector2i] = _ray(truck,int(s.width),int(s.height))
    for obstacle in s.get("obstacles",[]):
        if bool(obstacle.get("opened",false)): continue
        for cell in obstacle_cells(obstacle):
            if cell in ray: return int(obstacle.id)
    return -1

static func move_obstacle(s: Dictionary, id: int) -> Dictionary:
    for obstacle in s.get("obstacles",[]):
        if int(obstacle.id) != id: continue
        if not bool(obstacle.get("movable",false)):
            return {"ok":false,"reason":"fixed"}
        var target: int = 1-int(obstacle.position_index)
        var position: Vector2i = obstacle.positions[target]
        var candidate: Dictionary = obstacle.duplicate(true)
        candidate.x = position.x
        candidate.y = position.y
        var cells: Array[Vector2i] = obstacle_cells(candidate)
        for truck in s.trucks:
            if str(truck.status) != "yard": continue
            for cell in _cells(truck):
                if cell in cells: return {"ok":false,"reason":"occupied"}
        for other in s.obstacles:
            if int(other.id) == id: continue
            for cell in obstacle_cells(other):
                if cell in cells: return {"ok":false,"reason":"occupied"}
        obstacle.x = position.x
        obstacle.y = position.y
        obstacle.position_index = target
        s.moves = int(s.moves)+1
        return {"ok":true,"reason":""}
    return {"ok":false,"reason":"invalid"}

static func _generate_yard(count: int, level: int) -> Array:
    # Add a truck only when it can leave the current arrangement. Later additions
    # may block it. Removing in reverse insertion order is therefore a proof of
    # spatial solvability; a seeded RNG makes each authored-size board repeatable.
    for attempt in range(100):
        var rng := RandomNumberGenerator.new()
        rng.seed = 78139+level*7919+attempt*104729
        var trucks: Array = []
        var occupied: Dictionary = {}
        var tries := 0
        while trucks.size() < count and tries < 30000:
            tries += 1
            var direction: int = rng.randi_range(0,3)
            var length: int = 3 if rng.randf() < .28 else 2
            var width: int = length if direction%2 == 1 else 1
            var height: int = length if direction%2 == 0 else 1
            var x: int = rng.randi_range(0,L.WIDTH-width)
            var y: int = rng.randi_range(0,L.HEIGHT-height)
            var candidate := {"id":trucks.size(),"x":x,"y":y,"dir":direction,"len":length,
                "type":TYPES[(trucks.size()+level)%TYPES.size()],"capacity":rng.randi_range(2,4),
                "loaded":0,"status":"yard"}
            var free := true
            for cell in _cells(candidate):
                if occupied.has(cell):
                    free = false
                    break
            if not free:
                continue
            for cell in _ray(candidate,L.WIDTH,L.HEIGHT):
                if occupied.has(cell):
                    free = false
                    break
            if not free:
                continue
            trucks.append(candidate)
            for cell in _cells(candidate):
                occupied[cell] = candidate.id
        if trucks.size() == count:
            return trucks
    push_error("Could not generate a solvable truck depot")
    return []

static func _cells(truck: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for offset in range(int(truck.len)):
        result.append(Vector2i(int(truck.x)+(offset if int(truck.dir)%2 == 1 else 0),int(truck.y)+(offset if int(truck.dir)%2 == 0 else 0)))
    return result

static func _ray(truck: Dictionary, width: int, height: int) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    var direction: int = int(truck.dir)
    var step: Vector2i = DIRECTIONS[direction]
    var point := Vector2i(int(truck.x),int(truck.y))
    if direction == 1:
        point.x += int(truck.len)
    elif direction == 2:
        point.y += int(truck.len)
    else:
        point += step
    while point.x >= 0 and point.x < width and point.y >= 0 and point.y < height:
        result.append(point)
        point += step
    return result

static func _truck(s: Dictionary, id: int) -> Dictionary:
    var trucks: Array = s.get("trucks",[])
    if id < 0 or id >= trucks.size():
        return {}
    var candidate: Dictionary = trucks[id]
    return candidate if int(candidate.get("id",-1)) == id else {}

static func blocker_id(s: Dictionary, id: int) -> int:
    var truck: Dictionary = _truck(s,id)
    if truck.is_empty() or str(truck.status) != "yard":
        return -1
    var occupied: Dictionary = {}
    for other in s.trucks:
        if int(other.id) == id or str(other.status) != "yard":
            continue
        for cell in _cells(other):
            occupied[cell] = int(other.id)
    for cell in _ray(truck,int(s.width),int(s.height)):
        if occupied.has(cell):
            return int(occupied[cell])
    return -2 if obstacle_blocker(s,id) >= 0 else -1

static func can_dispatch(s: Dictionary, id: int) -> bool:
    var truck: Dictionary = _truck(s,id)
    return not truck.is_empty() and str(truck.status) == "yard" and -1 in s.bays and blocker_id(s,id) == -1

static func dispatch(s: Dictionary, id: int) -> Dictionary:
    var truck: Dictionary = _truck(s,id)
    if truck.is_empty():
        return {"ok":false,"reason":"invalid","bay":-1}
    if str(truck.status) != "yard":
        return {"ok":false,"reason":"already_dispatched","bay":-1}
    if blocker_id(s,id) >= 0:
        return {"ok":false,"reason":"blocked","bay":-1}
    if obstacle_blocker(s,id) >= 0:
        return {"ok":false,"reason":"obstacle","bay":-1}
    var bay: int = s.bays.find(-1)
    if bay < 0:
        return {"ok":false,"reason":"bays_full","bay":-1}
    if bool(s.get("campaign",false)):
        truck.target_load = preview_target(s,id)
        truck.expected_value = float(truck.target_load)*float(s.config.cargo_values[truck.type])
    s.bays[bay] = id
    truck.status = "driving"
    s.moves = int(s.moves)+1
    return {"ok":true,"reason":"","bay":bay}

static func arrive(s: Dictionary, id: int) -> void:
    var truck: Dictionary = _truck(s,id)
    if not truck.is_empty() and str(truck.status) == "driving" and id in s.bays:
        truck.status = "loading"

static func unlock_bays(s: Dictionary, count: int) -> void:
    # Purchases belong to the controller. Applying the persistent entitlement
    # after undo must only unlock spaces, never replace active truck ids.
    var target: int = clampi(count,3,GATES.size())
    for bay in range(3,target):
        if int(s.bays[bay]) == -2:
            s.bays[bay] = -1

static func tick(s: Dictionary) -> Dictionary:
    var events := {"loads":[],"departures":[],"spawned":[]}
    var belt: Array = s.belt
    # Every occupied slot moves, including unmatched goods. There is no hidden
    # queue-front test and no disappearance when a load passes the wrong gate.
    var last = belt[BELT_SIZE-1]
    for slot in range(BELT_SIZE-1,0,-1):
        belt[slot] = belt[slot-1]
    belt[0] = last
    for bay in range(GATES.size()):
        var truck_id: int = int(s.bays[bay])
        if truck_id < 0:
            continue
        var truck: Dictionary = _truck(s,truck_id)
        if truck.is_empty() or str(truck.status) != "loading":
            continue
        var slot: int = GATES[bay]
        var cargo = belt[slot]
        var target: int = int(truck.get("target_load",truck.capacity))
        if target <= 0 or cargo == null or str(cargo.type) != str(truck.type) or int(truck.loaded) >= target:
            continue
        belt[slot] = null
        truck.loaded = int(truck.loaded)+1
        var load_event := {"truck_id":truck_id,"bay":bay,"cargo_id":int(cargo.id),"type":str(cargo.type)}
        if cargo.has("value"):
            load_event["value"] = float(cargo.value)
            load_event["quality"] = int(cargo.get("quality",0))
            truck.delivery_value = float(truck.get("delivery_value",0.0))+float(cargo.value)
        events.loads.append(load_event)
        if int(truck.loaded) == target:
            truck.status = "departing"
            events.departures.append(truck_id)
    # The two visible feeders alternate in the generated global cargo order.
    # If the next feeder entry is occupied, new inflow waits. Otherwise one
    # feeder could race ahead and fill the finite ring with much later stock,
    # invalidating even the reverse-placement completion route. This controls
    # entry only: every good already on the ring still circulates freely.
    for _spawn in range(2):
        if bool(s.get("campaign",false)) and belt_count(s) >= int(s.belt_limit): break
        var left: Array = s.feed_left
        var right: Array = s.feed_right
        if left.is_empty() and right.is_empty():
            break
        var source := 0
        if left.is_empty() or (not right.is_empty() and int(right[0].id) < int(left[0].id)):
            source = 1
        # Slot 9 is the physical left edge; slot 0 is the right edge.
        var slot: int = int(BELT_SIZE/2) if source == 0 else 0
        var feed: Array = s.feed_left if source == 0 else s.feed_right
        if belt[slot] != null:
            break
        var cargo: Dictionary = feed.pop_front()
        belt[slot] = cargo
        var spawn_event := {"slot":slot,"cargo_id":int(cargo.id),"type":str(cargo.type)}
        if cargo.has("value"):
            spawn_event["value"] = float(cargo.value)
            spawn_event["quality"] = int(cargo.get("quality",0))
        events.spawned.append(spawn_event)
    s.ticks = int(s.get("ticks",0))+1
    return events

static func release_bay(s: Dictionary, id: int) -> Array[int]:
    var truck: Dictionary = _truck(s,id)
    var bay: int = s.bays.find(id)
    if truck.is_empty() or str(truck.status) != "departing" or bay < 0: return []
    var target: int = int(truck.get("target_load",truck.capacity))
    if target <= 0 or int(truck.loaded) != target: return []
    s.bays[bay] = -1
    truck.status = "done"
    s.delivered = int(s.delivered)+1
    if bool(s.get("campaign",false)):
        s.cargo_delivered = int(s.cargo_delivered)+int(truck.loaded)
        s.manifest_delivered[truck.type] = int(s.manifest_delivered.get(truck.type,0))+int(truck.loaded)
        s.departures_by_type[truck.type] = int(s.departures_by_type.get(truck.type,0))+1
        return refresh_obstacles(s)
    return []

static func refresh_obstacles(s: Dictionary) -> Array[int]:
    var opened: Array[int] = []
    for obstacle in s.get("obstacles",[]):
        if str(obstacle.get("kind","")) != "boom" or bool(obstacle.get("opened",false)): continue
        var required: String = str(obstacle.get("required_type",""))
        if int(s.delivered) >= int(obstacle.opens_after) and (required == "" or int(s.get("departures_by_type",{}).get(required,0)) > 0):
            obstacle.opened = true
            opened.append(int(obstacle.id))
    return opened

static func remaining_by_type(s: Dictionary) -> Dictionary:
    var remaining: Dictionary = {}
    for cargo in s.feed_left+s.feed_right+s.belt:
        if cargo != null: remaining[cargo.type] = int(remaining.get(cargo.type,0))+1
    return remaining

static func preview_target(s: Dictionary, id: int) -> int:
    var truck: Dictionary = _truck(s,id)
    if truck.is_empty(): return 0
    if not bool(s.get("campaign",false)): return int(truck.capacity)
    var amount: int = int(remaining_by_type(s).get(truck.type,0))
    for other in s.trucks:
        if int(other.id) != id and str(other.status) in ["driving","loading","departing"] and str(other.type) == str(truck.type):
            amount -= maxi(0,int(other.target_load)-int(other.loaded))
    return clampi(amount,0,int(truck.capacity))

static func rotate_truck(s: Dictionary, id: int) -> Dictionary:
    var truck: Dictionary = _truck(s,id)
    if truck.is_empty(): return {"ok":false,"reason":"invalid"}
    if str(truck.status) != "yard": return {"ok":false,"reason":"already_dispatched"}
    truck.dir = (int(truck.dir)+2)%4
    s.moves = int(s.moves)+1
    return {"ok":true,"reason":"","dir":int(truck.dir)}

static func belt_count(s: Dictionary) -> int:
    var count := 0
    for cargo in s.belt:
        if cargo != null: count += 1
    return count

static func is_won(s: Dictionary) -> bool:
    if bool(s.get("campaign",false)):
        return int(s.cargo_delivered) == int(s.cargo_total) and s.feed_left.is_empty() and s.feed_right.is_empty() and belt_count(s) == 0
    if int(s.delivered) != int(s.total):
        return false
    for truck in s.trucks:
        if str(truck.status) != "done" or int(truck.loaded) != int(truck.capacity):
            return false
    return s.feed_left.is_empty() and s.feed_right.is_empty() and s.belt.all(func(cargo): return cargo == null)

static func is_stuck(s: Dictionary) -> bool:
    if bool(s.get("campaign",false)): return not loss_reason(s).is_empty()
    # Report only a certain deadlock. A driving/departing truck can still change
    # the state, and any matching item anywhere on the ring will reach its gate.
    if -1 in s.bays or s.belt.any(func(cargo): return cargo == null):
        return false
    var occupied_bays := 0
    for id in s.bays:
        if int(id) == -2:
            continue
        occupied_bays += 1
        var truck: Dictionary = _truck(s,int(id))
        if truck.is_empty() or str(truck.status) != "loading":
            return false
        for cargo in s.belt:
            if str(cargo.type) == str(truck.type):
                return false
    return occupied_bays > 0


# Only definite automatic deadlocks are losses. A driving/ready departure,
# a matching positive reservation, or room for another normal move is never
# labelled lost merely because its current animation or queue is unfinished.
static func loss_reason(s: Dictionary) -> String:
    if is_won(s): return ""
    if not bool(s.get("campaign",false)): return "belt_blocked" if is_stuck(s) else ""
    for truck in s.trucks:
        if str(truck.status) in ["driving","departing"]: return ""
    if -1 in s.bays: return "blocked_exits" if _proven_exit_loss(s) else ""
    if belt_count(s) < int(s.belt_limit) and (not s.feed_left.is_empty() or not s.feed_right.is_empty()): return ""
    for id in s.bays:
        if int(id) < 0: continue
        var truck: Dictionary = _truck(s,int(id))
        if int(truck.target_load) <= int(truck.loaded): continue
        for cargo in s.belt:
            if cargo != null and str(cargo.type) == str(truck.type): return ""
    return "bays_blocked"

static func _proven_exit_loss(s: Dictionary) -> bool:
    # A rescue rotation is an explicit external intervention. Ordinary play
    # has no move when every yard exit is blocked, no movable can change it,
    # and exhaustive finite automatic circulation cannot complete a job.
    for truck in s.trucks:
        if can_dispatch(s,int(truck.id)): return false
    for obstacle in s.get("obstacles",[]):
        if bool(obstacle.get("movable",false)):
            var alternate: Dictionary = s.duplicate(true)
            if move_obstacle(alternate,int(obstacle.id)).ok: return false
    var automatic: Dictionary = s.duplicate(true)
    for _tick in range(BELT_SIZE*(int(s.cargo_total)+2)):
        if not _automatic_tick(automatic).is_empty(): return false
    return true

static func step_ready(s: Dictionary, step: Dictionary) -> bool:
    if str(step.get("action","")) == "wait":
        for id in step.get("trucks",[]):
            if str(_truck(s,int(id)).get("status","")) != "done": return false
        return true
    if str(step.get("action","")) == "dispatch": return can_dispatch(s,int(step.get("id",-1)))
    if str(step.get("action","")) == "move_obstacle": return true
    return false

static func _automatic_tick(s: Dictionary) -> Array[int]:
    for truck in s.trucks:
        if str(truck.status) == "driving": arrive(s,int(truck.id))
    var events: Dictionary = tick(s)
    var done: Array[int] = []
    for id in events.departures:
        release_bay(s,int(id))
        done.append(int(id))
    return done

static func simulate(initial: Dictionary, steps: Array = [], max_ticks: int = 4000) -> Dictionary:
    var state: Dictionary = initial.duplicate(true)
    var script: Array = steps if not steps.is_empty() else state.get("solution_steps",[])
    var ticks := 0
    for step in script:
        if is_won(state): break
        var action: String = str(step.get("action",""))
        if action == "dispatch":
            var result: Dictionary = dispatch(state,int(step.id))
            if not result.ok: return {"ok":false,"state":state,"ticks":ticks,"reason":result.reason}
            arrive(state,int(step.id))
        elif action == "wait":
            var no_progress := 0
            while not step_ready(state,step) and ticks < max_ticks and no_progress < BELT_SIZE*(int(state.cargo_total)+2):
                var before: int = int(state.delivered)
                _automatic_tick(state)
                ticks += 1
                no_progress = 0 if int(state.delivered) > before else no_progress+1
            if not step_ready(state,step): return {"ok":false,"state":state,"ticks":ticks,"reason":"wait_blocked"}
        elif action == "move_obstacle":
            if not move_obstacle(state,int(step.id)).ok: return {"ok":false,"state":state,"ticks":ticks,"reason":"obstacle"}
        else: return {"ok":false,"state":state,"ticks":ticks,"reason":"invalid_step"}
    return {"ok":is_won(state),"state":state,"ticks":ticks,"reason":"" if is_won(state) else "incomplete"}

static func _search_key(s: Dictionary) -> String:
    var key: Array = [s.bays,s.get("cargo_delivered",0),s.feed_left.size(),s.feed_right.size()]
    for truck in s.trucks: key.append([truck.status,truck.get("target_load",-1),truck.loaded])
    for cargo in s.belt: key.append(-1 if cargo == null else int(cargo.id))
    return var_to_str(key)

static func solve(initial: Dictionary, max_nodes: int = 2000) -> Array:
    var context := {"nodes":0,"budget":max_nodes,"seen":{}}
    return _solve_branch(initial.duplicate(true),context)

static func _solve_branch(s: Dictionary, context: Dictionary) -> Array:
    if is_won(s): return [{"action":"wait","trucks":[]}]
    context.nodes = int(context.nodes)+1
    if int(context.nodes) > int(context.budget): return []
    var key: String = _search_key(s)
    if context.seen.has(key): return []
    context.seen[key] = true
    var candidates: Array = s.get("required_route",s.solution)
    for id in candidates:
        if not can_dispatch(s,int(id)) or preview_target(s,int(id)) <= 0: continue
        var child: Dictionary = s.duplicate(true)
        dispatch(child,int(id))
        arrive(child,int(id))
        var suffix: Array = _solve_branch(child,context)
        if not suffix.is_empty(): return [{"action":"dispatch","id":int(id)}]+suffix
    var waiting: Dictionary = s.duplicate(true)
    var finished: Array[int] = []
    for _tick in range(BELT_SIZE*(int(s.cargo_total)+2)):
        finished = _automatic_tick(waiting)
        if not finished.is_empty(): break
    if not finished.is_empty():
        var suffix: Array = _solve_branch(waiting,context)
        if not suffix.is_empty(): return [{"action":"wait","trucks":finished}]+suffix
    return []
