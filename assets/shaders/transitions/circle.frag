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
    vec2 aspectVec = vec2(uResolution.x / max(uResolution.y, 1.0), 1.0);
    float dist = length((uv - 0.5) * aspectVec);
    float maxDist = length(vec2(0.5) * aspectVec);
    float radius = p * maxDist;
    if (dist <= radius) {
        fragColor = texture(uTextureB, uv);
    } else {
        fragColor = texture(uTextureA, uv);
    }
}
