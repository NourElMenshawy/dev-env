// nebula-bg+text.glsl
// Slow animated background. Terminal text is drawn on top unchanged.

vec3 palette(float t) {
    vec3 a = vec3(0.5);
    vec3 b = vec3(0.5);
    vec3 c = vec3(1.0);
    vec3 d = vec3(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

vec3 slow_nebula(vec2 fragCoord, float speed) {
    vec2 uv  = (fragCoord * 2.0 - iResolution.xy) / iResolution.y;
    vec2 uv0 = uv;
    vec3 col = vec3(0.0);

    for (float i = 0.0; i < 4.0; i++) {
        uv = fract(uv * 1.5) - 0.5;
        float d = length(uv) * exp(-length(uv0));
        vec3 p = palette(length(uv0) + i * 0.4 + iTime * speed);
        d = sin(d * 8.0 + iTime * speed) / 8.0;
        d = abs(d);
        d = pow(0.01 / max(d, 1e-4), 1.2);
        col += p * d;
    }
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // 1) paint the background
    const float SPEED = 0.05;   // very slow
    vec4 bg = vec4(slow_nebula(fragCoord, SPEED), 1.0);

    // 2) draw terminal content unmodified on top
    vec2 uv = fragCoord / iResolution.xy;
    vec4 term = texture(iChannel0, uv);

    // If term.a is meaningful, composite with it; otherwise just show term.
    fragColor = term.a > 0.0 ? mix(bg, term, term.a) : term;
}

