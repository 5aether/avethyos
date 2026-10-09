#version 440

// Rebuild: qsb-qt6 --qt6 --qsbversion 64 -o assets/shaders/cover-blend.frag.qsb assets/shaders/cover-blend.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float blendFraction;
};
layout(binding = 1) uniform sampler2D source;

void main()
{
    // Leave the bar's translucent background exposed at the join, then ease
    // into the cover backdrop with zero slope at both ends of the transition.
    float coverAmount = smoothstep(0.0, max(blendFraction, 0.0001), qt_TexCoord0.y);
    fragColor = texture(source, qt_TexCoord0) * coverAmount * qt_Opacity;
}
