#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 shadowPosition;
    float3 worldPosition;
    float3 worldNormal;
    float2 texCoord;
};

struct ShadowVertexOut {
    float4 position [[position]];
    float depth;
};

struct ShadowUniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
};

struct LightUniforms {
    float4x4 lightViewProjectionMatrix;
    float3 lightDirection;
    float lightIntensity;
    float3 lightColor;
    float shadowBias;
    float shadowSoftness;
};

// MARK: - Shadow Map Generation

vertex ShadowVertexOut shadowMapVertex(VertexIn in [[stage_in]],
                                      constant ShadowUniforms& uniforms [[buffer(0)]]) {
    ShadowVertexOut out;
    
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.depth = out.position.z / out.position.w;
    
    return out;
}

fragment float shadowMapFragment(ShadowVertexOut in [[stage_in]]) {
    return in.depth;
}

// MARK: - Shadow Receiving

vertex VertexOut shadowReceivingVertex(VertexIn in [[stage_in]],
                                     constant ShadowUniforms& uniforms [[buffer(0)]],
                                     constant LightUniforms& lightUniforms [[buffer(1)]]) {
    VertexOut out;
    
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPosition.xyz;
    out.worldNormal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.texCoord = in.texCoord;
    
    // Transform to light space for shadow mapping
    out.shadowPosition = lightUniforms.lightViewProjectionMatrix * worldPosition;
    
    return out;
}

fragment float4 shadowReceivingFragment(VertexOut in [[stage_in]],
                                      constant LightUniforms& lightUniforms [[buffer(0)]],
                                      texture2d<float> shadowMap [[texture(0)]],
                                      texture2d<float> baseColorTexture [[texture(1)]],
                                      sampler shadowSampler [[sampler(0)]],
                                      sampler colorSampler [[sampler(1)]]) {
    
    // Sample base color
    float4 baseColor = baseColorTexture.sample(colorSampler, in.texCoord);
    
    // Calculate shadow
    float shadow = calculateShadow(in.shadowPosition, shadowMap, shadowSampler, lightUniforms.shadowBias, lightUniforms.shadowSoftness);
    
    // Calculate lighting
    float3 lightDir = normalize(-lightUniforms.lightDirection);
    float3 normal = normalize(in.worldNormal);
    float ndotl = saturate(dot(normal, lightDir));
    
    // Combine lighting and shadow
    float3 diffuse = lightUniforms.lightColor * lightUniforms.lightIntensity * ndotl;
    float3 finalColor = baseColor.rgb * diffuse * shadow;
    
    return float4(finalColor, baseColor.a);
}

// MARK: - Shadow Calculation Functions

float calculateShadow(float4 shadowPosition,
                     texture2d<float> shadowMap,
                     sampler shadowSampler,
                     float bias,
                     float softness) {
    
    // Convert to normalized device coordinates
    float3 shadowCoord = shadowPosition.xyz / shadowPosition.w;
    shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;
    shadowCoord.y = 1.0 - shadowCoord.y; // Flip Y coordinate
    
    // Check if position is outside shadow map
    if (shadowCoord.x < 0.0 || shadowCoord.x > 1.0 ||
        shadowCoord.y < 0.0 || shadowCoord.y > 1.0 ||
        shadowCoord.z < 0.0 || shadowCoord.z > 1.0) {
        return 1.0; // No shadow
    }
    
    // Sample shadow map with PCF (Percentage Closer Filtering)
    return sampleShadowPCF(shadowMap, shadowSampler, shadowCoord, bias, softness);
}

float sampleShadowPCF(texture2d<float> shadowMap,
                     sampler shadowSampler,
                     float3 shadowCoord,
                     float bias,
                     float softness) {
    
    float shadow = 0.0;
    int samples = 16; // 4x4 PCF kernel
    float offset = softness;
    
    for (int x = -2; x <= 1; ++x) {
        for (int y = -2; y <= 1; ++y) {
            float2 sampleCoord = shadowCoord.xy + float2(x, y) * offset;
            float shadowDepth = shadowMap.sample(shadowSampler, sampleCoord).r;
            
            float currentDepth = shadowCoord.z - bias;
            shadow += (currentDepth <= shadowDepth) ? 1.0 : 0.0;
        }
    }
    
    return shadow / float(samples);
}

// MARK: - Soft Shadow Compute Shader

kernel void softShadowCompute(texture2d<float, access::read_write> shadowMap [[texture(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= shadowMap.get_width() || gid.y >= shadowMap.get_height()) {
        return;
    }
    
    // Apply Gaussian blur for soft shadows
    float result = 0.0;
    float weightSum = 0.0;
    
    int kernelSize = 3;
    float sigma = 1.0;
    
    for (int x = -kernelSize; x <= kernelSize; ++x) {
        for (int y = -kernelSize; y <= kernelSize; ++y) {
            uint2 samplePos = uint2(int2(gid) + int2(x, y));
            
            // Clamp to texture bounds
            samplePos.x = clamp(samplePos.x, 0u, shadowMap.get_width() - 1);
            samplePos.y = clamp(samplePos.y, 0u, shadowMap.get_height() - 1);
            
            float sample = shadowMap.read(samplePos).r;
            
            // Gaussian weight
            float distance = length(float2(x, y));
            float weight = exp(-(distance * distance) / (2.0 * sigma * sigma));
            
            result += sample * weight;
            weightSum += weight;
        }
    }
    
    result /= weightSum;
    shadowMap.write(float4(result), gid);
}

// MARK: - Contact Shadow Shader

kernel void contactShadowCompute(texture2d<float, access::read> depthTexture [[texture(0)]],
                                texture2d<float, access::write> contactShadowTexture [[texture(1)]],
                                constant float4x4& viewMatrix [[buffer(0)]],
                                constant float4x4& projectionMatrix [[buffer(1)]],
                                constant float3& lightDirection [[buffer(2)]],
                                uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= depthTexture.get_width() || gid.y >= depthTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(depthTexture.get_width(), depthTexture.get_height());
    float depth = depthTexture.read(gid).r;
    
    if (depth >= 1.0) {
        contactShadowTexture.write(float4(1.0), gid);
        return;
    }
    
    // Reconstruct world position from depth
    float4 ndc = float4(texCoord * 2.0 - 1.0, depth, 1.0);
    ndc.y = -ndc.y; // Flip Y
    
    float4x4 invViewProjection = inverse(projectionMatrix * viewMatrix);
    float4 worldPos = invViewProjection * ndc;
    worldPos.xyz /= worldPos.w;
    
    // Ray march in light direction
    float3 rayStart = worldPos.xyz;
    float3 rayDir = normalize(lightDirection);
    float rayLength = 0.5; // Maximum ray length
    int steps = 16;
    
    float shadow = 1.0;
    
    for (int i = 1; i <= steps; ++i) {
        float3 rayPos = rayStart + rayDir * (rayLength * float(i) / float(steps));
        
        // Project back to screen space
        float4 screenPos = projectionMatrix * viewMatrix * float4(rayPos, 1.0);
        screenPos.xyz /= screenPos.w;
        
        float2 screenUV = screenPos.xy * 0.5 + 0.5;
        screenUV.y = 1.0 - screenUV.y;
        
        if (screenUV.x < 0.0 || screenUV.x > 1.0 || screenUV.y < 0.0 || screenUV.y > 1.0) {
            break;
        }
        
        uint2 screenPixel = uint2(screenUV * float2(depthTexture.get_width(), depthTexture.get_height()));
        float sceneDepth = depthTexture.read(screenPixel).r;
        
        if (screenPos.z > sceneDepth + 0.001) {
            shadow = 0.3; // In shadow
            break;
        }
    }
    
    contactShadowTexture.write(float4(shadow), gid);
}

// MARK: - SSAO for Enhanced Shadows

kernel void ssaoCompute(texture2d<float, access::read> depthTexture [[texture(0)]],
                       texture2d<float, access::read> normalTexture [[texture(1)]],
                       texture2d<float, access::write> ssaoTexture [[texture(2)]],
                       constant float4x4& projectionMatrix [[buffer(0)]],
                       constant float& radius [[buffer(1)]],
                       constant float& bias [[buffer(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= depthTexture.get_width() || gid.y >= depthTexture.get_height()) {
        return;
    }
    
    float2 texCoord = float2(gid) / float2(depthTexture.get_width(), depthTexture.get_height());
    float depth = depthTexture.read(gid).r;
    float3 normal = normalTexture.read(gid).rgb * 2.0 - 1.0;
    
    if (depth >= 1.0) {
        ssaoTexture.write(float4(1.0), gid);
        return;
    }
    
    // Sample kernel for SSAO
    const int kernelSize = 16;
    const float3 kernel[kernelSize] = {
        float3(0.2024537, 0.841204, -0.9060141),
        float3(-0.2200423, 0.6282339, -0.8794678),
        // ... more sample points would be defined here
    };
    
    float occlusion = 0.0;
    
    for (int i = 0; i < kernelSize; ++i) {
        // Transform sample point to view space
        float3 samplePos = normal * kernel[i] * radius;
        
        // Get sample depth
        float2 sampleTexCoord = texCoord + samplePos.xy;
        
        if (sampleTexCoord.x < 0.0 || sampleTexCoord.x > 1.0 ||
            sampleTexCoord.y < 0.0 || sampleTexCoord.y > 1.0) {
            continue;
        }
        
        uint2 samplePixel = uint2(sampleTexCoord * float2(depthTexture.get_width(), depthTexture.get_height()));
        float sampleDepth = depthTexture.read(samplePixel).r;
        
        // Check occlusion
        float rangeCheck = smoothstep(0.0, 1.0, radius / abs(depth - sampleDepth));
        occlusion += (sampleDepth >= depth + bias ? 1.0 : 0.0) * rangeCheck;
    }
    
    occlusion = 1.0 - (occlusion / float(kernelSize));
    ssaoTexture.write(float4(occlusion), gid);
}

// MARK: - Utility Functions

float4x4 inverse(float4x4 m) {
    float det = determinant(m);
    if (abs(det) < 1e-6) {
        return float4x4(1.0); // Return identity if not invertible
    }
    
    return (1.0 / det) * float4x4(
        m[1][1] * m[2][2] * m[3][3] + m[1][2] * m[2][3] * m[3][1] + m[1][3] * m[2][1] * m[3][2] - m[1][1] * m[2][3] * m[3][2] - m[1][2] * m[2][1] * m[3][3] - m[1][3] * m[2][2] * m[3][1],
        -m[0][1] * m[2][2] * m[3][3] - m[0][2] * m[2][3] * m[3][1] - m[0][3] * m[2][1] * m[3][2] + m[0][1] * m[2][3] * m[3][2] + m[0][2] * m[2][1] * m[3][3] + m[0][3] * m[2][2] * m[3][1],
        m[0][1] * m[1][2] * m[3][3] + m[0][2] * m[1][3] * m[3][1] + m[0][3] * m[1][1] * m[3][2] - m[0][1] * m[1][3] * m[3][2] - m[0][2] * m[1][1] * m[3][3] - m[0][3] * m[1][2] * m[3][1],
        -m[0][1] * m[1][2] * m[2][3] - m[0][2] * m[1][3] * m[2][1] - m[0][3] * m[1][1] * m[2][2] + m[0][1] * m[1][3] * m[2][2] + m[0][2] * m[1][1] * m[2][3] + m[0][3] * m[1][2] * m[2][1],
        
        -m[1][0] * m[2][2] * m[3][3] - m[1][2] * m[2][3] * m[3][0] - m[1][3] * m[2][0] * m[3][2] + m[1][0] * m[2][3] * m[3][2] + m[1][2] * m[2][0] * m[3][3] + m[1][3] * m[2][2] * m[3][0],
        m[0][0] * m[2][2] * m[3][3] + m[0][2] * m[2][3] * m[3][0] + m[0][3] * m[2][0] * m[3][2] - m[0][0] * m[2][3] * m[3][2] - m[0][2] * m[2][0] * m[3][3] - m[0][3] * m[2][2] * m[3][0],
        -m[0][0] * m[1][2] * m[3][3] - m[0][2] * m[1][3] * m[3][0] - m[0][3] * m[1][0] * m[3][2] + m[0][0] * m[1][3] * m[3][2] + m[0][2] * m[1][0] * m[3][3] + m[0][3] * m[1][2] * m[3][0],
        m[0][0] * m[1][2] * m[2][3] + m[0][2] * m[1][3] * m[2][0] + m[0][3] * m[1][0] * m[2][2] - m[0][0] * m[1][3] * m[2][2] - m[0][2] * m[1][0] * m[2][3] - m[0][3] * m[1][2] * m[2][0],
        
        m[1][0] * m[2][1] * m[3][3] + m[1][1] * m[2][3] * m[3][0] + m[1][3] * m[2][0] * m[3][1] - m[1][0] * m[2][3] * m[3][1] - m[1][1] * m[2][0] * m[3][3] - m[1][3] * m[2][1] * m[3][0],
        -m[0][0] * m[2][1] * m[3][3] - m[0][1] * m[2][3] * m[3][0] - m[0][3] * m[2][0] * m[3][1] + m[0][0] * m[2][3] * m[3][1] + m[0][1] * m[2][0] * m[3][3] + m[0][3] * m[2][1] * m[3][0],
        m[0][0] * m[1][1] * m[3][3] + m[0][1] * m[1][3] * m[3][0] + m[0][3] * m[1][0] * m[3][1] - m[0][0] * m[1][3] * m[3][1] - m[0][1] * m[1][0] * m[3][3] - m[0][3] * m[1][1] * m[3][0],
        -m[0][0] * m[1][1] * m[2][3] - m[0][1] * m[1][3] * m[2][0] - m[0][3] * m[1][0] * m[2][1] + m[0][0] * m[1][3] * m[2][1] + m[0][1] * m[1][0] * m[2][3] + m[0][3] * m[1][1] * m[2][0],
        
        -m[1][0] * m[2][1] * m[3][2] - m[1][1] * m[2][2] * m[3][0] - m[1][2] * m[2][0] * m[3][1] + m[1][0] * m[2][2] * m[3][1] + m[1][1] * m[2][0] * m[3][2] + m[1][2] * m[2][1] * m[3][0],
        m[0][0] * m[2][1] * m[3][2] + m[0][1] * m[2][2] * m[3][0] + m[0][2] * m[2][0] * m[3][1] - m[0][0] * m[2][2] * m[3][1] - m[0][1] * m[2][0] * m[3][2] - m[0][2] * m[2][1] * m[3][0],
        -m[0][0] * m[1][1] * m[3][2] - m[0][1] * m[1][2] * m[3][0] - m[0][2] * m[1][0] * m[3][1] + m[0][0] * m[1][2] * m[3][1] + m[0][1] * m[1][0] * m[3][2] + m[0][2] * m[1][1] * m[3][0],
        m[0][0] * m[1][1] * m[2][2] + m[0][1] * m[1][2] * m[2][0] + m[0][2] * m[1][0] * m[2][1] - m[0][0] * m[1][2] * m[2][1] - m[0][1] * m[1][0] * m[2][2] - m[0][2] * m[1][1] * m[2][0]
    );
}

float determinant(float4x4 m) {
    return m[0][0] * (m[1][1] * (m[2][2] * m[3][3] - m[2][3] * m[3][2]) - m[1][2] * (m[2][1] * m[3][3] - m[2][3] * m[3][1]) + m[1][3] * (m[2][1] * m[3][2] - m[2][2] * m[3][1]))
         - m[0][1] * (m[1][0] * (m[2][2] * m[3][3] - m[2][3] * m[3][2]) - m[1][2] * (m[2][0] * m[3][3] - m[2][3] * m[3][0]) + m[1][3] * (m[2][0] * m[3][2] - m[2][2] * m[3][0]))
         + m[0][2] * (m[1][0] * (m[2][1] * m[3][3] - m[2][3] * m[3][1]) - m[1][1] * (m[2][0] * m[3][3] - m[2][3] * m[3][0]) + m[1][3] * (m[2][0] * m[3][1] - m[2][1] * m[3][0]))
         - m[0][3] * (m[1][0] * (m[2][1] * m[3][2] - m[2][2] * m[3][1]) - m[1][1] * (m[2][0] * m[3][2] - m[2][2] * m[3][0]) + m[1][2] * (m[2][0] * m[3][1] - m[2][1] * m[3][0]));
}