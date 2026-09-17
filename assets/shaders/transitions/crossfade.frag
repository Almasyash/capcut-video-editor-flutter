#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uProgress;
uniform sampler2D uTextureA;
uniform sampler2D uTextureB;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    vec4 cA = texture(uTextureA, uv);
    vec4 cB = texture(uTextureB, uv);
    fragColor = mix(cA, cB, clamp(uProgress, 0.0, 1.0));
}
