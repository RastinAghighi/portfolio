// Schwarzschild black hole — Phase 2 v2
// Same raymarcher as v1, but with a dim nebula background (via FBM noise)
// and denser stars so the black hole silhouette and lensing are visible.

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

varying vec2 vUv;

// ---------- Hash + value noise + FBM ----------
// Dave Hoskins-style 2D hash. Well-distributed, no sin() artifacts.

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);                         // smoothstep interpolation
  return mix(
    mix(hash(i),                  hash(i + vec2(1.0, 0.0)), f.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
    f.y
  );
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p *= 2.0;
    a *= 0.5;
  }
  return v;
}

// ---------- Skybox: dim nebula + pinpoint stars ----------

vec3 skybox(vec3 dir) {
  // Project direction onto 2D sphere coords
  vec2 sphereCoord = vec2(atan(dir.z, dir.x), asin(dir.y) * 1.5);

  // Nebula background (dim purples). Never pure black.
  vec3 nebulaLow  = vec3(0.04, 0.02, 0.07);
  vec3 nebulaHigh = vec3(0.10, 0.05, 0.16);
  float n = fbm(sphereCoord * 1.5);
  vec3 bgColor = mix(nebulaLow, nebulaHigh, n);

  // Sparse bright stars over the nebula
  vec2 starCoord = sphereCoord * 60.0;
  vec2 cell  = floor(starCoord);
  vec2 fcell = fract(starCoord);

  float star = 0.0;
  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      vec2 neighbor = cell + vec2(float(dx), float(dy));
      float h = hash(neighbor);
      if (h > 0.93) {                                  // ~7% of cells are stars
        vec2 starPos = vec2(float(dx), float(dy)) +
                       vec2(hash(neighbor + 17.3), hash(neighbor + 31.7));
        float d = length(fcell - starPos);
        float brightness = (h - 0.93) / 0.07;
        star += brightness * smoothstep(0.06, 0.0, d);
      }
    }
  }

  vec3 starColor = vec3(0.9, 0.95, 1.0) * star;
  return bgColor + starColor;
}

// ---------- Schwarzschild raymarcher ----------

void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  vec3 camPos = vec3(0.0, 0.5, 12.0);
  vec3 rayDir = normalize(vec3(uv, -1.5));

  vec3 pos = camPos;
  vec3 dir = rayDir;

  const float schwarzschildRadius = 1.0;
  const float maxDistance         = 30.0;
  const int   maxSteps            = 200;

  bool hitHorizon = false;

  for (int i = 0; i < maxSteps; i++) {
    float r = length(pos);

    if (r < schwarzschildRadius) {                     // captured
      hitHorizon = true;
      break;
    }
    if (r > maxDistance) break;                        // escaped

    float stepSize = max(0.06, r * 0.08);

    vec3  toCenter     = -pos / r;
    float bendStrength = 1.5 * schwarzschildRadius / (r * r);
    dir = normalize(dir + toCenter * bendStrength * stepSize);

    pos += dir * stepSize;
  }

  vec3 color = hitHorizon ? vec3(0.0) : skybox(dir);
  gl_FragColor = vec4(color, 1.0);
}
