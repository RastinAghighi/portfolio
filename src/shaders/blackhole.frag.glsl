// Schwarzschild black hole — Phase 3 v2
// Disc rotation now via position rotation (not texCoord shift) to avoid
// floating-point precision drift over long runtime.

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;

varying vec2 vUv;

// ---------- Hash / noise / FBM ----------
float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
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

// ---------- Skybox: dim nebula + stars ----------
vec3 skybox(vec3 dir) {
  vec2 sphereCoord = vec2(atan(dir.z, dir.x), asin(dir.y) * 1.5);
  vec3 nebulaLow  = vec3(0.04, 0.02, 0.07);
  vec3 nebulaHigh = vec3(0.10, 0.05, 0.16);
  float n = fbm(sphereCoord * 1.5);
  vec3 bgColor = mix(nebulaLow, nebulaHigh, n);

  vec2 starCoord = sphereCoord * 60.0;
  vec2 cell  = floor(starCoord);
  vec2 fcell = fract(starCoord);
  float star = 0.0;
  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      vec2 neighbor = cell + vec2(float(dx), float(dy));
      float h = hash(neighbor);
      if (h > 0.93) {
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

// ---------- Accretion disc ----------
const float discInner = 1.6;
const float discOuter = 6.5;

vec3 sampleDisc(vec3 crossing) {
  vec2 xz = crossing.xz;
  float r = length(xz);

  if (r < discInner || r > discOuter) return vec3(0.0);

  float t = (r - discInner) / (discOuter - discInner);

  // Blackbody-inspired temperature gradient
  vec3 hotColor  = vec3(1.3, 1.0,  0.75);
  vec3 midColor  = vec3(1.0, 0.55, 0.18);
  vec3 coldColor = vec3(0.5, 0.15, 0.05);

  vec3 color;
  if (t < 0.25) {
    color = mix(hotColor, midColor, t / 0.25);
  } else {
    color = mix(midColor, coldColor, (t - 0.25) / 0.75);
  }

  // Rotate position by omega(t) — keeps texture coords bounded forever.
  // Inner orbits faster than outer (Keplerian-style differential rotation).
  float omega = u_time * 0.15 * (1.5 - t);
  float c     = cos(omega);
  float s     = sin(omega);
  vec2  rotXZ = vec2(c * xz.x - s * xz.y, s * xz.x + c * xz.y);

  // Sample FBM in rotated 2D space — naturally seamless, no precision drift
  float n = fbm(rotXZ * 0.6);
  float density = smoothstep(0.35, 0.85, n);

  float innerFade = smoothstep(0.0, 0.1, t);
  float outerFade = smoothstep(1.0, 0.65, t);

  return color * density * innerFade * outerFade * 1.8;
}

// ---------- Schwarzschild raymarcher with camera look-at ----------
void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  vec3 camPos    = vec3(0.0, 3.0, 10.0);
  vec3 camTarget = vec3(0.0, 0.0, 0.0);
  vec3 worldUp   = vec3(0.0, 1.0, 0.0);

  vec3 camForward = normalize(camTarget - camPos);
  vec3 camRight   = normalize(cross(camForward, worldUp));
  vec3 camUp      = cross(camRight, camForward);

  vec3 rayDir = normalize(uv.x * camRight + uv.y * camUp + 1.5 * camForward);

  vec3 pos = camPos;
  vec3 dir = rayDir;

  const float schwarzschildRadius = 1.0;
  const float maxDistance         = 50.0;
  const int   maxSteps            = 250;

  bool hitHorizon = false;
  vec3 discColor  = vec3(0.0);

  for (int i = 0; i < maxSteps; i++) {
    float r = length(pos);

    if (r < schwarzschildRadius) {
      hitHorizon = true;
      break;
    }
    if (r > maxDistance) break;

    float stepSize = max(0.06, r * 0.08);

    vec3 prevPos = pos;

    vec3  toCenter     = -pos / r;
    float bendStrength = 1.5 * schwarzschildRadius / (r * r);
    dir = normalize(dir + toCenter * bendStrength * stepSize);
    pos += dir * stepSize;

    // Filter grazing crossings — only count meaningful disc transitions
    if (prevPos.y * pos.y < 0.0 && abs(dir.y) > 0.03) {
      float tCross = -prevPos.y / (pos.y - prevPos.y);
      vec3  crossing = mix(prevPos, pos, tCross);
      discColor += sampleDisc(crossing);
    }
  }

  vec3 color = hitHorizon ? discColor : skybox(dir) + discColor;
  gl_FragColor = vec4(color, 1.0);
}
