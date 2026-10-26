extends SceneTree
## Native OpenGL/Compatibility regression proof (does not launch the game):
## /Applications/Godot.app/Contents/MacOS/Godot --path truck-depot --script res://tests/test_badge_render.gd
## Add --log-file /absolute/path.log to retain the engine log. Requires a GPU;
## --headless exits with code2 rather than claiming a render validation pass.
## Outputs: qa/readability/glyph-rotation-camera-{0,90}.png.
## Rows: kyl,frys,schakt,adr,timmer,bransle. Columns: normal Mesh0/45/90deg,
## followed by MultiMesh0/45/90deg. The physical background keeps rotating;
## only the ink must remain upright. Compare the center disk and review sheets.
## The rotated plate corners can reach the fixture's square crop at45deg;
## actual truck/cargo envelope and final fleet thumbnails are tested separately.
## Archived successful baseline Models SHA256:
## 0698c5f7e9aec88f48bedcfd03a208477ad2d8812786970025136b8d55284fd4
const Models=preload("res://models.gd")
const KINDS=["kyl","frys","schakt","adr","timmer","bransle"]
const ANGLES=[0.0,PI*.25,PI*.5]
var failed=false
func _initialize():call_deferred("run")
func render_frame():
    for i in range(2):await process_frame
    RenderingServer.force_draw(false)
func central_error(a:Image,b:Image)->float:
    var error:float=0
    var count:int=0
    for y in range(30,114):
        for x in range(30,114):
            if Vector2(x-71.5,y-71.5).length()>40:continue
            var ca=a.get_pixel(x,y)
            var cb=b.get_pixel(x,y)
            error+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
            count+=3
    return error/maxi(1,count)
func run():
    if DisplayServer.get_name()=="headless":
        push_error("Badge render proof requires a native GPU renderer")
        quit(2)
        return
    var output="res://qa/readability"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    print("GLYPH_MODELS_SHA256 ",FileAccess.get_sha256("res://models.gd"))
    root.size=Vector2i(320,320)
    var vp=SubViewport.new()
    vp.size=Vector2i(144,144)
    vp.own_world_3d=true
    vp.transparent_bg=true
    vp.msaa_3d=Viewport.MSAA_4X
    vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    root.add_child(vp)
    var stage=Node3D.new()
    vp.add_child(stage)
    var env=WorldEnvironment.new()
    env.environment=Environment.new()
    env.environment.background_mode=Environment.BG_COLOR
    env.environment.background_color=Color(0,0,0,0)
    stage.add_child(env)
    var camera=Camera3D.new()
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.size=1.2
    camera.current=true
    stage.add_child(camera)
    for camera_yaw in [0.0,PI*.5]:
        camera.look_at_from_position(Vector3(0,4,0),Vector3.ZERO,Basis(Vector3.UP,camera_yaw)*Vector3.FORWARD)
        var contact=Image.create(864,864,false,Image.FORMAT_RGBA8)
        contact.fill(Color("18314a"))
        for row in range(KINDS.size()):
            var reference:Image
            for mode in range(2):
                for column in range(ANGLES.size()):
                    var label=Models.badge(KINDS[row],1.0)
                    var node:Node3D
                    if mode==0:
                        label.rotation.y=ANGLES[column]
                        stage.add_child(label)
                        node=label
                    else:
                        var face:MeshInstance3D=label.get_child(0)
                        var multi=MultiMesh.new()
                        multi.transform_format=MultiMesh.TRANSFORM_3D
                        multi.mesh=face.mesh
                        multi.instance_count=1
                        multi.set_instance_transform(0,Transform3D(Basis(Vector3.UP,ANGLES[column]),Vector3.ZERO))
                        var instance=MultiMeshInstance3D.new()
                        instance.multimesh=multi
                        instance.material_override=face.material_override
                        stage.add_child(instance)
                        label.free()
                        node=instance
                    await render_frame()
                    var img=vp.get_texture().get_image()
                    if mode==0 and column==0:reference=img
                    var error=central_error(reference,img)
                    print("GLYPH_ROTATION ",KINDS[row]," camera=",camera_yaw," MM=",mode," body=",ANGLES[column]," center_MAE=",error)
                    if error>.008:
                        failed=true
                        push_error("Glyph changed orientation on rotation")
                    contact.blend_rect(img,Rect2i(0,0,144,144),Vector2i((mode*3+column)*144,row*144))
                    node.free()
        var path=output.path_join("glyph-rotation-camera-%d.png"%roundi(rad_to_deg(camera_yaw)))
        if contact.save_png(ProjectSettings.globalize_path(path))!=OK:
            failed=true
            push_error("Could not save native rotation contact sheet")
    vp.free()
    print("GLYPH_ROTATION_NATIVE_OK" if not failed else "GLYPH_ROTATION_NATIVE_FAILED")
    quit(1 if failed else 0)
