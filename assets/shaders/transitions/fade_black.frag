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
    vec4 cB = texture(uTextureB, uv);
    if (p < 0.5) {
        float a = clamp(1.0 - p * 2.0, 0.0, 1.0);
        fragColor = vec4(cA.rgb * a, cA.a);
    } else {
        float a = clamp((p - 0.5) * 2.0, 0.0, 1.0);
        fragColor = vec4(cB.rgb * a, cB.a);
    }
}
