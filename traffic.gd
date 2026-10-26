extends RefCounted

# Continuous physical separation for campaign traffic. Selection and dock
# reservations are immediate; only vehicles sharing the apron take turns.
# Include the southern approach, not merely the painted cross-lane. A long
# truck waiting at the old -1.35 edge could stop its nose inside the current
# owner's rounded turn, producing a physical wait cycle. The new +1.8 edge
# stops that truck before the sweep and remains outside the first yard row.
const APRON := Rect2(-11.2,-4.65,22.4,6.45)
var apron_owner := -1
var apron_queue: Array[int] = []
var merge_zones: Dictionary = {}

func clear() -> void:
    apron_owner = -1
    apron_queue.clear()
    merge_zones.clear()

func register_merge(id: int, direction: int, source: Vector3) -> void:
    var area := Rect2()
    if direction == 3:
        area = Rect2(-11.8,source.z-3.6,3.55,7.2)
    elif direction == 1:
        area = Rect2(8.25,source.z-3.6,3.55,7.2)
    elif direction == 2:
        area = Rect2(source.x-3.6,18.4,7.2,4.0)
    if area.has_area():
        merge_zones[id] = {"area":area,"active":false,"entered":false,"done":false}

func finish_route(id: int) -> void:
    merge_zones.erase(id)
    release(id)

func allow_merges(id: int, next_shape: PackedVector2Array, others: Array[PackedVector2Array]) -> bool:
    var next_bounds := bounds(next_shape)
    # A branch may begin only when its entire turn and rear clearance are
    # empty. Lane traffic then yields before the turn, avoiding two vehicles
    # stopping nose-to-side halfway through the same merge.
    for owner in merge_zones:
        var zone: Dictionary = merge_zones[owner]
        if int(owner) != id and zone.active and next_bounds.intersects(zone.area):
            return false
    if not merge_zones.has(id):
        return true
    var own: Dictionary = merge_zones[id]
    if own.done:
        return true
    if next_bounds.intersects(own.area):
        if not own.active:
            for shape in others:
                if bounds(shape).intersects(own.area):
                    return false
            for owner in merge_zones:
                if int(owner) != id and merge_zones[owner].active and own.area.intersects(merge_zones[owner].area):
                    return false
            own.active = true
        own.entered = true
    elif own.active and own.entered:
        own.active = false
        own.done = true
    return true

func release(id: int) -> void:
    if apron_owner == id:
        apron_owner = -1
    apron_queue.erase(id)

static func corners(position: Vector3, yaw: float, length: float, width := .79) -> PackedVector2Array:
    var points := PackedVector2Array()
    for local in [Vector3(-width*.5,0,-length*.5),Vector3(width*.5,0,-length*.5),Vector3(width*.5,0,length*.5),Vector3(-width*.5,0,length*.5)]:
        var point: Vector3 = position+Basis(Vector3.UP,yaw)*local
        points.append(Vector2(point.x,point.z))
    return points

static func bounds(points: PackedVector2Array) -> Rect2:
    var area := Rect2(points[0],Vector2.ZERO)
    for point in points:
        area = area.expand(point)
    return area

static func overlaps(a: PackedVector2Array, b: PackedVector2Array, tolerance := .004) -> bool:
    if not bounds(a).intersects(bounds(b)):
        return false
    for polygon in [a,b]:
        for i in range(2):
            var edge: Vector2 = polygon[(i+1)%4]-polygon[i]
            var axis := Vector2(-edge.y,edge.x).normalized()
            var a_min := INF
            var a_max := -INF
            var b_min := INF
            var b_max := -INF
            for point in a:
                a_min = minf(a_min,point.dot(axis))
                a_max = maxf(a_max,point.dot(axis))
            for point in b:
                b_min = minf(b_min,point.dot(axis))
                b_max = maxf(b_max,point.dot(axis))
            if a_max <= b_min+tolerance or b_max <= a_min+tolerance:
                return false
    return true

func claim_apron(id: int, next_shape: PackedVector2Array, current_shape: PackedVector2Array) -> bool:
    var needs := bounds(next_shape).intersects(APRON)
    if not needs:
        if not bounds(current_shape).intersects(APRON):
            release(id)
        return true
    if apron_owner == id:
        return true
    if id not in apron_queue:
        apron_queue.append(id)
    if apron_owner == -1 and not apron_queue.is_empty() and apron_queue[0] == id:
        apron_owner = id
        apron_queue.pop_front()
        return true
    return false
