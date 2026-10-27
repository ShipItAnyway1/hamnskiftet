extends SceneTree

const Gestures = preload("res://mobile_gestures.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures.append(message)
        push_error(message)

func touch(index: int, position: Vector2, pressed: bool, canceled := false) -> InputEventScreenTouch:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = position
    event.pressed = pressed
    event.canceled = canceled
    return event

func drag(index: int, position: Vector2) -> InputEventScreenDrag:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = position
    # Position differences are authoritative under viewport stretch. A drag's
    # physical screen-relative field need not match logical viewport units.
    event.relative = Vector2(999,999)
    return event

func _initialize() -> void:
    var g := Gestures.new()
    check(not g.process_touch(touch(0,Vector2(100,100),true),1.0,false).handled and not g.tracks(0),"GUI/outside starts are ignored")
    check(not g.process_drag(drag(0,Vector2(101,100))).handled,"Untracked GUI finger never pans")
    var start: Dictionary = g.process_touch(touch(3,Vector2(100,100),true))
    check(start.handled and start.tap == null and g.tracks(3),"Touch start tracks without dispatch")
    check(not g.process_touch(touch(3,Vector2(100,100),true)).handled,"Repeated start cannot reset an existing gesture")
    var jitter: Dictionary = g.process_drag(drag(3,Vector2(106,104)),1.6)
    check(jitter.tap == null and jitter.pan == Vector2.ZERO,"Small jitter neither pans nor dispatches")
    var released: Dictionary = g.process_touch(touch(3,Vector2(106,104),false),1.6)
    check(released.tap == Vector2(106,104) and not g.tracks(3),"Single tap emits exactly once on release")
    check(g.process_touch(touch(3,Vector2(106,104),false)).tap == null,"Duplicate release cannot dispatch twice")

    g.process_touch(touch(1,Vector2(100,100),true))
    var movement: Dictionary = g.process_drag(drag(1,Vector2(112,100)),1.0)
    check(movement.pan == Vector2.ZERO,"Unzoomed drag cannot pan")
    g.process_drag(drag(1,Vector2(100,100)),1.0)
    check(g.process_touch(touch(1,Vector2(100,100),false)).tap == null,"Crossing twelve-unit threshold permanently cancels tap even after returning")
    g.process_touch(touch(1,Vector2(100,100),true))
    movement = g.process_drag(drag(1,Vector2(113,105)),1.5)
    check(movement.pan == Vector2(13,5),"Zoomed drag starts after threshold using logical displacement")
    movement = g.process_drag(drag(1,Vector2(118,107)),1.5)
    check(movement.pan == Vector2(5,2),"Continued pan uses incremental logical movement")
    check(g.process_touch(touch(1,Vector2(118,107),false)).tap == null,"Pan release cannot pick a truck")

    g.process_touch(touch(2,Vector2(100,100),true))
    g.process_touch(touch(9,Vector2(200,100),true))
    var pinch: Dictionary = g.process_drag(drag(9,Vector2(220,100)),1.5)
    check(is_equal_approx(pinch.zoom_delta,.3) and pinch.pan == Vector2.ZERO,"Pinch expands multiplicatively without panning")
    pinch = g.process_drag(drag(2,Vector2(110,100)),1.8)
    check(is_equal_approx(pinch.zoom_delta,-.15),"Other finger updates the same incremental pinch span")
    check(g.process_touch(touch(9,Vector2(220,100),false),1.65).tap == null,"First lifted pinch finger never taps")
    check(g.process_drag(drag(2,Vector2(115,101)),1.65).pan == Vector2(5,1),"Remaining pinch finger can pan continuously")
    check(g.process_touch(touch(2,Vector2(115,101),false),1.65).tap == null,"Last lifted pinch finger also never taps")

    for id in [0,1,2]: g.process_touch(touch(id,Vector2(200+id*20,200),true))
    check(g.process_drag(drag(1,Vector2(230,200)),1.6).zoom_delta == 0.0,"Three fingers do not invent a two-finger ratio")
    for id in [0,1,2]: check(g.process_touch(touch(id,Vector2(200+id*20,200),false)).tap == null,"Three-finger participants cannot dispatch")
    g.process_touch(touch(0,Vector2(100,100),true))
    check(g.process_touch(touch(0,Vector2(100,100),false,true)).tap == null and not g.tracks(0),"OS-canceled touch clears without dispatch")
    g.process_touch(touch(0,Vector2(100,100),true))
    check(g.process_touch(touch(0,Vector2(100,100),true,true)).tap == null and not g.tracks(0),"Cancellation takes precedence over platform pressed state")
    g.process_touch(touch(0,Vector2(100,100),true))
    check(g.process_touch(touch(0,Vector2(700,100),false),1.5,false).tap == null and not g.tracks(0),"Tracked release outside yard cleans up without picking")
    g.process_touch(touch(7,Vector2(100,100),true))
    g.cancel()
    check(not g.tracks(7) and g.process_touch(touch(7,Vector2(100,100),false)).tap == null,"Modal/focus/reset cancellation prevents stale dispatch")
    g.process_touch(touch(0,Vector2.ZERO,true))
    g.process_touch(touch(1,Vector2.ZERO,true))
    check(g.process_drag(drag(1,Vector2(1,0)),1.0).zoom_delta == 0.0,"Coincident fingers cannot divide by zero")
    g.cancel()
    if failures.is_empty(): print("MOBILE_GESTURES_TESTS_OK: %d checks; release-only tap, jitter/drag threshold, one-finger zoomed pan, pinch, GUI isolation, cancellation and logical coordinates" % checks)
    quit(0 if failures.is_empty() else 1)
