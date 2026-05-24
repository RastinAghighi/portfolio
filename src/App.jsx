import { useEffect, useRef } from 'react'
import * as THREE from 'three'
import vertexShader from './shaders/blackhole.vert.glsl'
import fragmentShader from './shaders/blackhole.frag.glsl'

function App() {
  const mountRef = useRef(null)

  useEffect(() => {
    const mount = mountRef.current
    if (!mount) return

    const width = mount.clientWidth
    const height = mount.clientHeight

    const scene = new THREE.Scene()

    const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1)

    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    renderer.setSize(width, height)
    renderer.setClearColor(0x000000, 1)
    mount.appendChild(renderer.domElement)

    const geometry = new THREE.PlaneGeometry(2, 2)
    const material = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        u_resolution: { value: new THREE.Vector2() },
        u_time: { value: 0 },
        u_camPos: { value: new THREE.Vector3(0, 5, 30) },
        u_camTarget: { value: new THREE.Vector3(0, 0, 0) },
      },
    })
    const quad = new THREE.Mesh(geometry, material)
    scene.add(quad)

    renderer.getDrawingBufferSize(material.uniforms.u_resolution.value)

    const ANIM_DURATION = 12.0
    const START_POS = new THREE.Vector3(0, 5, 30)
    const END_POS = new THREE.Vector3(0, 3, 10)
    let animStart = performance.now() / 1000

    let frameId = 0
    const tick = () => {
      const now = performance.now() / 1000
      const elapsed = now - animStart
      let p = Math.min(elapsed / ANIM_DURATION, 1.0)
      p = p * p * p * (p * (p * 6 - 15) + 10)
      material.uniforms.u_camPos.value.lerpVectors(START_POS, END_POS, p)
      material.uniforms.u_time.value = now
      renderer.render(scene, camera)
      frameId = requestAnimationFrame(tick)
    }
    frameId = requestAnimationFrame(tick)

    const handleResize = () => {
      const w = mount.clientWidth
      const h = mount.clientHeight
      renderer.setSize(w, h)
      renderer.getDrawingBufferSize(material.uniforms.u_resolution.value)
    }
    window.addEventListener('resize', handleResize)

    return () => {
      cancelAnimationFrame(frameId)
      window.removeEventListener('resize', handleResize)
      geometry.dispose()
      material.dispose()
      renderer.dispose()
      if (renderer.domElement.parentNode === mount) {
        mount.removeChild(renderer.domElement)
      }
    }
  }, [])

  return <div ref={mountRef} style={{ width: '100vw', height: '100vh' }} />
}

export default App
