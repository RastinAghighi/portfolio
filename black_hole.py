"""
black_hole.py
Procedural Interstellar-style black hole for Blender 4.x (Cycles).
Renders ONE hero still so we can dial in the look before we animate.

Run headless on a GPU box:
    blender --background --python black_hole.py

Output: bh_render.png  (in the directory you launch blender from)
"""

import bpy
import os

# ======================================================================
# TWEAKABLES  --  this block is what we iterate on
# ======================================================================
# Scales are in units of the gravitational radius  r_g = GM/c^2 = 1.
# This pass has no ray-traced lensing, so the numbers are set to the
# *observed* proportions of a real black hole (EHT's M87*) and Gargantua:
#   apparent shadow ~ 2.6 Schwarzschild radii (~5 r_g), the disc inner edge
#   hugging just outside it, thin disc, brightest at the inner edge.
SHADOW_RADIUS   = 5.0      # black sphere = the apparent (lensed) shadow
DISC_INNER      = 5.6      # disc inner edge, just outside the shadow
DISC_OUTER      = 24.0     # bright disc fades out by here (~4.3x inner)
DISC_BRIGHTNESS = 4.0      # emission strength (colour gets tuned next step)
DOPPLER         = 0.65     # relativistic beaming: one side brighter

# Camera: close, near edge-on, and STATIC -- "start close, stay there"
CAM_LOCATION    = (0.0, -33.0, 6.0)   # ~10 deg above the disc plane
CAM_LENS_MM     = 50
SAMPLES         = 256
RES_X, RES_Y    = 1920, 1080
OUTPUT          = "bh_render.png"
USE_GPU         = True     # set False to force CPU
# ======================================================================


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_node_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return mat, nt.nodes, nt.links


# ----------------------------------------------------------------------
def setup_render():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 16
    scene.cycles.transmission_bounces = 16
    scene.cycles.transparent_max_bounces = 16

    if USE_GPU:
        try:
            prefs = bpy.context.preferences.addons['cycles'].preferences
            for backend in ('OPTIX', 'CUDA'):
                try:
                    prefs.compute_device_type = backend
                    break
                except TypeError:
                    continue
            prefs.get_devices()
            for d in prefs.devices:
                d.use = True
            scene.cycles.device = 'GPU'
            print("Cycles device: GPU (%s)" % prefs.compute_device_type)
        except Exception as e:
            scene.cycles.device = 'CPU'
            print("GPU setup failed (%s) -> falling back to CPU" % e)
    else:
        scene.cycles.device = 'CPU'

    scene.render.resolution_x = RES_X
    scene.render.resolution_y = RES_Y
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = os.path.abspath(OUTPUT)
    # filmic-style highlight rolloff so the bright disc doesn't clip harshly
    scene.view_settings.view_transform = 'AgX'


# ----------------------------------------------------------------------
def make_world_starfield():
    world = bpy.data.worlds.new("Space")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)

    out   = nt.nodes.new('ShaderNodeOutputWorld')
    bg    = nt.nodes.new('ShaderNodeBackground')
    texco = nt.nodes.new('ShaderNodeTexCoord')
    vor   = nt.nodes.new('ShaderNodeTexVoronoi')
    vor.inputs['Scale'].default_value = 120.0
    ramp  = nt.nodes.new('ShaderNodeValToRGB')
    # tight ramp -> tiny bright star points where voronoi distance is small
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    ramp.color_ramp.elements[1].position = 0.06
    ramp.color_ramp.elements[1].color = (0, 0, 0, 1)

    nt.links.new(texco.outputs['Generated'], vor.inputs['Vector'])
    nt.links.new(vor.outputs['Distance'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 1.0
    nt.links.new(bg.outputs['Background'], out.inputs['Surface'])


# ----------------------------------------------------------------------
def make_event_horizon():
    bpy.ops.mesh.primitive_uv_sphere_add(radius=SHADOW_RADIUS, location=(0, 0, 0),
                                         segments=96, ring_count=48)
    obj = bpy.context.active_object
    obj.name = "Shadow"
    bpy.ops.object.shade_smooth()
    mat, nodes, links = new_node_material("Shadow_Black")
    out  = nodes.new('ShaderNodeOutputMaterial')
    emit = nodes.new('ShaderNodeEmission')
    emit.inputs['Color'].default_value = (0, 0, 0, 1)
    emit.inputs['Strength'].default_value = 0.0
    links.new(emit.outputs['Emission'], out.inputs['Surface'])
    obj.data.materials.append(mat)


# ----------------------------------------------------------------------
def make_disc():
    bpy.ops.mesh.primitive_circle_add(vertices=256, radius=DISC_OUTER,
                                      fill_type='NGON', location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = "AccretionDisc"
    mat, nodes, links = new_node_material("Disc_Emission")

    out    = nodes.new('ShaderNodeOutputMaterial')
    mix    = nodes.new('ShaderNodeMixShader')
    emit   = nodes.new('ShaderNodeEmission')
    transp = nodes.new('ShaderNodeBsdfTransparent')

    texco = nodes.new('ShaderNodeTexCoord')
    rlen  = nodes.new('ShaderNodeVectorMath')
    rlen.operation = 'LENGTH'
    links.new(texco.outputs['Object'], rlen.inputs[0])
    # rlen.outputs['Value'] == radial distance r in the disc plane

    # --- temperature colour by radius ---
    tmap = nodes.new('ShaderNodeMapRange')
    tmap.inputs['From Min'].default_value = DISC_INNER
    tmap.inputs['From Max'].default_value = DISC_OUTER
    tmap.inputs['To Min'].default_value   = 0.0
    tmap.inputs['To Max'].default_value   = 1.0
    tmap.clamp = True
    links.new(rlen.outputs['Value'], tmap.inputs['Value'])

    temp = nodes.new('ShaderNodeValToRGB')
    temp.color_ramp.elements[0].position = 0.0
    temp.color_ramp.elements[0].color = (1.0, 0.98, 0.92, 1)   # hot near-white
    e_mid = temp.color_ramp.elements.new(0.35)
    e_mid.color = (1.0, 0.5, 0.12, 1)                          # orange
    temp.color_ramp.elements[2].position = 1.0
    temp.color_ramp.elements[2].color = (0.55, 0.09, 0.02, 1)  # deep red
    links.new(tmap.outputs['Result'], temp.inputs['Fac'])

    # --- turbulence ---
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 1.5
    noise.inputs['Detail'].default_value = 12.0
    links.new(texco.outputs['Object'], noise.inputs['Vector'])

    # --- inner & outer radial falloff -> band mask ---
    inner = nodes.new('ShaderNodeMapRange')
    inner.inputs['From Min'].default_value = DISC_INNER
    inner.inputs['From Max'].default_value = DISC_INNER + 0.25
    inner.inputs['To Min'].default_value   = 0.0
    inner.inputs['To Max'].default_value   = 1.0
    inner.interpolation_type = 'SMOOTHSTEP'
    inner.clamp = True
    links.new(rlen.outputs['Value'], inner.inputs['Value'])

    outer = nodes.new('ShaderNodeMapRange')
    outer.inputs['From Min'].default_value = DISC_OUTER * 0.5
    outer.inputs['From Max'].default_value = DISC_OUTER
    outer.inputs['To Min'].default_value   = 1.0
    outer.inputs['To Max'].default_value   = 0.0
    outer.interpolation_type = 'SMOOTHSTEP'
    outer.clamp = True
    links.new(rlen.outputs['Value'], outer.inputs['Value'])

    mask = nodes.new('ShaderNodeMath')
    mask.operation = 'MULTIPLY'
    links.new(inner.outputs['Result'], mask.inputs[0])
    links.new(outer.outputs['Result'], mask.inputs[1])

    # --- doppler beaming (one side brighter) ---
    sep  = nodes.new('ShaderNodeSeparateXYZ')
    links.new(texco.outputs['Object'], sep.inputs['Vector'])
    dopp = nodes.new('ShaderNodeMapRange')
    dopp.inputs['From Min'].default_value = -DISC_OUTER
    dopp.inputs['From Max'].default_value =  DISC_OUTER
    dopp.inputs['To Min'].default_value   = 1.0 - DOPPLER
    dopp.inputs['To Max'].default_value   = 1.0 + DOPPLER
    dopp.clamp = True
    links.new(sep.outputs['X'], dopp.inputs['Value'])

    # --- emission strength = brightness * mask * doppler * (0.4 + 0.6*noise) ---
    nfac = nodes.new('ShaderNodeMath')
    nfac.operation = 'MULTIPLY_ADD'
    nfac.inputs[1].default_value = 0.9
    nfac.inputs[2].default_value = 0.12
    links.new(noise.outputs['Fac'], nfac.inputs[0])

    s1 = nodes.new('ShaderNodeMath'); s1.operation = 'MULTIPLY'
    links.new(mask.outputs['Value'], s1.inputs[0])
    links.new(dopp.outputs['Result'], s1.inputs[1])

    s2 = nodes.new('ShaderNodeMath'); s2.operation = 'MULTIPLY'
    links.new(s1.outputs['Value'], s2.inputs[0])
    links.new(nfac.outputs['Value'], s2.inputs[1])

    s3 = nodes.new('ShaderNodeMath'); s3.operation = 'MULTIPLY'
    s3.inputs[1].default_value = DISC_BRIGHTNESS
    links.new(s2.outputs['Value'], s3.inputs[0])

    links.new(temp.outputs['Color'], emit.inputs['Color'])
    links.new(s3.outputs['Value'], emit.inputs['Strength'])

    # --- transparent (outside band) vs emission (inside band) ---
    links.new(mask.outputs['Value'], mix.inputs[0])    # Fac
    links.new(transp.outputs['BSDF'], mix.inputs[1])   # Fac=0 -> transparent
    links.new(emit.outputs['Emission'], mix.inputs[2]) # Fac=1 -> emission
    links.new(mix.outputs[0], out.inputs['Surface'])

    obj.data.materials.append(mat)


# ----------------------------------------------------------------------
def make_camera():
    bpy.ops.object.empty_add(location=(0, 0, 0))
    target = bpy.context.active_object
    target.name = "CamTarget"

    bpy.ops.object.camera_add(location=CAM_LOCATION)
    cam = bpy.context.active_object
    cam.name = "Camera"
    cam.data.lens = CAM_LENS_MM
    con = cam.constraints.new('TRACK_TO')
    con.target = target
    con.track_axis = 'TRACK_NEGATIVE_Z'
    con.up_axis = 'UP_Y'
    bpy.context.scene.camera = cam


# ----------------------------------------------------------------------
def setup_compositor_bloom():
    scene = bpy.context.scene
    scene.use_nodes = True
    nt = scene.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    rl    = nt.nodes.new('CompositorNodeRLayers')
    glare = nt.nodes.new('CompositorNodeGlare')
    glare.glare_type = 'FOG_GLOW'
    glare.quality = 'HIGH'
    glare.threshold = 1.6
    comp  = nt.nodes.new('CompositorNodeComposite')
    nt.links.new(rl.outputs['Image'], glare.inputs['Image'])
    nt.links.new(glare.outputs['Image'], comp.inputs['Image'])


# ----------------------------------------------------------------------
def main():
    reset_scene()
    setup_render()
    make_world_starfield()
    make_event_horizon()
    make_disc()
    make_camera()
    setup_compositor_bloom()
    print("Rendering ...")
    bpy.ops.render.render(write_still=True)
    print("Done -> %s" % os.path.abspath(OUTPUT))


main()
