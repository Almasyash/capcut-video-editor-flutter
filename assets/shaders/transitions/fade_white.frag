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
        float t = clamp(p * 2.0, 0.0, 1.0);
        fragColor = vec4(mix(cA.rgb, vec3(1.0), t), cA.a);
    } else {
        float t = clamp((p - 0.5) * 2.0, 0.0, 1.0);
        fragColor = vec4(mix(vec3(1.0), cB.rgb, t), cB.a);
    }
}
