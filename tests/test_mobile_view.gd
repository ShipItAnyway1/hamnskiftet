extends SceneTree

const View = preload("res://readability_view.gd")
const Fixture = preload("res://tests/test_v7_view_ui.gd").Fixture
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
    var game := Fixture.new()
    root.add_child(game)
    game.camera = Camera3D.new()
    game.add_child(game.camera)
    var view = View.new()
    game.add_child(view)
    view.setup(game)
    view.configure({"campaign":true,"config":{"spawn_bounds":Rect2i(5,5,8,10),"types":["kyl","frys"]}})
    for dimensions in [Vector2(900,1600),Vector2(900,1948),Vector2(900,2100),Vector2(1200,1600),Vector2(1948,900),Vector2(900,900)]:
        view.reflow(dimensions)
        var canvas := Rect2(Vector2.ZERO,dimensions)
        for region in [view.dock_rect,view.yard_rect,view.road_rect]:
            check(canvas.encloses(region) and region.has_area(),"Every real camera region fits "+str(dimensions))
        check(not view.dock_rect.intersects(view.yard_rect),"Loading and yard do not overlap")
        check(not view.yard_rect.intersects(view.road_rect),"Road strip does not cover the yard")
        check(view.dock_texture.get_rect() == view.dock_rect and view.yard_texture.get_rect() == view.yard_rect,"Draw and hit-test regions use the same rects")
        var target := Vector3(-1.8,.8,8.0)
        var point: Vector2 = view.project(target)
        var ray: Dictionary = view.screen_ray(point)
        check(not ray.is_empty() and ray.camera == view.yard_camera,"Projected vehicle remains in actual yard hit region")
        if not ray.is_empty():
            var origin: Vector3 = ray.camera.project_ray_origin(ray.point)
            var normal: Vector3 = ray.camera.project_ray_normal(ray.point)
            check((target-origin).cross(normal).length() < .001,"Resize retains exact projection/ray roundtrip")
        view.set_zoom(1.5)
        var zoomed_size: float = view.yard_camera.size
        var previous: Vector3 = view.yard_camera.position
        view.pan(Vector2(42,23))
        check(view.yard_camera.position != previous,"Touch pan moves zoomed real camera")
        check(is_equal_approx(view.yard_camera.size,zoomed_size),"Pan does not change zoom")
        view.set_zoom(1)
        check(view._pan_offset == Vector2.ZERO,"Zooming out resets pan and preserves all vehicle access")
    view.reflow(Vector2(1948,900))
    view.set_zoom(1.9)
    view.pan(Vector2(100000,100000))
    view.reflow(Vector2(900,1948))
    var allowance: Vector2 = Vector2(view._yard_base_size*view.yard_rect.size.x/view.yard_rect.size.y,view._yard_base_size)*(1.0-1.0/1.9)*.52
    check(absf(view._pan_offset.x) <= allowance.x+.001 and absf(view._pan_offset.y) <= allowance.y+.001,"Rotation reclamps zoomed pan to the new camera framing")
    view.set_zoom(1.1)
    var zoom_allowance: Vector2 = Vector2(view._yard_base_size*view.yard_rect.size.x/view.yard_rect.size.y,view._yard_base_size)*(1.0-1.0/1.1)*.52
    check(absf(view._pan_offset.x) <= zoom_allowance.x+.001 and absf(view._pan_offset.y) <= zoom_allowance.y+.001,"Partial pinch out reclamps pan even before reaching minimum zoom")
    game.paused = true
    for viewport in [view.dock_viewport,view.yard_viewport,view.road_viewport]:
        viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    view.reflow(Vector2(1948,900))
    for viewport in [view.dock_viewport,view.yard_viewport,view.road_viewport]:
        check(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,"Resizing a paused view redraws its newly allocated texture once")
    game.queue_free()
    await process_frame
    await process_frame
    print("MOBILE_VIEW_TESTS_OK: %d checks, responsive camera bounds, exact picking after resize, zoom/pan and reset" % checks if failures.is_empty() else "MOBILE_VIEW_TESTS_FAILED")
    quit(0 if failures.is_empty() else 1)
