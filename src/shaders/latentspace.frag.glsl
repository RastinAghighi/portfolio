// Latent space scene — Phase 7b (v2)
// Brighter, more visible embedding field than v1. Same concept:
// sparse 3D grid of glowing AI-style embeddings, cool tinted, with depth parallax.

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;
uniform vec3  u_camPos;
uniform vec3  u_camTarget;

varying vec2 vUv;

// ---------- 3D hash ----------
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

// ---------- Embedding field (denser + brighter than v1) ----------
vec3 sampleEmbeddings(vec3 pos) {
  vec3 cell  = floor(pos);
  vec3 fcell = pos - cell;
  vec3 result = vec3(0.0);

  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dz = -1; dz <= 1; dz++) {
        vec3 nCell = cell + vec3(float(dx), float(dy), float(dz));
        vec3 h = hash33(nCell);

        if (h.x > 0.70) {                              // ~30% activation, up from 15%
          vec3 pInCell = vec3(float(dx), float(dy), float(dz)) + 0.15 + 0.7 * h;
          float d = length(fcell - pInCell);

          vec3 col = mix(
            vec3(0.30, 0.70, 1.00),
            vec3(0.60, 0.40, 1.00),
            h.y
          );

          float activation = pow(h.x - 0.70, 0.3) * 4.0;

          // Larger halos and stronger cores than v1
          float core = smoothstep(0.06, 0.0, d) * 10.0;
          float halo = smoothstep(0.45, 0.0, d) * 0.8;

          float pulse = 0.85 + 0.15 * sin(u_time * 0.6 + h.z * 6.28);

          result += col * (core + halo) * activation * pulse;
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

  vec3 color = vec3(0.020, 0.024, 0.045);

  float haze = noise3d(u_camPos * 0.05 + rayDir * 0.3 + vec3(u_time * 0.02));
  color += vec3(0.06, 0.08, 0.16) * haze * 0.7;

  vec3 pos = u_camPos;
  const int   steps    = 28;
  const float stepSize = 0.65;

  for (int i = 0; i < steps; i++) {
    float distAtten = 1.0 / (1.0 + 0.02 * float(i));   // gentler falloff
    color += sampleEmbeddings(pos) * stepSize * 0.12 * distAtten;
    pos += rayDir * stepSize;
  }

  color = color / (1.0 + color * 0.55);
  gl_FragColor = vec4(color, 1.0);
}
