// neo-overlay-small.glsl
// Small centered "NEO" with slow, subtle dark glow over your existing terminal.

#define PI 3.14159265359

// -------- math helpers --------
mat2 Rot(float a){ float c=cos(a), s=sin(a); return mat2(c,-s,s,c); }

float sdBox(vec2 p, vec2 b){
    vec2 d = abs(p) - b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}
float sdCircle(vec2 p, float r){ return length(p) - r; }

float smoothMask(float d, float w){ return 1.0 - smoothstep(0.0, w, d); }

// -------- dark, low-saturation palette (white-theme friendly) --------
vec3 palette(float t){
    // base around ~0.22, small amplitude; clamped so it stays dark
    vec3 a = vec3(0.22);
    vec3 b = vec3(0.08);
    vec3 c = vec3(1.00);
    vec3 d = vec3(0.10, 0.33, 0.66);
    vec3 col = a + b * cos(6.28318 * (c*t + d));
    return clamp(col, 0.14, 0.32);
}

// -------- letters (N/E/O) built from rotated boxes for crisp shapes --------
// Coordinate space: origin at letter center, height ~1.2, width ~0.7

float letterN(vec2 p){
    // Stems
    float hw = 0.35;                // half-width of letter
    float hh = 0.60;                // half-height of letter
    float w  = 0.10;                // stroke half-width
    float r  = 0.02;                // edge smoothing for mask

    float left  = sdBox(p - vec2(-hw, 0.0), vec2(w, hh));
    float right = sdBox(p - vec2( hw, 0.0), vec2(w, hh));

    // Diagonal: rotate coords so the diagonal becomes vertical, then box
    // 45° looks good visually; no shear artifacts.
    vec2 q = Rot(-PI*0.25) * p;                 // rotate by -45°
    float diag = sdBox(q, vec2(w, hh*1.05));    // slightly longer to meet stems

    float d = min(min(left, right), diag);
    return smoothMask(d, r);
}

float letterE(vec2 p){
    float hw = 0.35, hh = 0.60, w = 0.10, r = 0.02;

    float spine = sdBox(p - vec2(-hw, 0.0), vec2(w, hh));
    float top   = sdBox(p - vec2(-0.02,  hh - w), vec2(hw,      w));
    float mid   = sdBox(p - vec2(-0.02,  0.0),    vec2(hw*0.75, w));
    float bot   = sdBox(p - vec2(-0.02, -hh + w), vec2(hw,      w));

    float d = min(min(min(spine, top), mid), bot);
    return smoothMask(d, r);
}

float letterO(vec2 p){
    // Ring via difference of circles
    float R = 0.55, r = 0.35, e = 0.02;
    float outer = smoothMask(abs(sdCircle(p, R)), e);
    float inner = smoothMask(abs(sdCircle(p, r)), e);
    return clamp(outer - inner, 0.0, 1.0);
}

// -------- build centered “NEO”; returns (mask, approx dist for glow) --------
vec2 neoMask(vec2 fragCoord, vec2 res){
    // aspect-correct centered coords
    vec2 p = (fragCoord - 0.5 * res) / res.y;

    // size/spacing knobs
    float SCALE = 0.40;   // overall size (0.20–0.50)
    float ADV   = 0.90;   // letter advance
    p *= SCALE;

    // per-letter positions
    vec2 pN = p + vec2( ADV, 0.0);
    vec2 pE = p + vec2( 0.0, 0.0);
    vec2 pO = p + vec2(-ADV, 0.0);

    float mN = letterN(pN);
    float mE = letterE(pE);
    float mO = letterO(pO);
    float mask = clamp(mN + mE + mO, 0.0, 1.0);

    // coarse distance field for glow falloff (min of a few primitives)
    float dN = min( min( sdBox(pN - vec2(-0.35,0.0), vec2(0.10,0.60)),
                         sdBox(pN - vec2( 0.35,0.0), vec2(0.10,0.60)) ),
                    sdBox(Rot(-PI*0.25)*pN, vec2(0.10, 0.60*1.05)) );
    float dE = min( min( sdBox(pE - vec2(-0.35,0.0), vec2(0.10,0.60)),
                    min( sdBox(pE - vec2(-0.02,  0.60-0.10), vec2(0.35,0.10)),
                         sdBox(pE - vec2(-0.02,  0.0),        vec2(0.26,0.10)) ) ),
                    sdBox(pE - vec2(-0.02, -0.60+0.10), vec2(0.35,0.10)) );
    float dO = abs(sdCircle(pO, 0.55)) - 0.20;

    float d = min(min(dN, dE), dO);
    return vec2(mask, d);
}

// -------- main --------
void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord / iResolution.xy;

    // Base: terminal as-is
    vec4 term = texture(iChannel0, uv);

    // Centered NEO
    vec2 mm    = neoMask(fragCoord, iResolution.xy);
    float m    = mm.x;
    float dist = mm.y;

    // Slow, dark color cycle
    vec3 hue  = palette(iTime * 0.02);
    vec3 core = mix(vec3(1.0), hue, 0.50);   // keep it dark/muted

    // Tight, subtle glow (a few pixels)
    float inner = exp(-25.0 * max(dist, 0.0));  // ~tight core
    float outer = exp(-4.0  * max(dist, 0.0));  // soft skirt
    float glow  = 0.65 * inner + 0.30 * outer;

    // Gentle additive overlay (don’t repaint the screen)
    vec3 addRGB = core * (0.10 * m + 0.30 * glow);

    // Composite: add on top of terminal and clamp
    vec3 outRGB = min(term.rgb + addRGB, 1.0);

    fragColor = vec4(outRGB, 1.0);
}

