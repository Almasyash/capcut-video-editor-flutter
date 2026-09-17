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
    float blurAmount = (1.0 - abs(p - 0.5) * 2.0) * 0.02;

    vec4 sumA = vec4(0.0);
    vec4 sumB = vec4(0.0);
    if (blurAmount <= 0.001) {
        sumA = texture(uTextureA, uv);
        sumB = texture(uTextureB, uv);
    } else {
        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                vec2 offset = vec2(float(x), float(y)) * blurAmount;
                sumA += texture(uTextureA, clamp(uv + offset, 0.0, 1.0));
                sumB += texture(uTextureB, clamp(uv + offset, 0.0, 1.0));
            }
        }
        sumA /= 9.0;
        sumB /= 9.0;
    }

    fragColor = mix(sumA, sumB, p);
}
