shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

varying float final_height;
varying vec2 world_pos_xz;

// --- Uniforms ---
uniform float amplitude = 10.0;
uniform float noise_frequency = 0.05;
uniform float noise_seed = 42.0;
uniform float _octaves = 4.0;
uniform float _persistence = 0.5;
uniform float _lacunarity = 2.0;

// Color Uniforms (Simple)
uniform vec4 grass_color : source_color = vec4(0.15, 0.35, 0.08, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.4, 0.2, 0.1, 1.0);


// --- Noise Functions ---

vec2 hash22(vec2 p) {
    p = mod(p, 4096.0);
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float noise2d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = dot(hash22(i + vec2(0.0, 0.0)), vec2(1.0, 0.0));
    float b = dot(hash22(i + vec2(1.0, 0.0)), vec2(1.0, 0.0));
    float c = dot(hash22(i + vec2(0.0, 1.0)), vec2(1.0, 0.0));
    float d = dot(hash22(i + vec2(1.0, 1.0)), vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float fbm(vec2 uv, float p_octaves, float frequency, float p_persistence, float p_lacunarity, float seed) {
    float total = 0.0;
    float amp = 1.0;
    float max_val = 0.0;
    vec2 seed_offset = vec2(fract(seed * 0.1234), fract(seed * 0.5678)) * 1000.0;
    vec2 coord = uv * frequency + seed_offset;
    for(int i=0; i < 4; i++) { 
        if (float(i) >= p_octaves) break;
        total += noise2d(coord) * amp; 
        max_val += amp;
        amp *= p_persistence;
        coord *= p_lacunarity;
    }
    return total / max_val; 
}

float get_height(vec2 pos) {
    float n = fbm(pos, _octaves, noise_frequency, _persistence, _lacunarity, noise_seed);
    return n * amplitude;
}

// --- Vertex Function ---
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_pos_xz = world_pos.xz;
    float height = get_height(world_pos.xz);
    
    VERTEX.y += height;
    
    final_height = height; 
}

// --- Fragment Function ---
void fragment() {
    vec2 pos_2d = world_pos_xz;
    float height_at_fragment = final_height;
    
    // Height-based Blending 
    float BLEND_START_HEIGHT = amplitude * -0.05; 
    float BLEND_END_HEIGHT = amplitude * 0.35;    
    
    float dirt_blend = smoothstep(BLEND_START_HEIGHT, BLEND_END_HEIGHT, height_at_fragment); 
    
    // Simple color mix
    vec4 final_albedo = mix(grass_color, dirt_color, dirt_blend);
    
    // Simple Roughness/Metallic
    float final_roughness = mix(0.8, 1.0, dirt_blend);
    
    // Apply default normals (from mesh)
    
    // Final Output
    ALBEDO = final_albedo.rgb;
    ROUGHNESS = final_roughness;
    METALLIC = 0.0;
}