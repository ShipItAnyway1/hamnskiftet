extends SceneTree
## Actual main input routing inside a SceneTree; no game/audio/profile boot.
class DummyView:
    extends CanvasLayer
    var yard_rect := Rect2(0,300,900,900)
    var pans: Array[Vector2] = []
    func pan(relative: Vector2) -> void: pans.append(relative)
    func is_overview() -> bool: return false

class PointerGame:
    extends "res://main.gd"
    var picks: Array[Vector2] = []
    var zoom_steps: Array[float] = []
    func _ready() -> void: pass
    func _process(_delta: float) -> void: pass
    func _pick(point: Vector2) -> void: picks.append(point)
    func _change_zoom(amount: float) -> void:
        zoom_steps.append(amount)
        zoom = clampf(zoom+amount,1.0,1.9)

var failures: Array[String] = []
var checks := 0
func check(ok: bool,message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)
func _initialize() -> void: call_deferred("run")
func touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = position
    event.pressed = pressed
    return event
func drag(index: int, position: Vector2) -> InputEventScreenDrag:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = position
    return event
func mouse(position: Vector2, button: int, pressed: bool, emulated := false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.position = position
    event.button_index = button
    event.pressed = pressed
    if emulated: event.device = InputEvent.DEVICE_ID_EMULATION
    return event

func run() -> void:
    var game := PointerGame.new()
    root.add_child(game) # Real get_viewport/set_input_as_handled path is required.
    var view := DummyView.new()
    game.add_child(view)
    game.readable_view = view
    game.qa = true
    var point := Vector2(231,549)
    game._unhandled_input(touch(0,point,true))
    check(game.picks.is_empty() and game.gestures.tracks(0),"Integrated yard touchStart never dispatches")
    game._input(touch(0,point,false))
    check(game.picks == [point] and not game.gestures.tracks(0),"Tracked release through main._input dispatches exactly one logical point")
    game._unhandled_input(mouse(point,MOUSE_BUTTON_LEFT,true,true))
    game._unhandled_input(mouse(point,MOUSE_BUTTON_LEFT,false,true))
    var emulated_touch := touch(0,point,true)
    emulated_touch.device = InputEvent.DEVICE_ID_EMULATION
    game._unhandled_input(emulated_touch)
    check(game.picks.size() == 1 and not game.gestures.tracks(0),"Emulated mouse/touch copies cannot duplicate a real tap")
    game._input(touch(0,point,false))
    game._unhandled_input(touch(0,point,false))
    check(game.picks.size() == 1,"Repeated release cannot duplicate a finished touch")

    game.zoom = 1.0
    game._unhandled_input(touch(2,Vector2(200,600),true))
    game._unhandled_input(touch(3,Vector2(400,600),true))
    game._input(drag(3,Vector2(440,600)))
    check(game.zoom_steps.size() == 1 and is_equal_approx(game.zoom_steps[0],.2),"Real main gesture route applies pinch zoom delta")
    game._input(touch(3,Vector2(440,600),false))
    game._input(touch(2,Vector2(200,600),false))
    check(game.picks.size() == 1 and view.pans.is_empty(),"Two-finger drag and both releases never dispatch or invent pan")

    game.zoom = 1.5
    game._unhandled_input(touch(4,Vector2(300,650),true))
    game._input(drag(4,Vector2(320,655)))
    game._input(drag(4,Vector2(328,659)))
    game._input(touch(4,Vector2(328,659),false))
    check(view.pans == [Vector2(20,5),Vector2(8,4)] and game.picks.size() == 1,"Zoomed one-finger drag reaches readable_view.pan and never dispatches")
    game.zoom = 1.0
    game._unhandled_input(touch(4,Vector2(300,650),true))
    game._input(drag(4,Vector2(320,655)))
    game._input(touch(4,Vector2(320,655),false))
    check(view.pans.size() == 2 and game.picks.size() == 1,"Unzoomed drag neither pans nor dispatches")

    game._unhandled_input(touch(5,point,true))
    game._input(touch(6,Vector2(100,100),true)) # Consumed by GUI after _input.
    check(not game.gestures.tracks(5),"A new GUI/outside press cancels the pending yard tap")
    game._input(touch(5,point,false))
    game._unhandled_input(touch(5,point,false))
    check(game.picks.size() == 1,"Releasing canceled yard touch cannot select a truck")
    game._unhandled_input(touch(7,point,true))
    game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(not game.gestures.tracks(7),"Actual main focus-out notification clears gestures")
    game._input(touch(7,point,false))
    game._unhandled_input(touch(7,point,false))
    check(game.picks.size() == 1,"Focus return/release cannot dispatch a stale tap")

    var desktop := Vector2(511,675)
    game._unhandled_input(mouse(desktop,MOUSE_BUTTON_LEFT,true))
    game._unhandled_input(mouse(desktop,MOUSE_BUTTON_LEFT,false))
    check(game.picks == [point,desktop],"Physical desktop mouse retains exact viewport coordinates and single press action")
    game.zoom_steps.clear()
    for wheel in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
        game._unhandled_input(mouse(desktop,wheel,true))
    check(game.zoom_steps == [.10,-.10] and game.picks.size() == 2,"Desktop wheel zoom still works without dispatch")
    game.free()
    print("WEB_INPUT_TESTS_OK: %d checks; actual SceneTree main route, release-only tap, emulation, pinch/pan, GUI/focus cancellation, desktop click and wheel" % checks if failures.is_empty() else "WEB_INPUT_TESTS_FAILED")
    quit(0 if failures.is_empty() else 1)
