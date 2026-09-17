#version 460 core
#include <flutter/runtime_effect.glsl>

#define PI 3.141592653589793

uniform vec2 uResolution;
uniform float uProgress;
uniform sampler2D uTextureA;
uniform sampler2D uTextureB;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;
    float p = clamp(uProgress, 0.0, 1.0);
    vec2 d = uv - 0.5;
    float angle = atan(-d.x, d.y) + PI;
    float sweep = angle / (2.0 * PI);
    if (sweep <= p) {
        fragColor = texture(uTextureB, uv);
    } else {
        fragColor = texture(uTextureA, uv);
    }
}
