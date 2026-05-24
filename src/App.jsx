import { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import vertexShader from './shaders/blackhole.vert.glsl'
import fragmentShader from './shaders/blackhole.frag.glsl'

function App() {
  const mountRef = useRef(null)
  const skipRef = useRef(false)
  const [introDone, setIntroDone] = useState(false)
  const [skipHovered, setSkipHovered] = useState(false)

  const handleSkip = () => {
    skipRef.current = true
  }

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

    const TOTAL_DURATION = 22.0
    const POS_INTRO_START = new THREE.Vector3(0, 5, 30)
    const POS_INTRO_END = new THREE.Vector3(0, 3, 10)
    const POS_DESCENT_END = new THREE.Vector3(0, 0.5, 5)
    let animStart = performance.now() / 1000
    let doneFired = false

    let frameId = 0
    const tick = () => {
      const now = performance.now() / 1000
      let elapsed = skipRef.current ? TOTAL_DURATION : (now - animStart)

      if (elapsed >= TOTAL_DURATION && !doneFired) {
        doneFired = true
        setIntroDone(true)
      }
      elapsed = Math.min(elapsed, TOTAL_DURATION)

      const camPos = material.uniforms.u_camPos.value
      if (elapsed < 12.0) {
        let p = elapsed / 12.0
        p = p * p * p * (p * (p * 6 - 15) + 10)
        camPos.lerpVectors(POS_INTRO_START, POS_INTRO_END, p)
      } else {
        let p = (elapsed - 12.0) / 10.0
        p = p * p * p * (p * (p * 6 - 15) + 10)
        camPos.lerpVectors(POS_INTRO_END, POS_DESCENT_END, p)
      }

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

  return (
    <>
      <div ref={mountRef} style={{ width: '100vw', height: '100vh' }} />
      {!introDone && (
        <button
          onClick={handleSkip}
          onMouseEnter={() => setSkipHovered(true)}
          onMouseLeave={() => setSkipHovered(false)}
          style={{
            position: 'fixed',
            bottom: 24,
            left: 24,
            zIndex: 10,
            padding: '10px 22px',
            background: skipHovered
              ? 'rgba(255, 255, 255, 0.15)'
              : 'rgba(255, 255, 255, 0.08)',
            border: skipHovered
              ? '1px solid rgba(255, 255, 255, 0.5)'
              : '1px solid rgba(255, 255, 255, 0.3)',
            borderRadius: 4,
            color: 'rgba(255, 255, 255, 0.85)',
            fontSize: 13,
            letterSpacing: '0.15em',
            textTransform: 'uppercase',
            fontFamily: 'inherit',
            cursor: 'pointer',
            backdropFilter: 'blur(8px)',
            WebkitBackdropFilter: 'blur(8px)',
            transition: 'all 200ms ease',
          }}
        >
          Skip →
        </button>
      )}
    </>
  )
}

export default App
