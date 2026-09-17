#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uProgress;
uniform sampler2D uTextureA;
uniform sampler2D uTextureB;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    float p = clamp(uProgress, 0.0, 1.0);
    float peak = 1.0 - abs(p - 0.5) * 2.0;
    float cellSize = mix(1.0, 32.0, peak * peak);
    vec2 cells = max(uResolution / cellSize, vec2(4.0));
    vec2 steppedUv = floor(uv * cells) / cells;

    vec4 cA = texture(uTextureA, steppedUv);
    vec4 cB = texture(uTextureB, steppedUv);
    fragColor = mix(cA, cB, p);
}
