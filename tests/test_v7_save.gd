extends SceneTree
const P = preload("res://progression.gd")
const R = preload("res://puzzle.gd")
const Save = preload("res://campaign_save.gd")
const PATH := "res://qa/_ci/v7-state.cfg"
var failures: Array[String] = []
var saves := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
    _partial_and_rescue()
    _counter_and_corruption()
    _empty_reservation()
    if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
    if failures.is_empty(): print("V7_SAVE_TESTS_OK:%d real ConfigFile roundtrips; partialtarget/actualvalue,driving/loading/done,emptyreservations,180rotation,rescuecounter,bomprogress,fixedinventory,forgeryrejectionandV5fallback" % saves)
    else: print("V7_SAVE_TESTS_FAILED ",failures.size())
    quit(0 if failures.is_empty() else 1)

func _roundtrip(state: Dictionary, ranks: Dictionary, context: String) -> Dictionary:
    var canonical: Dictionary = Save.validate(state,ranks,int(state.stage)-1)
    check(not canonical.is_empty(),"Valid "+context+" validates before serialization")
    var file := ConfigFile.new()
    file.set_value("campaign","state",state)
    file.set_value("campaign","ranks",ranks)
    file.set_value("progress","coins",432)
    file.set_value("progress","rewards",{"campaign:v1:1:9":true})
    check(file.save(PATH) == OK,"Disposable ConfigFile writes "+context)
    var reloaded := ConfigFile.new()
    check(reloaded.load(PATH) == OK,"Disposable ConfigFile reads "+context)
    var restored: Dictionary = Save.validate(reloaded.get_value("campaign","state"),reloaded.get_value("campaign","ranks"),int(state.stage)-1)
    check(not restored.is_empty(),"Actual disk roundtrip validates "+context)
    check(reloaded.get_value("progress","coins") == 432 and reloaded.get_value("progress","rewards") == {"campaign:v1:1:9":true},"Snapshot validation never resets permanent wallet/claim ledger")
    if not restored.is_empty(): check(restored == canonical,"Canonical roundtrip retains every rule field for "+context)
    saves += 1
    return restored

func _partial_and_rescue() -> void:
    var ranks: Dictionary = P.defaults()
    ranks.fleet_schakt = 3
    ranks.fleet_kyl = 3
    ranks.loader = 1
    ranks.warehouse = 1
    var state: Dictionary = R.create_level(0,P.stage_config(1,ranks))
    _roundtrip(state,ranks,"fresh fixed manifest")
    var rotate_id: int = int(state.solution[-1])
    check(R.rotate_truck(state,rotate_id).ok,"Yard truck can be physically reversed")
    state.rescue_used = 1 # Controller-owned monotonic accounting, not a fee.
    var after_rotate: Dictionary = _roundtrip(state,ranks,"rotated rescue state")
    check(after_rotate.rescue_used == 1 and after_rotate.trucks[rotate_id].dir == state.trucks[rotate_id].dir,"Rescue use and reversed heading survive serialization")
    R.rotate_truck(state,rotate_id)
    var id: int = int(state.solution[0])
    check(R.dispatch(state,id).ok and state.trucks[id].target_load == 4 and state.trucks[id].capacity == 6,"One upgraded truck reserves four units without inventing two more")
    _roundtrip(state,ranks,"driving partial-target job")
    R.arrive(state,id)
    var guard := 0
    while state.trucks[id].loaded == 0 and guard < 80:
        R.tick(state)
        guard += 1
    check(state.trucks[id].loaded > 0 and state.trucks[id].loaded < state.trucks[id].target_load,"Fixture exercises genuinely partial loaded cargo")
    var partial: Dictionary = _roundtrip(state,ranks,"loading partial-target job")
    check(partial.trucks[id].delivery_value == state.trucks[id].delivery_value and partial.cargo_total == 8,"Loaded money and fixed pool survive loading resume")
    while str(state.trucks[id].status) == "loading" and guard < 160:
        R.tick(state)
        guard += 1
    check(state.trucks[id].status == "departing" and state.trucks[id].loaded == 4,"Full target can be a partial physical truck")
    _roundtrip(state,ranks,"departing four-of-six truck")
    R.release_bay(state,id)
    var done: Dictionary = _roundtrip(state,ranks,"completed partial delivery")
    check(done.cargo_delivered == 4 and done.delivered == 1 and done.rescue_used == 1,"Saved counters distinguish actual freight, trips and rescue usage")
    var corrupt: Dictionary = state.duplicate(true)
    corrupt.trucks[id].target_load = 6
    check(Save.validate(corrupt,ranks,0).is_empty(),"Forged larger shipment target rejected")
    corrupt = state.duplicate(true)
    corrupt.trucks[0].dir = (int(corrupt.trucks[0].dir)+1)%4
    check(Save.validate(corrupt,ranks,0).is_empty(),"90degree rotation cannot change immutable footprint")
    corrupt = state.duplicate(true)
    corrupt.rescue_used = -1
    check(Save.validate(corrupt,ranks,0).is_empty(),"Negative rescue accounting rejected")
    corrupt = state.duplicate(true)
    corrupt.config.version = 5
    check(Save.validate(corrupt,ranks,0).is_empty(),"Incompatible V5 active board safely requests a fresh V7 attempt")
    var migrated: Dictionary = P.sanitize({"fleet":7,"parking":2,"loader":3})
    for key in P.FLEET_KEYS: check(migrated[key] == 3,"Pre-resource fleet upgrades remain owned across V7")
    check(migrated.parking == 2 and migrated.loader == 3,"General ownership remains intact under new prices")

func _counter_and_corruption() -> void:
    var ranks: Dictionary = P.defaults()
    var state: Dictionary = R.create_level(4,P.stage_config(5,ranks))
    _roundtrip(state,ranks,"boss boom initially closed")
    for step in state.solution_steps:
        if state.delivered >= 2: break
        if step.action == "dispatch":
            check(R.dispatch(state,int(step.id)).ok,"Counter fixture follows proven spatial chain")
            R.arrive(state,int(step.id))
        else:
            var guard := 0
            while not R.step_ready(state,step) and guard < 300:
                var event: Dictionary = R.tick(state)
                for id in event.departures: R.release_bay(state,int(id))
                guard += 1
    check(state.delivered == 2 and state.obstacles[0].opened,"Only two actual positive departures open boss boom")
    var restored: Dictionary = _roundtrip(state,ranks,"automatically opened boss boom")
    check(restored.obstacles[0].opened and restored.departures_by_type == state.departures_by_type,"Boom progress and resource-specific departures persist")
    var bad: Dictionary = state.duplicate(true)
    bad.obstacles[0].opened = false
    check(Save.validate(bad,ranks,4).is_empty(),"Counter/boom visual state cannot disagree")
    bad = state.duplicate(true)
    bad.cargo_delivered += 1
    check(Save.validate(bad,ranks,4).is_empty(),"Forged shipped quantity rejected")
    bad = state.duplicate(true)
    bad.manifest_delivered["bransle"] = 1
    check(Save.validate(bad,ranks,4).is_empty(),"Unshipped fuel cannot fake resource progress")
    bad = state.duplicate(true)
    var cargo = bad.feed_left[0] if not bad.feed_left.is_empty() else bad.feed_right[0]
    cargo.quality += 1
    check(Save.validate(bad,ranks,4).is_empty(),"Remaining physical inventory quality cannot be forged")
    bad = state.duplicate(true)
    if not bad.feed_left.is_empty(): bad.feed_right.append(bad.feed_left[0].duplicate(true))
    check(Save.validate(bad,ranks,4).is_empty(),"Duplicate cargo identity rejected")

func _empty_reservation() -> void:
    var ranks: Dictionary = P.defaults()
    var state: Dictionary = R.create_level(2,P.stage_config(3,ranks))
    for _tick in range(8): R.tick(state)
    for id in [0,1]:
        check(R.dispatch(state,id).ok,"Explicit legal surplus choice can be persisted")
        R.arrive(state,id)
    check(state.trucks[0].target_load == 2 and state.trucks[1].target_load == 0,"Only actual free freight is reserved")
    var restored: Dictionary = _roundtrip(state,ranks,"positive plus zero-target occupied docks")
    check(restored.bays == state.bays and restored.trucks[1].status == "loading" and restored.trucks[1].target_load == 0,"Empty trap retains its occupied physical bay")
    var bad: Dictionary = state.duplicate(true)
    bad.trucks[1].target_load = 2
    bad.trucks[1].expected_value = 6.0
    check(Save.validate(bad,ranks,2).is_empty(),"Two jobs cannot reserve the same two Kyl items after reload")
    bad = state.duplicate(true)
    bad.trucks[1].status = "done"
    check(Save.validate(bad,ranks,2).is_empty(),"Empty surplus truck cannot be forged into an earned departure")
