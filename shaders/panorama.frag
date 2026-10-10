// Renders a perspective view of an equirectangular panorama (full sphere or a
// cropped part of it, e.g. a 180° photo) for the given yaw / pitch / field of view.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;   // viewport in px
uniform float uYaw;   // radians, + turns right
uniform float uPitch; // radians, + looks up
uniform float uFov;   // vertical field of view, radians
uniform vec4 uCrop;   // image area within the full sphere: left, top, width, height (0..1)
uniform sampler2D uTex;

out vec4 fragColor;

const float PI = 3.14159265359;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float t = tan(uFov * 0.5);
  vec3 d = normalize(vec3((2.0 * p.x / uSize.x - 1.0) * t * uSize.x / uSize.y,
                          -(2.0 * p.y / uSize.y - 1.0) * t, 1.0));
  float cp = cos(uPitch), sp = sin(uPitch);
  d = vec3(d.x, d.y * cp + d.z * sp, -d.y * sp + d.z * cp);
  float cy = cos(uYaw), sy = sin(uYaw);
  d = vec3(d.x * cy + d.z * sy, d.y, -d.x * sy + d.z * cy);

  float u = atan(d.x, d.z) / (2.0 * PI) + 0.5;
  float v = 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI;
  u = (u - uCrop.x) / uCrop.z;
  v = (v - uCrop.y) / uCrop.w;
  if (uCrop.z > 0.999) u = fract(u); // full 360°: wrap around
  if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  fragColor = texture(uTex, vec2(u, v));
}
