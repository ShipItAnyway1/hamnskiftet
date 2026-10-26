extends SceneTree
## Headless regression for real main pointer routing, without scene/audio/saves.
## Godot --headless --path truck-depot --script res://tests/test_web_input.gd
class PointerGame:
    extends "res://main.gd"
    var picks: Array[Vector2] = []
    var zoom_steps: Array[float] = []
    func _ready() -> void: pass
    func _process(_delta: float) -> void: pass
    func _pick(point: Vector2) -> void: picks.append(point)
    func _change_zoom(amount: float) -> void: zoom_steps.append(amount)

var failures: Array[String] = []
func check(ok: bool,message: String) -> void:
    if not ok:
        failures.append(message)
        push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var game := PointerGame.new()
    # Directly invoke the actual inherited handler; adding a partial main node
    # to the tree would register unrelated engine shortcuts and notifications.
    var touch := InputEventScreenTouch.new()
    touch.position = Vector2(231,549)
    touch.pressed = true
    game._unhandled_input(touch)
    var emulated := InputEventMouseButton.new()
    emulated.device = InputEvent.DEVICE_ID_EMULATION
    emulated.button_index = MOUSE_BUTTON_LEFT
    emulated.position = touch.position
    emulated.pressed = true
    game._unhandled_input(emulated)
    check(game.picks == [touch.position],"One physical touch and its emulated mouse copy produce exactly one world action")
    var mouse := InputEventMouseButton.new()
    mouse.button_index = MOUSE_BUTTON_LEFT
    mouse.position = Vector2(511,675)
    mouse.pressed = true
    game._unhandled_input(mouse)
    check(game.picks == [touch.position,mouse.position],"Physical desktop mouse still reaches the same logical viewport coordinates")
    var emulated_touch := InputEventScreenTouch.new()
    emulated_touch.device = InputEvent.DEVICE_ID_EMULATION
    emulated_touch.position = mouse.position
    emulated_touch.pressed = true
    game._unhandled_input(emulated_touch)
    check(game.picks.size() == 2,"Optional mouse-to-touch emulation cannot double desktop actions either")
    mouse.pressed = false
    game._unhandled_input(mouse)
    touch.pressed = false
    game._unhandled_input(touch)
    check(game.picks.size() == 2,"Pointer release never dispatches another action")
    for wheel in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
        mouse.button_index = wheel
        mouse.pressed = true
        game._unhandled_input(mouse)
    check(game.zoom_steps == [.10,-.10] and game.picks.size() == 2,"Desktop wheel zoom remains available without dispatching a truck")
    game.free()
    print("WEB_INPUT_TESTS_OK: original touch/mouse only, no duplicate emulation, unchanged viewport coordinates, release ignored and wheel zoom" if failures.is_empty() else "WEB_INPUT_TESTS_FAILED")
    quit(0 if failures.is_empty() else 1)
