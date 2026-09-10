#version 460 core

// Frosted-glass fold effect.
//
// Model:
// - UI content lives on a fixed plane in world space, the zero-tilt screen plane.
// - The eye is stationary on that plane's normal through the screen centre,
//   uEyeDistancePx back from the plane.
// - The pane hinges on a line at any angle and rotates by uTiltDegrees, the far
//   side lifting toward the viewer. The hinge line itself stays in the plane.
// - Per pixel: ray from the eye through the glass point, continued to the UI
//   plane, then a Vogel-disk blur whose radius grows with the glass-to-plane
//   gap, dimmed in proportion to how much it scatters. Where the ray lands off
//   the UI plane there is nothing to sample, so the surround colour is used.
//
// Uniform conventions:
// - uTiltDegrees: magnitude only, 0 to 45, never negative. Direction lives in
//   uLiftDirX/uLiftDirY instead of in the sign.
// - uLiftDirX, uLiftDirY: unit vector, in fragment coordinates (y down),
//   pointing from the hinge line toward the edge that rises toward the viewer.
//   uLiftDirX = -1, uLiftDirY = 0 reproduces the old hinge-right behaviour.
// - uBlurSpread: blur radius gained per px of glass-to-plane separation.
// - uEdgeStretch: 1 samples the content clamped to its own edge, so the last
//   row and column smear outward and the frost covers the whole screen even
//   where the tilt has swung the glass past the content. 0 leaves that region
//   as the surround colour, which is the plain optical answer: nothing is
//   there, so nothing is shown.
// - uBaseBlurPx: blur radius applied everywhere once the fold is off rest,
//   including on the hinge line itself. Without it the frost is a gradient
//   that reaches zero at the hinge, so half the screen stays sharp.
// - uDarkening: fraction of light lost per px of blur radius.
// - uHazeR/G/B: what the scattered light fades toward. Absorption alone is a
//   fade to black, which is what black here gives. Real frosted glass usually
//   scatters some light back out and veils toward white instead, and a tinted
//   haze is the same trick with a colour behind it.
// - uSurroundR/G/B: what lies beyond the edge of the content plane. The filter
//   input is the folded subtree alone, and this shader writes an opaque colour,
//   so whatever a host paints behind the widget can never show through here.
//   The surround has to be handed in instead. Black gives a void; the host's
//   background colour makes the fold sit on the surface it is drawn on.
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
uniform float uLiftDirX;       // float 3
uniform float uLiftDirY;       // float 4
uniform float uEyeDistancePx;  // float 5
uniform float uBlurSpread;     // float 6
uniform float uDarkening;      // float 7
// Scalars, not vec3. Vector uniforms are padded and aligned by the backend,
// and a runtime effect's floats are addressed by index from Dart, so a padded
// vec3 silently shifts every uniform after it. uLiftDirX and uLiftDirY are
// split for the same reason.
uniform float uSurroundR;      // float 8
uniform float uSurroundG;      // float 9
uniform float uSurroundB;      // float 10
uniform float uHazeR;          // float 11
uniform float uHazeG;          // float 12
uniform float uHazeB;          // float 13
uniform float uBaseBlurPx;     // float 14
uniform float uEdgeStretch;    // float 15

out vec4 fragColor;

vec3 surroundColor() {
  return vec3(uSurroundR, uSurroundG, uSurroundB);
}

vec3 hazeColor() {
  return vec3(uHazeR, uHazeG, uHazeB);
}

const float GOLDEN_ANGLE = 2.39996322972865332;
const float TWO_PI = 6.28318530717958648;
const float MAX_TAPS = 32.0;
const float MAX_TILT = 45.0;

// Samples the filter input at a pixel coordinate.
//
// Two answers for a coordinate that lands off the content, chosen by
// uEdgeStretch. Clamped, the edge row and column smear outward, which fills the
// space the tilt opens up and keeps the frost running to the screen edge.
// Unclamped, the sample is the surround: nothing is there, so nothing is shown.
// Either way the off-content case returns an opaque colour rather than
// transparent black, which keeps a kernel straddling the boundary from
// dragging the edge dark.
vec4 sampleContent(vec2 px) {
  vec2 uv = px / uSize;
  if (uEdgeStretch > 0.5) {
    uv = clamp(uv, vec2(0.0), vec2(1.0));
  } else if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
    return vec4(surroundColor(), 1.0);
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

  float tilt = radians(clamp(uTiltDegrees, 0.0, MAX_TILT));
  if (tilt < 1e-5) {
    fragColor = sampleContent(fragCoord);
    return;
  }

  // UI-plane frame: origin at the top-left of the untilted surface, in px.
  // liftDir points from the hinge line toward the edge that rises toward
  // the viewer. sHinge is the hinge line's projection onto liftDir, the
  // minimum projection of the rect's four corners.
  vec2 liftDir = vec2(uLiftDirX, uLiftDirY);
  float sHinge = min(0.0, uSize.x * liftDir.x) + min(0.0, uSize.y * liftDir.y);
  float d = dot(fragCoord, liftDir) - sHinge;

  // Glass rotated by tilt around the hinge line, rising toward the viewer.
  vec2 glass = fragCoord - liftDir * d * (1.0 - cos(tilt));
  float gap = d * sin(tilt);
  vec2 eye = uSize * 0.5;

  // Ray eye to glass pixel, continued to the UI plane at z = 0.
  float depth = uEyeDistancePx - gap;
  if (depth <= 1e-3) {
    fragColor = vec4(surroundColor(), 1.0);
    return;
  }
  float t = uEyeDistancePx / depth;
  vec2 hit = eye + (glass - eye) * t;

  float radius = uBlurSpread * gap + uBaseBlurPx;

  // The whole kernel misses the UI, so nothing is scattered and the surround
  // comes through undimmed. Skipped when the edge is stretched, since then
  // every tap has something to read and the blur carries on out here.
  if (uEdgeStretch < 0.5 &&
      (hit.x < -radius || hit.y < -radius ||
          hit.x > uSize.x + radius || hit.y > uSize.y + radius)) {
    fragColor = vec4(surroundColor(), 1.0);
    return;
  }

  // Frosted glass scatters, and what it scatters is lost to the haze: fade
  // toward the haze colour in proportion to how much scattering the gap causes.
  float atten = max(1.0 - uDarkening * radius, 0.0);

  if (radius < 0.5) {
    fragColor = vec4(mix(hazeColor(), sampleContent(hit).rgb, atten), 1.0);
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

  fragColor = vec4(mix(hazeColor(), sum / weightSum, atten), 1.0);
}
