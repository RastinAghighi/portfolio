import { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js'
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js'
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js'
import vertexShader from './shaders/blackhole.vert.glsl'
import fragmentShader from './shaders/blackhole.frag.glsl'
import latentVert from './shaders/latentspace.vert.glsl'
import latentFrag from './shaders/latentspace.frag.glsl'
import dustVert from './shaders/dust.vert.glsl'
import dustFrag from './shaders/dust.frag.glsl'

function App() {
  const mountRef = useRef(null)
  const skipRef = useRef(false)
  const fadeOverlayRef = useRef(null)
  const sceneRef = useRef({ stage: 'blackhole', dustStart: 0, latentStart: 0 })
  const [introDone, setIntroDone] = useState(false)
  const [skipHovered, setSkipHovered] = useState(false)

  const handleSkip = () => {
    skipRef.current = true
    if (fadeOverlayRef.current) {
      fadeOverlayRef.current.style.transition = 'opacity 400ms ease-in'
      fadeOverlayRef.current.style.opacity = '1'
    }
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
    renderer.toneMapping = THREE.ACESFilmicToneMapping
    renderer.toneMappingExposure = 1.0
    renderer.outputColorSpace = THREE.SRGBColorSpace
    mount.appendChild(renderer.domElement)

    const geometry = new THREE.PlaneGeometry(2, 2)
    const blackHoleMaterial = new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        u_resolution: { value: new THREE.Vector2() },
        u_time: { value: 0 },
        u_camPos: { value: new THREE.Vector3(0, 5, 30) },
        u_camTarget: { value: new THREE.Vector3(0, 0, 0) },
      },
    })
    const mesh = new THREE.Mesh(geometry, blackHoleMaterial)
    scene.add(mesh)

    renderer.getDrawingBufferSize(blackHoleMaterial.uniforms.u_resolution.value)

    const composer = new EffectComposer(renderer)

    const renderPass = new RenderPass(scene, camera)
    composer.addPass(renderPass)

    const bloomPass = new UnrealBloomPass(
      new THREE.Vector2(window.innerWidth, window.innerHeight),
      0.75,
      0.45,
      0.55
    )
    composer.addPass(bloomPass)

    const initialBufferSize = new THREE.Vector2()
    renderer.getDrawingBufferSize(initialBufferSize)
    composer.setSize(initialBufferSize.x, initialBufferSize.y)

    const latentMaterial = new THREE.ShaderMaterial({
      vertexShader: latentVert,
      fragmentShader: latentFrag,
      uniforms: {
        u_resolution: { value: new THREE.Vector2() },
        u_time:       { value: 0 },
        u_camPos:     { value: new THREE.Vector3(0, 0, 10) },
        u_camTarget:  { value: new THREE.Vector3(0, 0, 0) },
      },
    })
    renderer.getDrawingBufferSize(latentMaterial.uniforms.u_resolution.value)

    const dustMaterial = new THREE.ShaderMaterial({
      vertexShader: dustVert,
      fragmentShader: dustFrag,
      uniforms: {
        u_resolution: { value: new THREE.Vector2() },
        u_time:       { value: 0 },
        u_camPos:     { value: new THREE.Vector3(0, 0, 8) },
        u_camTarget:  { value: new THREE.Vector3(0, 0, 0) },
      },
    })
    renderer.getDrawingBufferSize(dustMaterial.uniforms.u_resolution.value)

    const TOTAL_DURATION = 20.0
    const FADE_START = 16.0
    const cameraCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0,    5,    30),
      new THREE.Vector3(0,    3,    10),
      new THREE.Vector3(0,    1.0,  4),
      new THREE.Vector3(0,    0.3,  1.5),
      new THREE.Vector3(0,    0.05, 0.5),
    ], false, 'centripetal')
    const camPosScratch = new THREE.Vector3()

    const LATENT_DURATION = 18.0
    const latentCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0,   0,    10),
      new THREE.Vector3(0.8, 0.4,  4),
      new THREE.Vector3(-0.6, 0.2, -3),
      new THREE.Vector3(0.3, 0.8,  -10),
      new THREE.Vector3(0,   1.0,  -16),
    ], false, 'centripetal')
    const latentCamScratch = new THREE.Vector3()
    const latentTargetScratch = new THREE.Vector3()

    const DUST_DURATION = 12.0
    const dustCurve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0,    0,    8),
      new THREE.Vector3(0.3,  0.2,  3),
      new THREE.Vector3(-0.4, -0.1, -3),
      new THREE.Vector3(0.2,  0.3,  -8),
    ], false, 'centripetal')
    const dustCamScratch    = new THREE.Vector3()
    const dustTargetScratch = new THREE.Vector3()

    let animStart = performance.now() / 1000
    let doneFired = false
    let fadeTriggered = false

    let frameId = 0
    const tick = () => {
      const now = performance.now() / 1000
      const skipped = skipRef.current

      if (sceneRef.current.stage === 'blackhole') {
        let elapsed = skipped ? TOTAL_DURATION : (now - animStart)

        if (elapsed >= FADE_START && !fadeTriggered && fadeOverlayRef.current) {
          fadeTriggered = true
          fadeOverlayRef.current.style.opacity = '1'
        }

        if (elapsed >= TOTAL_DURATION) {
          sceneRef.current.stage = 'dust'
          sceneRef.current.dustStart = now
          mesh.material = dustMaterial
          if (fadeOverlayRef.current) {
            fadeOverlayRef.current.style.transition = 'opacity 1.5s ease-out'
            fadeOverlayRef.current.style.opacity = '0'
          }
        } else {
          elapsed = Math.min(elapsed, TOTAL_DURATION)
          let p = elapsed / TOTAL_DURATION
          p = p * p * p * (p * (p * 6 - 15) + 10)
          cameraCurve.getPointAt(p, camPosScratch)
          blackHoleMaterial.uniforms.u_camPos.value.copy(camPosScratch)
          blackHoleMaterial.uniforms.u_time.value = now
        }
      }

      if (sceneRef.current.stage === 'dust') {
        const dustElapsed = skipped
          ? DUST_DURATION
          : (now - sceneRef.current.dustStart)

        if (dustElapsed >= DUST_DURATION - 2.0 && fadeOverlayRef.current && fadeOverlayRef.current.style.opacity !== '1') {
          fadeOverlayRef.current.style.transition = 'opacity 2s ease-in'
          fadeOverlayRef.current.style.opacity = '1'
        }

        if (dustElapsed >= DUST_DURATION) {
          sceneRef.current.stage = 'latent'
          sceneRef.current.latentStart = now
          mesh.material = latentMaterial
          if (fadeOverlayRef.current) {
            fadeOverlayRef.current.style.transition = 'opacity 1.5s ease-out'
            fadeOverlayRef.current.style.opacity = '0'
          }
        } else {
          const dp = Math.min(dustElapsed / DUST_DURATION, 1.0)
          const dps = dp * dp * dp * (dp * (dp * 6 - 15) + 10)
          dustCurve.getPointAt(dps, dustCamScratch)
          const dustTargetT = Math.min(dps + 0.15, 1.0)
          dustCurve.getPointAt(dustTargetT, dustTargetScratch)

          dustMaterial.uniforms.u_camPos.value.copy(dustCamScratch)
          dustMaterial.uniforms.u_camTarget.value.copy(dustTargetScratch)
          dustMaterial.uniforms.u_time.value = now
        }
      }

      if (sceneRef.current.stage === 'latent') {
        const latentElapsed = skipped
          ? LATENT_DURATION
          : (now - sceneRef.current.latentStart)

        if (latentElapsed >= LATENT_DURATION && !doneFired) {
          doneFired = true
          setIntroDone(true)
        }

        const lp = Math.min(latentElapsed / LATENT_DURATION, 1.0)
        const lps = lp * lp * lp * (lp * (lp * 6 - 15) + 10)

        latentCurve.getPointAt(lps, latentCamScratch)
        const targetT = Math.min(lps + 0.1, 1.0)
        latentCurve.getPointAt(targetT, latentTargetScratch)

        latentMaterial.uniforms.u_camPos.value.copy(latentCamScratch)
        latentMaterial.uniforms.u_camTarget.value.copy(latentTargetScratch)
        latentMaterial.uniforms.u_time.value = now
      }

      composer.render()
      frameId = requestAnimationFrame(tick)
    }
    frameId = requestAnimationFrame(tick)

    const handleResize = () => {
      const w = mount.clientWidth
      const h = mount.clientHeight
      renderer.setSize(w, h)
      renderer.getDrawingBufferSize(blackHoleMaterial.uniforms.u_resolution.value)
      renderer.getDrawingBufferSize(latentMaterial.uniforms.u_resolution.value)
      renderer.getDrawingBufferSize(dustMaterial.uniforms.u_resolution.value)
      const bufferSize = new THREE.Vector2()
      renderer.getDrawingBufferSize(bufferSize)
      composer.setSize(bufferSize.x, bufferSize.y)
    }
    window.addEventListener('resize', handleResize)

    return () => {
      cancelAnimationFrame(frameId)
      window.removeEventListener('resize', handleResize)
      geometry.dispose()
      blackHoleMaterial.dispose()
      latentMaterial.dispose()
      dustMaterial.dispose()
      composer.dispose()
      bloomPass.dispose()
      renderer.dispose()
      if (renderer.domElement.parentNode === mount) {
        mount.removeChild(renderer.domElement)
      }
    }
  }, [])

  return (
    <>
      <div ref={mountRef} style={{ width: '100vw', height: '100vh' }} />
      <div
        ref={fadeOverlayRef}
        style={{
          position: 'fixed',
          inset: 0,
          background: '#000',
          opacity: 0,
          transition: 'opacity 4s ease-in',
          pointerEvents: 'none',
          zIndex: 5,
        }}
      />
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
