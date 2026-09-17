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
    vec4 cA = texture(uTextureA, uv);
    vec2 centeredB = (uv - 0.5) / max(p, 0.001) + 0.5;
    if (centeredB.x >= 0.0 && centeredB.x <= 1.0 && centeredB.y >= 0.0 && centeredB.y <= 1.0) {
        vec4 cB = texture(uTextureB, centeredB);
        fragColor = mix(cA, cB, p);
    } else {
        fragColor = cA;
    }
}
