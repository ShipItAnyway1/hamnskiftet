extends SceneTree
## Native visual proof: Godot --path truck-depot --script res://tests/test_rescue_render.gd
## Saves actual airborne/lowering/landed frames in qa/v7/rescue-proof/.
## Requires GPU; the gameplay controller, rules and saved progress are untouched.
const Rescue=preload("res://rescue_effect.gd")
const Models=preload("res://models.gd")
var done=false
func _initialize():call_deferred("run")
func animate(fx:Node3D,parent:Node3D,truck:Node3D)->void:
    await fx.play(parent,truck,PI,func()->bool:return true)
    done=true
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Rescue visual proof requires a native renderer")
        quit(2)
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa/v7/rescue-proof"))
    root.size=Vector2i(900,900)
    var scene=Node3D.new()
    root.add_child(scene)
    var env=WorldEnvironment.new()
    env.environment=Environment.new()
    env.environment.background_mode=Environment.BG_COLOR
    env.environment.background_color=Color("14304a")
    env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color=Color("cce6f2")
    env.environment.ambient_light_energy=.5
    scene.add_child(env)
    var sun=DirectionalLight3D.new()
    sun.rotation_degrees=Vector3(-55,-30,0)
    sun.light_energy=.85
    sun.shadow_enabled=true
    scene.add_child(sun)
    var plane=MeshInstance3D.new()
    var p=PlaneMesh.new()
    p.size=Vector2(16,16)
    plane.mesh=p
    var mat=StandardMaterial3D.new()
    mat.albedo_color=Color("244d6e")
    plane.material_override=mat
    scene.add_child(plane)
    var truck=Node3D.new()
    var model=Models.truck("frys",2.56,0,6)
    truck.add_child(model)
    truck.set_meta("model",model)
    scene.add_child(truck)
    for x in [-1.0,1.0]:
        var other=Models.truck("timmer" if x<0 else "bransle",2.56,0,6)
        other.position.x=x
        scene.add_child(other)
    var effects=Node3D.new()
    scene.add_child(effects)
    var camera=Camera3D.new()
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.size=11
    camera.position=Vector3(10,10,-14)
    scene.add_child(camera)
    camera.look_at(Vector3(0,2.9,0))
    camera.current=true
    var fx=Rescue.new()
    animate(fx,effects,truck)
    var took_lift=false
    var took_lower=false
    while not done:
        await process_frame
        if not is_instance_valid(fx):continue
        if fx.progress>.56 and not took_lift:
            RenderingServer.force_draw(false)
            root.get_texture().get_image().save_png("res://qa/v7/rescue-proof/airborne.png")
            took_lift=true
        if fx.progress>.77 and not took_lower:
            RenderingServer.force_draw(false)
            root.get_texture().get_image().save_png("res://qa/v7/rescue-proof/lowering.png")
            took_lower=true
    for i in range(2):await process_frame
    RenderingServer.force_draw(false)
    root.get_texture().get_image().save_png("res://qa/v7/rescue-proof/landed.png")
    assert(effects.get_child_count()==0)
    assert(truck.position.is_equal_approx(Vector3.ZERO))
    assert(absf(angle_difference(truck.rotation.y,PI))<.0001)
    scene.free()
    print("RESCUE_NATIVE_V7_OK")
    quit()
