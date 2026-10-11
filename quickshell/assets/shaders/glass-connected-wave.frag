#version 440

// Rebuild: qsb-qt6 --qt6 --qsbversion 64 -o assets/shaders/glass-connected-wave.frag.qsb assets/shaders/glass-connected-wave.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 effectSize;
    vec4 dialogBounds;
    float dialogRadius;
    float feather;
    float waveSpread;
    float waveOpacity;
    float joinHeight;
    float backgroundPass;
    vec4 color;
};

float softCoverage(float phase)
{
    return phase * phase * phase * (phase * (phase * 6.0 - 15.0) + 10.0);
}

void main()
{
    vec2 halfSize = dialogBounds.zw * 0.5;
    vec2 center = dialogBounds.xy + halfSize;
    float radius = clamp(dialogRadius, 0.0, min(halfSize.x, halfSize.y));
    vec2 offset = abs(qt_TexCoord0 * effectSize - center) - halfSize + vec2(radius);
    // Distance to the entire rounded outline, shared by expansion and return.
    float distanceFromDialog = length(max(offset, vec2(0.0)))
        + min(max(offset.x, offset.y), 0.0) - radius;
    float edgeWidth = max(feather, fwidth(distanceFromDialog));
    float phase = clamp((waveSpread + edgeWidth * 0.5 - distanceFromDialog)
        / edgeWidth, 0.0, 1.0);
    // A quintic falloff keeps both slope and curvature continuous at the edge.
    float coverage = softCoverage(phase) * waveOpacity;
    // Preserve the bar's single glass layer at the join, then gradually
    // introduce the foreground blur through a soft connecting strip.
    float join = joinHeight > 0.0
        ? softCoverage(clamp(qt_TexCoord0.y * effectSize.y / joinHeight, 0.0, 1.0)) : 1.0;
    coverage *= join;
    if (backgroundPass > 0.5) {
        // Base alpha + overlay alpha * (1 - base alpha) must remain the
        // bar's tint alpha. The advancing wave replaces the original tint.
        float remainingTint = (1.0 - coverage) / max(1.0 - color.a * coverage, 0.0001);
        fragColor = color * (remainingTint * qt_Opacity);
        return;
    }
    // The compositor blurs what is behind this translucent native surface.
    // Use the existing glass tint rather than filtering the controls' colors.
    fragColor = color * (coverage * qt_Opacity);
}
