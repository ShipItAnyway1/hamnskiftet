extends SceneTree
## Headless lifecycle/pose checks. No main controller, UI, money or rule edits.
const Rescue=preload("res://rescue_effect.gd")
const Models=preload("res://models.gd")
var errors:Array[String]=[]
var completed_runs:Dictionary={}
func _initialize():call_deferred("run")
func check(ok:bool,message:String)->void:
    if not ok:
        errors.append(message)
        push_error(message)
func start_rescue(fx:Node3D,parent:Node3D,truck:Node3D,guard:Callable,pause:Callable,key:String)->void:
    await fx.play(parent,truck,PI,guard,pause)
    completed_runs[key]=true
func make_truck(parent:Node3D)->Node3D:
    var truck=Node3D.new()
    truck.position=Vector3(1,0,2)
    var model=Models.truck("frys",2.56,0,6)
    truck.add_child(model)
    truck.set_meta("model",model)
    parent.add_child(truck)
    return truck
func wait_done(key:String)->void:
    var began=Time.get_ticks_msec()
    while not completed_runs.has(key) and Time.get_ticks_msec()-began<2500:
        await process_frame
    check(completed_runs.has(key),"Rescue coroutine returns on "+key)
func run()->void:
    var yard=Node3D.new()
    root.add_child(yard)
    var effects=Node3D.new()
    yard.add_child(effects)
    var truck=make_truck(yard)
    var start=truck.transform
    var flags={"valid":true,"paused":false}
    var guard=func()->bool:return bool(flags.valid)
    var pause=func()->bool:return bool(flags.paused)
    var fx=Rescue.new()
    fx.duration_seconds=.50
    start_rescue(fx,effects,truck,guard,pause,"success")
    while fx.progress<.35:
        await process_frame
    flags.paused=true
    var held=truck.transform
    var rotor=fx._rotor.rotation.y
    var held_progress=fx.progress
    await create_timer(.06).timeout
    check(truck.transform.is_equal_approx(held) and is_equal_approx(fx.progress,held_progress),"Pause freezes truck and rescue clock")
    check(is_equal_approx(fx._rotor.rotation.y,rotor),"Pause freezes the rotor")
    flags.paused=false
    var saw_turn=false
    while not completed_runs.has("success"):
        if is_instance_valid(fx) and fx.phase=="turn":
            saw_turn=true
            check(truck.position.y>=2.34,"Truck only rotates after clearing neighboring roofs")
        check(Vector2(truck.position.x,truck.position.z).is_equal_approx(Vector2(start.origin.x,start.origin.z)),"Rescue keeps the same ground footprint")
        await process_frame
    check(saw_turn,"Rescue includes a real elevated turning phase")
    check(truck.position.is_equal_approx(start.origin) and absf(angle_difference(truck.rotation.y,PI))<.0001,"Success sets the truck down at exactly its starting point facing180 degrees")
    check(effects.get_child_count()==0,"Success removes every helicopter/cable/gripper visual")
    await process_frame
    var abort_fx=Rescue.new()
    abort_fx.duration_seconds=.40
    start_rescue(abort_fx,effects,truck,guard,pause,"generation_abort")
    while abort_fx.progress<.40:
        await process_frame
    flags.valid=false
    var abort_pose=truck.transform
    await wait_done("generation_abort")
    check(truck.transform.is_equal_approx(abort_pose),"Invalid generation receives no later pose writes")
    check(effects.get_child_count()==0,"Generation abort removes all rescue visuals")
    flags.valid=true
    truck.transform=start
    var reset_fx=Rescue.new()
    reset_fx.duration_seconds=.35
    start_rescue(reset_fx,effects,truck,guard,pause,"effects_reset")
    await process_frame
    effects.free()
    await wait_done("effects_reset")
    check(is_instance_valid(truck),"Resetting effects does not delete the rescued truck")
    var empty=Node3D.new()
    yard.add_child(empty)
    var freed_fx=Rescue.new()
    freed_fx.duration_seconds=.35
    start_rescue(freed_fx,empty,truck,guard,pause,"truck_freed")
    await process_frame
    truck.free()
    await wait_done("truck_freed")
    check(empty.get_child_count()==0,"Deleted truck cancels and cleans its helicopter")
    await process_frame
    await process_frame
    for child in root.get_children():
        check(child.name!="HelicopterRescueController","All rescue controller nodes retire after their coroutine returns")
    yard.free()
    if errors.is_empty():print("RESCUE_FX_TESTS_OK: same-point180 turn, clearance, pause, generation abort, effects reset, freed truck and zero ghost nodes")
    quit(0 if errors.is_empty() else 1)
