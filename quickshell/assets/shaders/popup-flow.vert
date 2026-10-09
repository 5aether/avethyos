#version 440

// Rebuild: qsb-qt6 --qt6 --qsbversion 64 -o assets/shaders/popup-flow.vert.qsb assets/shaders/popup-flow.vert
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 flowSize;
    vec2 flowAnchor;
    float flowProgress;
    float flowStrength;
};

void main()
{
    qt_TexCoord0 = qt_MultiTexCoord0;
    float p = clamp(flowProgress, 0.0, 1.0);
    // A restrained Genie taper. The trailing edge bends toward the origin
    // during travel and returns to an exact, undeformed rectangle at rest.
    float flow = flowStrength * sin(3.14159265 * p) * (1.0 - p);
    vec2 away = qt_MultiTexCoord0 - flowAnchor;
    vec2 position = qt_Vertex.xy;
    position.x = mix(position.x, flowAnchor.x * flowSize.x,
                     flow * away.y * away.y);
    position.y = mix(position.y, flowAnchor.y * flowSize.y,
                     flow * away.x * away.x * 0.65);
    gl_Position = qt_Matrix * vec4(position, qt_Vertex.zw);
}
