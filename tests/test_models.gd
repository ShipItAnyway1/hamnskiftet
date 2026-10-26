extends SceneTree

const Models = preload("res://models.gd")
const Layout = preload("res://layout.gd")
const Renderer = preload("res://rendering_helper.gd")
const World = preload("res://world.gd")
const Progression = preload("res://progression.gd")
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func check(condition: bool, text: String) -> void:
    if not condition:
        failures.append(text)
        push_error(text)

func _run() -> void:
    var fingerprints: Dictionary = {}
    for kind in Layout.COLORS:
        var key: String = str(kind)
        var texture: Texture2D = Models.icon(key)
        check(texture == Models.icon(key),"%s icon is cached" % key)
        check(texture.get_width() == 128 and texture.get_height() == 128,"%s icon has requested dimensions" % key)
        check(Models.icon(key,64).get_width() == 64,"%s icon supports another raster size" % key)
        var image := Image.new()
        check(image.load_svg_from_string(Models._icon_svg(key)) == OK,"%s SVG rasterizes" % key)
        check(image.get_pixel(0,0).a < .01,"%s icon has transparent corners" % key)
        var expected := Color(str(Layout.COLORS[key]))
        check(image.get_pixel(10,64).is_equal_approx(expected),"%s icon uses canonical category color" % key)
        fingerprints[hash(image.get_data())] = true
        var foreground_pixels: int = 0
        var dark_ink: bool = key in ["kyl","schakt","adr"]
        for y in range(128):
            for x in range(128):
                var pixel: Color = image.get_pixel(x,y)
                var dark: bool = pixel.r < .16 and pixel.g < .20 and pixel.b < .24
                var white: bool = pixel.r > .95 and pixel.g > .95 and pixel.b > .95
                if pixel.a > .95 and (dark if dark_ink else white):
                    foreground_pixels += 1
        check(foreground_pixels > 1000,"%s has a large contrasting pictogram" % key)
        var sample_badge: Node3D = Models.badge(key)
        var face: MeshInstance3D = sample_badge.get_child(0)
        check(texture.get_image().has_mipmaps() and badge_uses_filtered_reduction(face.material_override),"%s badge has filtered reduction levels for a moving angled surface" % key)
        sample_badge.free()
        var vehicle: Node3D = Models.truck(key,2.4,3)
        root.add_child(vehicle)
        check(vehicle.has_meta("type_badge"),"%s truck has a visible type badge" % key)
        check(vehicle.has_meta("loading_fx"),"%s truck exposes loading effect references" % key)
        check(vehicle.get_meta("wheels").size() == 6,"%s wheel animation contract" % key)
        var fx: Dictionary = vehicle.get_meta("loading_fx")
        check(is_instance_valid(fx.body) and is_instance_valid(fx.badge),"%s effect nodes survive geometry batching" % key)
        var lamps: Dictionary = vehicle.get_meta("vehicle_lights")
        Models.set_vehicle_lights(vehicle,true,true)
        check(bool(vehicle.get_meta("braking")) and bool(vehicle.get_meta("headlights_on")),"%s exposes independent driving/brake lamp state" % key)
        check(lamps.head.material_override.emission_enabled and lamps.brake.material_override.emission_enabled,"%s driving and braking illuminate the real lamp lenses" % key)
        Models.set_vehicle_lights(vehicle,false,false)
        check(not lamps.head.material_override.emission_enabled and not lamps.brake.material_override.emission_enabled,"%s lamp materials return to their unlit state" % key)
        if key in ["kyl","frys"]:
            check(vehicle.has_meta("reefer_door") and is_instance_valid(fx.door),"%s has a separate rear-door hinge" % key)
        var bounds: AABB = combined_bounds(vehicle)
        check(bounds.position.y >= -.001 and bounds.size.x <= .7501 and bounds.size.z <= 2.401 and bounds.end.y <= 1.17,"%s vehicle bounds and ground contact" % key)
        for length in [1.66,2.56]:
            var exact: Node3D = Models.truck(key,length)
            root.add_child(exact)
            var exact_bounds: AABB = combined_bounds(exact)
            check(exact_bounds.size.x <= .7501 and exact_bounds.size.z <= length+.0001,"%s respects exact %.2f-length occupancy" % [key,length])
            check(is_equal_approx(float(exact.get_meta("length")),length),"%s never expands a short vehicle length" % key)
            check(int(exact.get_meta("capacity")) == (3 if length < 2.0 else 6),"%s capacity metadata follows the physical length" % key)
            check(exact.has_meta("tier_mark"),"%s exposes the fleet tier marker" % key)
            check_direction_mark(exact,length,key)
            check_turn_signals(exact,exact_bounds,key)
            exact.queue_free()
        for capacity in [3,4,5,6]:
            var length: float = 1.66 if capacity < 5 else 2.56
            var exact: Node3D = Models.truck(key,length,0,capacity)
            check(int(exact.get_meta("capacity")) == capacity,"%s exposes requested %d-load capacity" % [key,capacity])
            var meter: Node3D = exact.get_meta("capacity_meter")
            var segments: MultiMesh = meter.get_meta("segments")
            check(segments.instance_count == capacity,"%s load meter has one physical segment per load" % key)
            Models.set_load_fraction(exact,1.0/float(capacity))
            check(int(meter.get_meta("filled")) == 1,"%s load meter shows exactly one landed load" % key)
            Models.set_load_fraction(exact,1.0)
            check(int(meter.get_meta("filled")) == capacity,"%s load meter shows a full truck" % key)
            Models.set_load_fraction(exact,0)
            check(int(meter.get_meta("filled")) == 0,"%s empty truck keeps its physical capacity indication" % key)
            var envelope: AABB = combined_bounds(exact)
            check(envelope.size.x <= .7501 and envelope.size.z <= length+.0001 and envelope.end.y <= 1.17,"%s load meter stays inside truck width, length and crane clearance" % key)
            exact.free()
        var units: Array = vehicle.get_meta("load_units")
        for amount in [0.0,.25,.5,.75,1.0]:
            Models.set_load_fraction(vehicle,amount)
            check(vehicle.get_meta("load_root").visible == (amount > 0),"%s load root visibility" % key)
            if key != "bransle":
                var wanted: int = mini(units.size(),int(ceil(amount*units.size()-.000001)))
                for index in range(units.size()):
                    check(units[index].visible == (index < wanted),"%s toggles whole logical load units" % key)
            else:
                check(is_equal_approx(vehicle.get_meta("load_gauge").scale.y,maxf(amount,.001)),"Fuel gauge fills from its fixed bottom" )
        var unit: Node3D = Models.cargo(key)
        root.add_child(unit)
        var cargo_bounds: AABB = combined_bounds(unit)
        check(cargo_bounds.size.x <= .521 and cargo_bounds.size.z <= .521 and cargo_bounds.end.y <= .651,"%s physical cargo plus badge fits contract" % key)
        check(unit.has_meta("type_badge") and solid_vertex_count(unit) >= 120,"%s keeps substantial physical cargo geometry alongside its symbol" % key)
        check(is_equal_approx(float(unit.get_meta("lift_height")),cargo_bounds.end.y),"%s reports actual unscaled lifting height" % key)
        var mark: Node3D = unit.get_meta("type_badge")
        var support_y: float = opaque_support_below(unit,mark.position)
        check(mark.position.y-support_y >= -.002 and mark.position.y-support_y < .009,"%s marking rests directly on real cargo rather than a pole" % key)
        var ordinary_meshes: int = count_meshes(unit)
        var original_lift: float = float(unit.get_meta("lift_height"))
        check(int(unit.get_meta("quality")) == 0 and not unit.has_meta("quality_mark"),"%s quality zero preserves ordinary physical cargo" % key)
        Models.set_cargo_quality(unit,1)
        check(unit.has_meta("quality_mark") and count_meshes(unit) == ordinary_meshes+1,"%s quality adds one batched physical gold label" % key)
        check(combined_bounds(unit).is_equal_approx(cargo_bounds),"%s gold label preserves cargo width, length and height" % key)
        check(is_equal_approx(float(unit.get_meta("lift_height")),original_lift),"%s gold label preserves lifting clearance" % key)
        var quality_mark: Node3D = unit.get_meta("quality_mark")
        Models.set_cargo_quality(unit,5)
        check(int(unit.get_meta("quality")) == 5 and unit.get_meta("quality_mark") == quality_mark,"%s quality rank updates reuse the same quiet physical label" % key)
        Models.set_cargo_quality(unit,-1)
        check(int(unit.get_meta("quality")) == 0 and not unit.has_meta("quality_mark") and count_meshes(unit) == ordinary_meshes,"%s removing quality restores the ordinary model" % key)
        var premium: Node3D = Models.cargo(key,1.0,3)
        check(int(premium.get_meta("quality")) == 3 and premium.has_meta("quality_mark"),"%s cargo constructor accepts an optional quality rank" % key)
        check(combined_bounds(premium).is_equal_approx(cargo_bounds),"%s constructor quality preserves the original cargo envelope" % key)
        premium.free()
        unit.queue_free()
        vehicle.queue_free()
    check(fingerprints.size() == 6,"All six pictograms are distinct")
    check_parked_batches()
    check_active_yard_surface()
    check_obstacle_models()
    await process_frame
    if failures.is_empty():
        print("TRUCK_MODELS_V5_OK: exact occupancy, cargo quality, capacity3/4/5/6 meters, driving/brake lenses, container/gate cell bounds, active surfaces and reversible parked batches")
    quit(0 if failures.is_empty() else 1)

func combined_bounds(node: Node3D) -> AABB:
    var boxes: Array[AABB] = []
    collect_bounds(node,Transform3D.IDENTITY,boxes)
    var result: AABB = boxes[0]
    for box in boxes:
        result = result.merge(box)
    return result

func collect_bounds(node: Node3D, accumulated: Transform3D, output: Array[AABB]) -> void:
    for child in node.get_children():
        if child is Node3D:
            var transform: Transform3D = accumulated*child.transform
            if child is MeshInstance3D:
                output.append(transform*child.get_aabb())
            collect_bounds(child,transform,output)

func count_meshes(node: Node) -> int:
    var count: int = 1 if node is MeshInstance3D else 0
    for child in node.get_children():
        count += count_meshes(child)
    return count

func solid_vertex_count(node: Node) -> int:
    var count: int = 0
    if node is MeshInstance3D:
        var material: Material = node.material_override
        if not is_badge_material(material):
            count += node.mesh.get_faces().size()
    for child in node.get_children():
        count += solid_vertex_count(child)
    return count

func is_badge_material(material: Material) -> bool:
    if material is StandardMaterial3D:
        return material.albedo_texture != null
    if material is ShaderMaterial:
        return material.get_shader_parameter("glyph_texture") is Texture2D and material.get_shader_parameter("plate_texture") is Texture2D
    return false

func badge_uses_filtered_reduction(material: Material) -> bool:
    if material is StandardMaterial3D:
        return material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    if material is ShaderMaterial and is_badge_material(material):
        var glyph: Texture2D = material.get_shader_parameter("glyph_texture")
        var plate: Texture2D = material.get_shader_parameter("plate_texture")
        return glyph.get_image().has_mipmaps() and plate.get_image().has_mipmaps() and material.shader.code.count("filter_linear_mipmap_anisotropic") == 2
    return false

func check_turn_signals(model: Node3D, original_bounds: AABB, kind: String) -> void:
    var lenses: Dictionary = model.get_meta("turn_signal_lenses")
    check(lenses.left.size() == 2 and lenses.right.size() == 2,"%s has real front/rear indicator lenses on both sides" % kind)
    for state in [{"side":-1,"on":true},{"side":1,"on":true},{"side":1,"on":false},{"side":0,"on":true}]:
        Models.set_turn_signal(model,int(state.side),bool(state.on))
        var indicator_state: Dictionary = model.get_meta("turn_signal")
        check(int(indicator_state.side) == int(state.side) and bool(indicator_state.on) == (bool(state.on) and int(state.side) != 0),"%s exposes the requested indicator side and flash phase" % kind)
        for key in ["left","right"]:
            var expected: bool = bool(indicator_state.on) and ((int(indicator_state.side) == -1 and key == "left") or (int(indicator_state.side) == 1 and key == "right"))
            for lens in lenses[key]:
                check(lens.material_override.emission_enabled == expected,"%s lights only the selected pair of indicators" % kind)
                check(lens.position.y+lens.scale.y*.5 < .60,"%s indicators stay below the cab and crane clearance" % kind)
        check(combined_bounds(model).is_equal_approx(original_bounds),"%s blinking never expands the vehicle AABB" % kind)
    Models.set_turn_signal(model,0,false)

func check_parked_batches() -> void:
    var yard := Node3D.new()
    yard.position = Vector3(4,0,7)
    root.add_child(yard)
    var vehicles: Array[Node3D] = []
    var visible_before: Dictionary = {}
    for index in range(8):
        var vehicle: Node3D = Models.truck("frys",2.56,index)
        vehicle.position.x = index
        yard.add_child(vehicle)
        Models.set_load_fraction(vehicle,0.0 if index == 0 else 1.0)
        vehicles.append(vehicle)
        var entries: Array[Dictionary] = []
        Models._collect_meshes(vehicle,Transform3D.IDENTITY,true,entries)
        for entry in entries:
            visible_before[entry.node.get_instance_id()] = entry.node.visible
    var batch := Renderer.build(yard,vehicles)
    check(int(batch.get_meta("model_count")) == 8,"Parked batching keeps all eight logical models")
    check(int(batch.get_meta("draw_group_count"))*2 < int(batch.get_meta("source_mesh_count")),"Equal truck geometry is shared and reduces parked draw groups")
    check(batch.contains(vehicles[0]) and batch.contains(vehicles[7]),"Parked batch tracks independent models")
    batch.detach(vehicles[0])
    check(not batch.contains(vehicles[0]) and batch.contains(vehicles[1]),"Detaching one animated truck leaves other parked trucks batched")
    batch.restore()
    check(int(batch.get_meta("model_count")) == 0,"Restore releases all parked model references")
    for vehicle in vehicles:
        var entries: Array[Dictionary] = []
        Models._collect_meshes(vehicle,Transform3D.IDENTITY,true,entries)
        for entry in entries:
            check(entry.node.visible == bool(visible_before[entry.node.get_instance_id()]),"Parked render restore preserves hidden load parts and visible body parts")
    yard.free()

func check_active_yard_surface() -> void:
    var world: Node3D = World.build()
    var entire := Rect2i(0,0,Layout.WIDTH,Layout.HEIGHT)
    check(world.get_meta("active_spawn_bounds") == entire,"Default depot surface covers the original full grid")
    for stage in range(1,11):
        var config: Dictionary = Progression.stage_config(stage)
        var cells: Rect2i = config.spawn_bounds
        World.set_spawn_bounds(world,cells)
        var expected := Rect2(Layout.YARD_BOUNDS.position+Vector2(cells.position)*Layout.CELL,Vector2(cells.size)*Layout.CELL)
        check(world.get_meta("active_yard_bounds").is_equal_approx(expected),"Stage %d active surface follows its authored spawn cells" % stage)
        var overlay: Node3D = world.get_node("ActiveDepotSurface")
        check(overlay.find_children("*","CollisionObject3D",true,false).is_empty(),"Active depot paint introduces no physical obstacles")
        for child in overlay.get_children():
            check(child is MultiMeshInstance3D,"Active surface stays in a small set of instanced paint batches")
        # Headless Godot's dummy renderer returns identity from MultiMesh
        # transform readback. Inspect the actual CPU instance data before upload.
        var builder := World.SiteBuilder.new()
        builder.root = Node3D.new()
        builder._active_yard(cells)
        for value in builder.batches.values():
            var batch: Dictionary = value
            for transform in batch.transforms:
                var bounds: AABB = transform*batch.mesh.get_aabb()
                check(bounds.end.y <= .055,"Active surface remains flush paint under the existing vehicles")
                var footprint := Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
                check(Layout.YARD_BOUNDS.grow(.061).encloses(footprint),"Active surface stays within the original depot boundary")
        builder.root.free()
        check(world.get_meta("parking_bounds") == Layout.YARD_BOUNDS,"Changing the active surface preserves all shared route bounds")
    World.set_spawn_bounds(world,Rect2i(-2,-3,3,4))
    check(world.get_meta("active_spawn_bounds") == Rect2i(0,0,1,1),"Active surface clamps to the existing grid")
    World.set_spawn_bounds(world,Rect2i())
    check(world.get_meta("active_spawn_bounds") == entire,"Invalid empty spawn bounds fall back to the full depot")
    world.free()

func check_obstacle_models() -> void:
    var yard := Node3D.new()
    root.add_child(yard)
    var fixtures: Array = [
        {"id":0,"kind":"container","x":2,"y":3,"w":2,"h":1,"movable":false},
        {"id":1,"kind":"gate","x":5,"y":6,"w":1,"h":1,"movable":true,"positions":[Vector2i(5,6),Vector2i(6,6)],"position_index":0},
    ]
    var obstacles: Dictionary = World.build_obstacles(yard,fixtures)
    check(obstacles.size() == 2,"World builds both container and movable gate from rule data")
    for data in fixtures:
        var model: Node3D = obstacles[data.id]
        var expected := Vector3(Layout.YARD_ORIGIN.x+(float(data.x)+float(data.w-1)*.5)*Layout.CELL,0,Layout.YARD_ORIGIN.y+(float(data.y)+float(data.h-1)*.5)*Layout.CELL)
        check(model.position.is_equal_approx(expected),"Obstacle model aligns exactly with its occupied cell rectangle")
        var body: StaticBody3D = model.get_meta("body")
        check(body.collision_layer == 4 and body.collision_mask == 0,"Obstacle hit body uses the dedicated raycast layer")
        check(body.get_meta("obstacle_id") == data.id and model.get_meta("obstacle_id") == data.id,"Obstacle ID survives visual and physics layers")
        var shape_node: CollisionShape3D = body.get_child(0)
        check(shape_node.shape.size.x <= float(data.w)*Layout.CELL and shape_node.shape.size.z <= float(data.h)*Layout.CELL,"Obstacle body never extends into neighboring road cells")
        var builder := World.SiteBuilder.new()
        builder.root = Node3D.new()
        var size := Vector2(float(data.w)*Layout.CELL-.10,float(data.h)*Layout.CELL-.10)
        builder._obstacle_shape(str(data.kind),size)
        for value in builder.batches.values():
            var batch: Dictionary = value
            for transform in batch.transforms:
                var bounds: AABB = transform*batch.mesh.get_aabb()
                check(bounds.position.x >= -float(data.w)*Layout.CELL*.5-.001 and bounds.end.x <= float(data.w)*Layout.CELL*.5+.001,"Obstacle visual remains inside its column footprint")
                check(bounds.position.z >= -float(data.h)*Layout.CELL*.5-.001 and bounds.end.z <= float(data.h)*Layout.CELL*.5+.001,"Obstacle visual remains inside its row footprint")
        builder.root.free()
    var gate: Node3D = obstacles[1]
    gate.position.x += Layout.CELL
    check(gate.get_meta("body").global_position.is_equal_approx(gate.global_position),"Moving a gate model also moves its raycast body")
    yard.free()

func opaque_support_below(model: Node3D, point: Vector3) -> float:
    var entries: Array[Dictionary] = []
    Models._collect_meshes(model,Transform3D.IDENTITY,true,entries)
    var highest: float = -1000.0
    for entry in entries:
        var mesh_node: MeshInstance3D = entry.node
        var material: Material = mesh_node.material_override
        if is_badge_material(material):
            continue
        var vertices: PackedVector3Array = mesh_node.mesh.get_faces()
        var transform: Transform3D = entry.transform
        for index in range(0,vertices.size(),3):
            var hit: Variant = Geometry3D.ray_intersects_triangle(point+Vector3.UP*.02,Vector3.DOWN,transform*vertices[index],transform*vertices[index+1],transform*vertices[index+2])
            if hit is Vector3:
                highest = maxf(highest,hit.y)
    return highest

func check_direction_mark(model: Node3D, length: float, kind: String) -> void:
    var cab: Node3D = model.get_meta("cab")
    var found: bool = false
    for child in cab.get_children():
        if not child is MeshInstance3D:
            continue
        var material: StandardMaterial3D = child.material_override
        if material == null or material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or material.get_meta("category_paint",false):
            continue
        found = true
        var box: AABB = child.get_aabb()
        var cab_length: float = minf(.74,length*.32)
        var front: float = -length*.5+.04
        check(box.size.x >= .429 and box.size.z >= .329,"%s direction arrow has a broad readable footprint" % kind)
        check(box.position.z >= front+.115-.001 and box.end.z <= front+cab_length+.001,"%s direction mark fits the short cab roof" % kind)
        check(box.position.x >= -.331 and box.end.x <= .331,"%s arrow stays within cab width" % kind)
        var faces: PackedVector3Array = child.mesh.get_faces()
        for point in faces:
            if is_equal_approx(point.z,box.position.z):
                check(absf(point.x) < .001,"%s arrow nose points toward -Z" % kind)
    check(found,"%s has an unshaded white direction mark" % kind)
