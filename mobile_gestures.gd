extends RefCounted

## Pointer state only; the controller owns picking, camera changes and GUI.
## Positions and TAP_DISTANCE use root viewport logical units, never CSS/DPR.
## New touches may start only in the yard. Route tracked drags/releases even
## over GUI/outside the yard, then cancel() on modal, level or focus changes.
const TAP_DISTANCE := 12.0
var _fingers: Dictionary = {}

func tracks(index: int) -> bool:
    return _fingers.has(index)

func cancel() -> void:
    _fingers.clear()

func _result() -> Dictionary:
    return {"handled":false,"tap":null,"zoom_delta":0.0,"pan":Vector2.ZERO}

func process_touch(event: InputEventScreenTouch, zoom: float = 1.0, allow_start: bool = true) -> Dictionary:
    var result := _result()
    if event.canceled:
        result.handled = _fingers.has(event.index)
        _fingers.erase(event.index)
        return result
    if event.pressed:
        if not allow_start or _fingers.has(event.index):
            return result
        _fingers[event.index] = {"start":event.position,"position":event.position,"distance":0.0,"tap":true,"dragging":false}
        if _fingers.size() > 1:
            # No participant in a multi-finger gesture can later become a tap.
            for finger in _fingers.values():
                finger.tap = false
                finger.dragging = true
        result.handled = true
        return result
    if not _fingers.has(event.index):
        return result
    var finger: Dictionary = _fingers[event.index]
    var distance: float = maxf(float(finger.distance),event.position.distance_to(finger.start))
    if _fingers.size() == 1 and bool(finger.tap) and distance < TAP_DISTANCE:
        result.tap = event.position
    _fingers.erase(event.index)
    result.handled = true
    return result

func process_drag(event: InputEventScreenDrag, zoom: float = 1.0) -> Dictionary:
    var result := _result()
    if not _fingers.has(event.index):
        return result
    result.handled = true
    var finger: Dictionary = _fingers[event.index]
    var previous: Vector2 = finger.position
    if _fingers.size() == 2:
        var other_index: int = int(_fingers.keys()[0])
        if other_index == event.index:
            other_index = int(_fingers.keys()[1])
        var other: Vector2 = _fingers[other_index].position
        var old_distance: float = previous.distance_to(other)
        var new_distance: float = event.position.distance_to(other)
        # Coincident fingers must separate before a ratio can be measured.
        if old_distance > .001 and is_finite(zoom) and zoom > 0.0:
            result.zoom_delta = zoom*(new_distance/old_distance-1.0)
    finger.position = event.position
    finger.distance = maxf(float(finger.distance),event.position.distance_to(finger.start))
    if float(finger.distance) >= TAP_DISTANCE:
        finger.tap = false
    if _fingers.size() == 1 and is_finite(zoom) and zoom > 1.0:
        if bool(finger.dragging):
            result.pan = event.position-previous
        elif float(finger.distance) >= TAP_DISTANCE:
            finger.dragging = true
            result.pan = event.position-finger.start
    return result
