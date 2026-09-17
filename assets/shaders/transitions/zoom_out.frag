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
    vec4 cB = texture(uTextureB, uv);
    float s = max(1.0 - p, 0.001);
    vec2 centeredA = (uv - 0.5) / s + 0.5;
    if (centeredA.x >= 0.0 && centeredA.x <= 1.0 && centeredA.y >= 0.0 && centeredA.y <= 1.0) {
        vec4 cA = texture(uTextureA, centeredA);
        fragColor = mix(cB, cA, 1.0 - p);
    } else {
        fragColor = cB;
    }
}
