// Dust cloud scene — polish iteration
// Dense field of fine white-silver dust grains with occasional hot orange
// sparks mixed in (~5%). HDR amplitudes so bloom + tone mapping land it
// in cinematic territory.

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;
uniform vec3  u_camPos;
uniform vec3  u_camTarget;

varying vec2 vUv;

// ---------- 3D hash ----------
vec3 hash33(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
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

// ---------- Dust grain field ----------
// Most particles white-silver, ~5% are hot orange sparks.
vec3 sampleDustField(vec3 pos) {
  vec3 cell  = floor(pos);
  vec3 fcell = pos - cell;
  vec3 result = vec3(0.0);

  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dz = -1; dz <= 1; dz++) {
        vec3 nCell = cell + vec3(float(dx), float(dy), float(dz));
        vec3 h = hash33(nCell);

        if (h.x > 0.25) {                              // dense ~75%
          vec3 pInCell = vec3(float(dx), float(dy), float(dz)) + 0.05 + 0.9 * h;
          float d = length(fcell - pInCell);
          float bright = (h.x - 0.25) / 0.75;          // 0..1

          // Sharp small core + soft halo (bloom does the rest)
          float core = smoothstep(0.045, 0.0, d) * 9.0;
          float halo = smoothstep(0.17,  0.0, d) * 0.35;

          // ~5% of particles are hot orange sparks; the rest are dust
          vec3 dustColor  = vec3(1.0, 0.95, 0.88);
          vec3 sparkColor = vec3(2.8, 1.3,  0.35);     // HDR — blooms heavily
          float isSpark = step(0.95, h.y);
          vec3 particleColor = mix(dustColor, sparkColor, isSpark);

          result += particleColor * (core + halo) * bright;
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

  // Near-black ambient — dust must read against pure dark
  vec3 color = vec3(0.004, 0.004, 0.006);

  // Subtle volumetric tint, very faint
  float haze = noise3d(u_camPos * 0.08 + rayDir * 0.3 + vec3(u_time * 0.03));
  color += vec3(0.025, 0.020, 0.018) * haze;

  // Raymarch the dust
  vec3 pos = u_camPos;
  const int   steps    = 28;
  const float stepSize = 0.5;

  for (int i = 0; i < steps; i++) {
    float distAtten = 1.0 / (1.0 + 0.03 * float(i));
    color += sampleDustField(pos) * stepSize * 0.075 * distAtten;
    pos += rayDir * stepSize;
  }

  gl_FragColor = vec4(color, 1.0);
}
