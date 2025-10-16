shader_type spatial;

// A varying to pass the world position from the vertex to the fragment shader
varying vec3 world_position;

uniform vec4 color1 : source_color = vec4(0.0, 0.0, 0.0, 1.0); // Black
uniform vec4 color2 : source_color = vec4(1.0, 1.0, 1.0, 1.0); // White
uniform float tile_size = 1.0; // The size of one square unit in world units

void vertex() {
    // Correctly calculate the world position and pass it to the fragment shader
    // WORLD_MATRIX is implicitly available here.
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // 1. Get the world position passed from the vertex shader
    vec3 wpos = world_position;
    
    // 2. Scale the coordinates (using X and Z for a horizontal plane)
    vec2 pos = wpos.xz / tile_size;

    // 3. Use floor() to get the integer grid cell, effectively "snapping" the position
    vec2 grid_cell = floor(pos);
    
    // 4. Sum the cell coordinates and check for even/odd (the checker formula)
    float check = mod(grid_cell.x + grid_cell.y, 2.0);

    // 5. Mix the two colors based on the check value
    ALBEDO = mix(color1.rgb, color2.rgb, check);
    
    // Minimal lighting interaction
    ROUGHNESS = 0.8; 
}