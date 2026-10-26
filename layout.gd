extends RefCounted

# Shared world coordinates. All roads, trucks and route tests use this contract.
const CELL := .9
const WIDTH := 18
const HEIGHT := 20
const COUNTS := [64,88]
const YARD_ORIGIN := Vector2(-7.65,.7)
const YARD_BOUNDS := Rect2(-8.1,.25,16.2,18.0)
const LANE_X := 10.0
const LANE_WIDTH := 1.5
const APRON_Z := -2.8
const BOTTOM_Z := 20.7
const DOCK_Z := -6.3
const BAY_X := [-3.0,0.0,3.0,-6.0,6.0]
const BAY_GATES := [6,4,3,7,2]
const DOCK_PRICES := [0,0,0,650,1400]
const BELT_CENTER_Z := -11.0
const BELT_STRAIGHT_HALF := 5.7
const BELT_RADIUS_Z := 2.3
const BELT_RADIUS_X := BELT_STRAIGHT_HALF+BELT_RADIUS_Z
const BELT_LENGTH := 4.0*BELT_STRAIGHT_HALF+TAU*BELT_RADIUS_Z
const BELT_SLOTS := 18
const BELT_TOP := 1.0
const BELT_HEIGHT := BELT_TOP
const CARGO_HEIGHT := BELT_TOP+.08
const QUAY_BOUNDS := Rect2(-11.8,-17.5,23.6,39.8)
const BRIDGE_BOUNDS := Rect2(-1.7,20.5,3.4,10.0)
const COLORS := {"kyl":"25cc78", "frys":"2698ff", "schakt":"ffd43b", "adr":"ff7b25", "timmer":"a36bfa", "bransle":"f2387c"}
const NAMES := {"kyl":"Kyl", "frys":"Frys", "schakt":"Schakt", "adr":"Farligt gods", "timmer":"Timmer", "bransle":"Bränsle"}

static func yard_position(truck: Dictionary) -> Vector3:
    var horizontal: bool = int(truck.dir)%2 == 1
    return Vector3(YARD_ORIGIN.x+(float(truck.x)+(float(truck.len)-1)*.5 if horizontal else float(truck.x))*CELL,0,
        YARD_ORIGIN.y+(float(truck.y) if horizontal else float(truck.y)+(float(truck.len)-1)*.5)*CELL)

static func belt_position(slot: float, height: float = BELT_HEIGHT) -> Vector3:
    # A real constant-speed racetrack: straight runs and semicircular drums.
    # Slot zero/nine remain the right/left inlets used by the puzzle rules.
    var distance := fposmod(slot/float(BELT_SLOTS)*BELT_LENGTH,BELT_LENGTH)
    var quarter := PI*.5*BELT_RADIUS_Z
    var straight := BELT_STRAIGHT_HALF*2.0
    var x: float
    var z: float
    if distance < quarter:
        var angle := distance/BELT_RADIUS_Z
        x = BELT_STRAIGHT_HALF+BELT_RADIUS_Z*cos(angle)
        z = BELT_RADIUS_Z*sin(angle)
    elif distance < quarter+straight:
        x = BELT_STRAIGHT_HALF-(distance-quarter)
        z = BELT_RADIUS_Z
    elif distance < quarter+straight+2.0*quarter:
        var angle := PI*.5+(distance-quarter-straight)/BELT_RADIUS_Z
        x = -BELT_STRAIGHT_HALF+BELT_RADIUS_Z*cos(angle)
        z = BELT_RADIUS_Z*sin(angle)
    elif distance < quarter+straight*2.0+2.0*quarter:
        x = -BELT_STRAIGHT_HALF+(distance-quarter-straight-2.0*quarter)
        z = -BELT_RADIUS_Z
    else:
        var angle := PI*1.5+(distance-quarter-straight*2.0-2.0*quarter)/BELT_RADIUS_Z
        x = BELT_STRAIGHT_HALF+BELT_RADIUS_Z*cos(angle)
        z = BELT_RADIUS_Z*sin(angle)
    return Vector3(x,height,BELT_CENTER_Z+z)

static func belt_tangent(slot: float) -> Vector3:
    return (belt_position(slot+.001)-belt_position(slot-.001)).normalized()

static func belt_yaw(slot: float) -> float:
    var tangent := belt_tangent(slot)
    return atan2(tangent.x,tangent.z)
