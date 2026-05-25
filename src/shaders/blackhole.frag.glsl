// Schwarzschild black hole — Phase 7c (polish iteration 1)
// Adds Doppler beaming, domain-warped filament noise, and higher contrast
// for the Gargantua-quality look. Designed to be rendered through bloom
// post-processing — outputs HDR values >1 in the brightest disc regions.

precision highp float;

uniform vec2  u_resolution;
uniform float u_time;
uniform vec3  u_camPos;
uniform vec3  u_camTarget;

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
  for (int i = 0; i < 6; i++) {                     // 6 octaves now (was 5)
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
  vec3 starColor = vec3(0.9, 0.95, 1.0) * star * 1.4;
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

  // Temperature gradient — pushed slightly hotter at inner edge for HDR bloom
  vec3 hotColor  = vec3(1.6, 1.3,  0.95);
  vec3 midColor  = vec3(1.2, 0.55, 0.18);
  vec3 coldColor = vec3(0.45, 0.12, 0.04);

  vec3 color;
  if (t < 0.25) {
    color = mix(hotColor, midColor, t / 0.25);
  } else {
    color = mix(midColor, coldColor, (t - 0.25) / 0.75);
  }

  // Uniform slow rotation
  float omega = u_time * 0.04;
  float cR    = cos(omega);
  float sR    = sin(omega);
  vec2  rotXZ = vec2(cR * xz.x - sR * xz.y, sR * xz.x + cR * xz.y);

  // ---- Domain-warped multi-scale noise for filament structure ----
  // Use one noise field to perturb the sampling positions of another.
  // This is what produces the swirly filament look instead of cloudy blobs.
  vec2 q = vec2(
    fbm(rotXZ * 0.5),
    fbm(rotXZ * 0.5 + vec2(5.2, 1.3))
  );
  vec2 warped = rotXZ + 2.4 * q;

  float largeScale = fbm(warped * 0.7);
  float midScale   = fbm(warped * 2.0);
  float fineScale  = fbm(warped * 5.5);

  float n = largeScale * 0.55 + midScale * 0.30 + fineScale * 0.15;

  // Sharper threshold for higher-contrast filaments (was 0.35..0.85)
  float density = smoothstep(0.42, 0.72, n);

  // ---- Doppler beaming ----
  // Material orbits in xz plane. At a disc point (x, 0, z), the orbital
  // direction (counterclockwise viewed from +y) is (-z, 0, x) / r.
  // Orbital speed approximates Keplerian: sqrt(GM/r) with GM = 0.5 in our units.
  // The relativistic beaming makes the side moving toward the camera much
  // brighter — the iconic asymmetric Gargantua look.
  vec3 discPoint3D = vec3(xz.x, 0.0, xz.y);
  vec3 orbitalDir  = normalize(vec3(-xz.y, 0.0, xz.x));
  float orbitalSpeed = sqrt(0.5 / max(r, 0.5));
  vec3 velocity = orbitalDir * orbitalSpeed;

  vec3 toCam = normalize(u_camPos - discPoint3D);
  float vDotN = dot(velocity, toCam);

  float doppler = 1.0 / max(0.35, 1.0 - vDotN);
  float beaming = pow(doppler, 2.6);                  // tunable strength
  beaming = clamp(beaming, 0.3, 6.0);

  // Edge fades
  float innerFade = smoothstep(0.0, 0.1, t);
  float outerFade = smoothstep(1.0, 0.65, t);

  return color * density * beaming * innerFade * outerFade * 1.4;
}

// ---------- Schwarzschild raymarcher ----------
void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  vec3 camPos    = u_camPos;
  vec3 camTarget = u_camTarget;
  vec3 worldUp   = vec3(0.0, 1.0, 0.0);

  vec3 camForward = normalize(camTarget - camPos);
  vec3 camRight   = normalize(cross(camForward, worldUp));
  vec3 camUp      = cross(camRight, camForward);

  vec3 rayDir = normalize(uv.x * camRight + uv.y * camUp + 1.5 * camForward);

  vec3 pos = camPos;
  vec3 dir = rayDir;

  const float schwarzschildRadius = 1.0;
  const float maxDistance         = 60.0;
  const int   maxSteps            = 300;              // more steps for photon-ring accuracy

  bool hitHorizon = false;
  vec3 discColor  = vec3(0.0);

  for (int i = 0; i < maxSteps; i++) {
    float r = length(pos);

    if (r < schwarzschildRadius) {
      hitHorizon = true;
      break;
    }
    if (r > maxDistance) break;

    // Smaller steps near the BH for sharper lensing and clearer photon ring
    float stepSize = max(0.04, r * 0.07);

    vec3 prevPos = pos;

    vec3  toCenter     = -pos / r;
    float bendStrength = 1.5 * schwarzschildRadius / (r * r);
    dir = normalize(dir + toCenter * bendStrength * stepSize);
    pos += dir * stepSize;

    if (prevPos.y * pos.y < 0.0 && abs(dir.y) > 0.03) {
      float tCross = -prevPos.y / (pos.y - prevPos.y);
      vec3  crossing = mix(prevPos, pos, tCross);
      discColor += sampleDisc(crossing);
    }
  }

  vec3 color = hitHorizon ? discColor : skybox(dir) + discColor;

  // Output HDR — let the bloom + tone mapping in post-processing handle the rest.
  // Do NOT clamp here; bright pixels feeding the bloom pass is the whole point.
  gl_FragColor = vec4(color, 1.0);
}
