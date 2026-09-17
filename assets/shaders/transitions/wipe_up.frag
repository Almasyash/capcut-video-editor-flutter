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
    if (uv.y < (1.0 - p)) {
        fragColor = texture(uTextureA, uv);
    } else {
        fragColor = texture(uTextureB, uv);
    }
}
