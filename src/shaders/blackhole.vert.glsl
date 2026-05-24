// Passthrough vertex shader for the fullscreen quad.
// Geometry is a 2x2 plane in clip space, so we just pass position through.
// All the work happens in the fragment shader.

varying vec2 vUv;

void main() {
  vUv = uv;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
