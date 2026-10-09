#version 440

// Rebuild: qsb-qt6 --qt6 --qsbversion 64 -o assets/shaders/attached-panel.frag.qsb assets/shaders/attached-panel.frag
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
    float cornerRadius;
    float borderWidth;
    float edgeSoftness;
    vec4 borderColor;
    float attachRightEdge;
};
layout(binding = 1) uniform sampler2D source;

float coverage(float distanceToEdge)
{
    // Derivatives follow the physical pixel size, including display scaling.
    // Keep a consistent feather width around curves as well as straight edges.
    float pixelWidth = max(edgeSoftness
        * length(vec2(dFdx(distanceToEdge), dFdy(distanceToEdge))), 0.0001);
    return 1.0 - smoothstep(-0.5 * pixelWidth, 0.5 * pixelWidth, distanceToEdge);
}

void main()
{
    vec2 p = qt_TexCoord0 * panelSize;
    float r = cornerRadius;
    float bottom = panelSize.y - r;

    // Signed distance to the open left/bottom outline. The two concave
    // shoulders are circular cutouts; their tangents meet the straight edges.
    float edgeDistance = max(r - p.x, p.y - bottom);
    if (p.y < r)
        edgeDistance = r - length(p - vec2(0.0, r));
    if (p.x < 2.0 * r && p.y > bottom - r)
        edgeDistance = length(p - vec2(2.0 * r, bottom - r)) - r;
    if (attachRightEdge > 0.5) {
        if (p.x > panelSize.x - r)
            edgeDistance = r - length(p - vec2(panelSize.x - r, panelSize.y));
    } else {
        // A centered popup has a matching bar shoulder and bottom corner.
        edgeDistance = max(edgeDistance, p.x - (panelSize.x - r));
        if (p.x > panelSize.x - r && p.y < r)
            edgeDistance = r - length(p - vec2(panelSize.x, r));
        if (p.x > panelSize.x - 2.0 * r && p.y > bottom - r)
            edgeDistance = length(p - vec2(panelSize.x - 2.0 * r, bottom - r)) - r;
    }

    // The top and right sides join the bar and monitor with square corners.
    // Only the exposed left/bottom outline needs a rounded mask and border.
    float fillCoverage = coverage(edgeDistance);
    float borderCoverage = min(fillCoverage,
        max(coverage(edgeDistance) - coverage(edgeDistance + borderWidth), 0.0));
    vec4 content = texture(source, qt_TexCoord0);

    // Compose both inside one coverage value. Drawing an antialiased border
    // over an already antialiased mask otherwise darkens the attachment tips.
    fragColor = (content * (fillCoverage - borderColor.a * borderCoverage)
        + borderColor * borderCoverage) * qt_Opacity;
}
