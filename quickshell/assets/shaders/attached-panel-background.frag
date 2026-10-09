#version 440

// Rebuild: qsb-qt6 --qt6 --qsbversion 64 -o assets/shaders/attached-panel-background.frag.qsb assets/shaders/attached-panel-background.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 flowSize;
    vec2 flowAnchor;
    float flowProgress;
    float flowStrength;
    vec2 panelSize;
    vec2 drawSize;
    vec4 color;
    float cornerRadius;
    float edgeSoftness;
    float blendHeight;
};

void main()
{
    vec2 p = qt_TexCoord0 * drawSize;
    float r = cornerRadius;
    float bottom = panelSize.y - r;

    // Same outline as media-panel.frag, evaluated without a source texture.
    float edgeDistance = max(r - p.x, p.y - bottom);
    if (p.y < r)
        edgeDistance = r - length(p - vec2(0.0, r));
    if (p.x < 2.0 * r && p.y > bottom - r)
        edgeDistance = length(p - vec2(2.0 * r, bottom - r)) - r;
    if (p.x > panelSize.x - r)
        edgeDistance = r - length(p - vec2(panelSize.x - r, panelSize.y));

    float pixelWidth = max(edgeSoftness
        * length(vec2(dFdx(edgeDistance), dFdy(edgeDistance))), 0.0001);
    float coverage = 1.0 - smoothstep(-0.5 * pixelWidth, 0.5 * pixelWidth, edgeDistance);
    float blend = blendHeight > 0.0 ? smoothstep(0.0, blendHeight, p.y) : 1.0;
    fragColor = color * (coverage * blend * qt_Opacity);
}
