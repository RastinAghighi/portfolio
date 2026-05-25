// Dust cloud scene — Phase 7a
// Camera flies through a dense field of debris/dust particles in space.
// Neutral warm tones (cream / dim brown), dense parallax, volumetric haze.
// Visually distinct from the cooler latent space scene that follows.

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;
uniform vec3  u_camPos;
uniform vec3  u_camTarget;

varying vec2 vUv;

// ---------- 3D hash functions ----------
float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

// ---------- 3D smooth noise ----------
float noise3d(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(
      mix(hash13(i),                hash13(i + vec3(1,0,0)), f.x),
      mix(hash13(i + vec3(0,1,0)),  hash13(i + vec3(1,1,0)), f.x),
      f.y
    ),
    mix(
      mix(hash13(i + vec3(0,0,1)),  hash13(i + vec3(1,0,1)), f.x),
      mix(hash13(i + vec3(0,1,1)),  hash13(i + vec3(1,1,1)), f.x),
      f.y
    ),
    f.z
  );
}

// ---------- Dust particle field ----------
// Dense (~55% of cells active), neutral warm colors, smaller particle size
// than the latent space embeddings.
vec3 sampleDust(vec3 pos) {
  vec3 cell  = floor(pos);
  vec3 fcell = pos - cell;
  vec3 result = vec3(0.0);

  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dz = -1; dz <= 1; dz++) {
        vec3 nCell = cell + vec3(float(dx), float(dy), float(dz));
        vec3 h = hash33(nCell);

        if (h.x > 0.45) {                              // dense ~55%
          vec3 pInCell = vec3(float(dx), float(dy), float(dz)) + 0.05 + 0.9 * h;
          float d = length(fcell - pInCell);

          // Neutral warm palette — cream to dim brown
          vec3 col = mix(
            vec3(0.85, 0.80, 0.72),
            vec3(0.55, 0.45, 0.38),
            h.y
          );

          float brightness = (h.x - 0.45) / 0.55;      // 0..1

          // Small sharp grains
          float core = smoothstep(0.025, 0.0, d) * 5.0;
          float halo = smoothstep(0.14, 0.0, d) * 0.35;

          result += col * (core + halo) * brightness;
        }
      }
    }
  }
  return result;
}

void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  vec3 camForward = normalize(u_camTarget - u_camPos);
  vec3 camRight   = normalize(cross(camForward, vec3(0.0, 1.0, 0.0)));
  vec3 camUp      = cross(camRight, camForward);
  vec3 rayDir     = normalize(uv.x * camRight + uv.y * camUp + 1.5 * camForward);

  // Dim ambient with warm tint
  vec3 color = vec3(0.025, 0.022, 0.018);

  // Volumetric haze — denser than latent for cloud feel
  float haze = noise3d(u_camPos * 0.08 + rayDir * 0.4 + vec3(u_time * 0.05));
  color += vec3(0.07, 0.06, 0.045) * haze;

  // Raymarch the dust field
  vec3 pos = u_camPos;
  const int   steps    = 30;
  const float stepSize = 0.5;

  for (int i = 0; i < steps; i++) {
    float distAtten = 1.0 / (1.0 + 0.04 * float(i));
    color += sampleDust(pos) * stepSize * 0.10 * distAtten;
    pos += rayDir * stepSize;
  }

  color = color / (1.0 + color * 0.5);
  gl_FragColor = vec4(color, 1.0);
}
