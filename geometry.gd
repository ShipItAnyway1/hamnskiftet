extends RefCounted

static var materials: Dictionary = {}

static func material(hex: String, roughness := 0.84) -> StandardMaterial3D:
    if materials.has(hex):
        return materials[hex]
    var m := StandardMaterial3D.new()
    m.albedo_color = Color(hex).srgb_to_linear().lerp(Color(hex),.20)
    m.roughness = roughness
    m.metallic_specular = .15
    materials[hex] = m
    return m

static func mesh(parent: Node3D, shape: Mesh, pos: Vector3, hex: String) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = shape
    instance.material_override = material(hex)
    instance.position = pos
    parent.add_child(instance)
    return instance

static func box(parent: Node3D, pos: Vector3, size: Vector3, hex: String) -> MeshInstance3D:
    var shape := BoxMesh.new()
    shape.size = size
    return mesh(parent, shape, pos, hex)

static func sphere(parent: Node3D, pos: Vector3, radius: float, hex: String) -> MeshInstance3D:
    var shape := SphereMesh.new()
    shape.radius = radius
    shape.height = radius * 2
    shape.radial_segments = 12
    shape.rings = 6
    return mesh(parent, shape, pos, hex)

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, hex: String, top := -1.0) -> MeshInstance3D:
    var shape := CylinderMesh.new()
    shape.bottom_radius = radius
    shape.top_radius = radius if top < 0 else top
    shape.height = height
    shape.radial_segments = 16
    return mesh(parent, shape, pos, hex)

static func rounded(parent: Node3D, pos: Vector3, size: Vector3, radius: float, hex: String) -> MeshInstance3D:
    var points: Array[Vector3] = []
    var r := minf(radius, minf(size.x, size.z) * 0.49)
    var centers := [Vector2(size.x/2-r,size.z/2-r), Vector2(size.x/2-r,-size.z/2+r), Vector2(-size.x/2+r,-size.z/2+r), Vector2(-size.x/2+r,size.z/2-r)]
    for corner in range(4):
        for step in range(7):
            var angle := (float(corner)*PI/2) + float(step)/6*PI/2
            points.append(Vector3(centers[corner].x+sin(angle)*r,0,centers[corner].y+cos(angle)*r))
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var h := size.y / 2
    for i in range(points.size()):
        var a := points[i]
        var b := points[(i+1)%points.size()]
        for v in [Vector3(0,h,0), b+Vector3(0,h,0), a+Vector3(0,h,0)]:
            st.set_normal(Vector3.UP)
            st.add_vertex(v)
        for v in [Vector3(0,-h,0), a-Vector3(0,h,0), b-Vector3(0,h,0)]:
            st.set_normal(Vector3.DOWN)
            st.add_vertex(v)
        var normal := Vector3((a.x+b.x)*0.5,0,(a.z+b.z)*0.5).normalized()
        # Side normals follow the outline tangent, keeping long edges flat.
        normal = Vector3(a.z-b.z,0,b.x-a.x).normalized()
        for v in [a-Vector3(0,h,0), a+Vector3(0,h,0), b+Vector3(0,h,0), a-Vector3(0,h,0), b+Vector3(0,h,0), b-Vector3(0,h,0)]:
            st.set_normal(normal)
            st.add_vertex(v)
    var shape := st.commit()
    var instance := mesh(parent, shape, pos, hex)
    # Generated meshes deliberately use both sides; direction is geometric, not winding-dependent.
    var m := material(hex).duplicate() as StandardMaterial3D
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    instance.material_override = m
    return instance

static func arrow(parent: Node3D, pos: Vector3, hex: String) -> MeshInstance3D:
    var outline := PackedVector2Array([Vector2(-.07,-.34), Vector2(.07,-.34), Vector2(.07,.06), Vector2(.22,.06), Vector2(0,.35), Vector2(-.22,.06), Vector2(-.07,.06)])
    var indices := Geometry2D.triangulate_polygon(outline)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index in indices:
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(outline[index].x,0,outline[index].y))
    var item := mesh(parent, st.commit(), pos, hex)
    var m := material(hex).duplicate() as StandardMaterial3D
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    item.material_override = m
    return item
