#version 460 core

// Frosted-glass fold effect.
//
// Model:
// - UI content lives on a fixed plane in world space, the zero-tilt screen plane.
// - The eye is stationary on that plane's normal through the screen centre,
//   uEyeDistancePx back from the plane.
// - The tilted glass rotates by uTiltDegrees around the screen-space Y axis,
//   hinged on the edge farther from the viewer. That edge stays in the plane.
// - Per pixel: ray from the eye through the glass point, continued to the UI
//   plane, then a Vogel-disk blur whose radius grows with the glass-to-plane
//   gap, dimmed in proportion to how much it scatters. A missed kernel is black.
//
// Uniform conventions:
// - uTiltDegrees: signed tilt about the screen-space Y axis. Positive means the
//   right edge is farther from the viewer, so the hinge is on the RIGHT and the
//   frost spreads left. Negative hinges on the LEFT.
// - uHingeSide: +1 hinge right, -1 hinge left. Resolved at runtime from the
//   tilt sign, never hardcoded.
// - uBlurSpread: blur radius gained per px of glass-to-plane separation.
// - uDarkening: fraction of light lost per px of blur radius.
//
// uSize and uTexture are set by the engine, not by Dart: ImageFilter.shader
// binds the filter input to sampler 0 and its size to float uniforms 0 and 1.
// Declaration order below is therefore load-bearing. Custom floats start at
// index 2 and must stay in sync with DuoFoldParameters.packUniforms.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;            // engine: float 0, 1
uniform sampler2D uTexture;    // engine: sampler 0
uniform float uTiltDegrees;    // float 2
uniform float uEyeDistancePx;  // float 3
uniform float uHingeSide;      // float 4
uniform float uBlurSpread;     // float 5
uniform float uDarkening;      // float 6

out vec4 fragColor;

const float GOLDEN_ANGLE = 2.39996322972865332;
const float TWO_PI = 6.28318530717958648;
const float MAX_TAPS = 32.0;
const float MAX_TILT = 45.0;

// Samples the filter input at a pixel coordinate. Outside the input is empty,
// not clamped: the model wants black where the glass looks past the UI plane.
vec4 sampleContent(vec2 px) {
  vec2 uv = px / uSize;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
    return vec4(0.0);
  }
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, uv);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;

  if (uSize.x <= 1.0 || uSize.y <= 1.0) {
    fragColor = sampleContent(fragCoord);
    return;
  }

  float tilt = radians(clamp(abs(uTiltDegrees), 0.0, MAX_TILT));
  if (tilt < 1e-5) {
    fragColor = sampleContent(fragCoord);
    return;
  }

  // UI-plane frame: origin at the top-left of the untilted surface, in px.
  float isRight = step(0.0, uHingeSide);
  float hingeX = mix(0.0, uSize.x, isRight);
  float side = mix(1.0, -1.0, isRight);
  float d = abs(fragCoord.x - hingeX);

  // Glass rotated by tilt around the hinge line, rising toward the viewer.
  vec2 glass = vec2(hingeX + side * d * cos(tilt), fragCoord.y);
  float gap = d * sin(tilt);
  vec2 eye = uSize * 0.5;

  // Ray eye to glass pixel, continued to the UI plane at z = 0.
  float depth = uEyeDistancePx - gap;
  if (depth <= 1e-3) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  float t = uEyeDistancePx / depth;
  vec2 hit = eye + (glass - eye) * t;

  float radius = uBlurSpread * gap;

  // The whole kernel misses the UI.
  if (hit.x < -radius || hit.y < -radius ||
      hit.x > uSize.x + radius || hit.y > uSize.y + radius) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  // Frosted glass absorbs: dim in proportion to how much it scatters.
  float atten = max(1.0 - uDarkening * radius, 0.0);

  if (radius < 0.5) {
    fragColor = vec4(sampleContent(hit).rgb * atten, 1.0);
    return;
  }

  // Vogel disk with a per-pixel rotation, which turns banding into grain.
  // Small kernels near the hinge take few taps and stay cheap.
  //
  // The loop bound is a fixed constant rather than the uniform-derived
  // `taps`, because impellerc's SkSL target rejects a loop index compared
  // against a non-constant expression ("loop index must be compared with a
  // constant expression"). Each iteration is instead weighted to zero once
  // it passes tapsF, and the weights are summed into the divisor so the
  // average stays correct regardless of how many taps were actually live.
  float tapsF = clamp(radius * 2.0, 6.0, MAX_TAPS);
  float rotation =
      fract(sin(dot(fragCoord, vec2(12.9898, 78.233))) * 43758.5453) * TWO_PI;

  vec3 sum = vec3(0.0);
  float weightSum = 0.0;
  for (int i = 0; i < 32; i++) {
    float fi = float(i);
    float weight = 1.0 - step(tapsF, fi);
    float r = radius * sqrt((fi + 0.5) / tapsF);
    float a = fi * GOLDEN_ANGLE + rotation;
    sum += sampleContent(hit + r * vec2(cos(a), sin(a))).rgb * weight;
    weightSum += weight;
  }

  fragColor = vec4(sum / weightSum * atten, 1.0);
}
