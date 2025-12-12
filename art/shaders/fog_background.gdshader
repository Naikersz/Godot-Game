shader_type canvas_item;
render_mode blend_mix;

uniform float time_scale : hint_range(0.1, 2.0) = 0.5;
uniform float fog_density : hint_range(0.1, 2.0) = 0.8;
uniform vec4 fog_color : source_color = vec4(0.15, 0.10, 0.08, 1.0);
uniform vec4 fog_color_light : source_color = vec4(0.22, 0.16, 0.12, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.28, 0.20, 0.16, 1.0);
uniform float stripe_intensity : hint_range(0.0, 1.0) = 0.4;
uniform vec4 glow_color : source_color = vec4(0.40, 0.32, 0.25, 1.0);
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float glow_frequency : hint_range(0.1, 5.0) = 2.0;

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    for(int i = 0; i < 4; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV;
    vec2 st_base = uv * 3.0;
    float time = TIME * time_scale;

    // Слои с разным масштабом и скоростью (параллакс)
    float fog1 = fbm(st_base + vec2(time * 0.10, time * 0.05));           // базовый
    float fog2 = fbm(st_base * 1.6 + vec2(time * 0.17, time * 0.11));      // мелкий, быстрее
    float fog3 = fbm(st_base * 0.9 - vec2(time * 0.08, time * 0.13));      // крупный, медленный
    float fog4 = fbm(st_base * 2.3 + vec2(-time * 0.12, time * 0.07));     // дополнительная деталь
    float fog5 = fbm(st_base * 0.6 + vec2(time * 0.04, -time * 0.09));     // самый мягкий, почти статика

    // Весовая комбинация
    float combined_fog = (
        fog1 * 0.30 +
        fog2 * 0.22 +
        fog3 * 0.20 +
        fog4 * 0.18 +
        fog5 * 0.10
    ) * fog_density;
    
    // Добавляем горизонтальные полосы (ленты тумана) - более заметные
    float stripe_pattern = sin(uv.y * 6.0 + time * 0.4) * 0.5 + 0.5;
    stripe_pattern = pow(stripe_pattern, 2.0); // Делаем полосы более резкими
    stripe_pattern = smoothstep(0.2, 0.8, stripe_pattern);
    
    // Добавляем вторую систему полос с другой частотой
    float stripe_pattern2 = sin(uv.y * 4.0 - time * 0.25) * 0.5 + 0.5;
    stripe_pattern2 = pow(stripe_pattern2, 1.5);
    stripe_pattern2 = smoothstep(0.3, 0.7, stripe_pattern2);
    
    // Третья система полос - тонкие
    float stripe_pattern3 = sin(uv.y * 10.0 + time * 0.5) * 0.5 + 0.5;
    stripe_pattern3 = smoothstep(0.4, 0.6, stripe_pattern3);
    
    // Комбинируем полосы с большей видимостью
    float stripes = (stripe_pattern * 0.6 + stripe_pattern2 * 0.4 + stripe_pattern3 * 0.3) * stripe_intensity;
    
    // Добавляем градиент сверху вниз
    float vertical_gradient = 1.0 - uv.y * 0.3;
    combined_fog = combined_fog * vertical_gradient;
    
    // Смешиваем цвета тумана
    vec4 final_color = mix(fog_color, fog_color_light, combined_fog);
    
    // Добавляем полосы поверх тумана - более заметно
    final_color = mix(final_color, stripe_color, stripes);
    
    // Спорадические подсветки (мерцающие области)
    // Создаем несколько источников света с разными позициями и частотами
    vec2 light_pos1 = vec2(0.3, 0.4);
    vec2 light_pos2 = vec2(0.7, 0.6);
    vec2 light_pos3 = vec2(0.5, 0.2);
    vec2 light_pos4 = vec2(0.2, 0.8);
    vec2 light_pos5 = vec2(0.8, 0.3);
    
    // Время с разными частотами для каждого источника
    float light_time1 = time * glow_frequency * 0.7;
    float light_time2 = time * glow_frequency * 0.9;
    float light_time3 = time * glow_frequency * 1.1;
    float light_time4 = time * glow_frequency * 0.8;
    float light_time5 = time * glow_frequency * 1.2;
    
    // Создаем пульсацию (синусоида с разными фазами)
    float pulse1 = sin(light_time1) * 0.5 + 0.5;
    float pulse2 = sin(light_time2 + 1.5) * 0.5 + 0.5;
    float pulse3 = sin(light_time3 + 3.0) * 0.5 + 0.5;
    float pulse4 = sin(light_time4 + 2.0) * 0.5 + 0.5;
    float pulse5 = sin(light_time5 + 4.0) * 0.5 + 0.5;
    
    // Делаем пульсацию более спорадической (не все одновременно)
    pulse1 = smoothstep(0.3, 0.9, pulse1);
    pulse2 = smoothstep(0.4, 0.8, pulse2);
    pulse3 = smoothstep(0.2, 0.7, pulse3);
    pulse4 = smoothstep(0.5, 0.9, pulse4);
    pulse5 = smoothstep(0.3, 0.8, pulse5);
    
    // Расстояние от каждого источника света
    float dist1 = distance(uv, light_pos1);
    float dist2 = distance(uv, light_pos2);
    float dist3 = distance(uv, light_pos3);
    float dist4 = distance(uv, light_pos4);
    float dist5 = distance(uv, light_pos5);
    
    // Радиус свечения для каждого источника
    float radius = 0.25;
    float glow1 = (1.0 - smoothstep(0.0, radius, dist1)) * pulse1;
    float glow2 = (1.0 - smoothstep(0.0, radius, dist2)) * pulse2;
    float glow3 = (1.0 - smoothstep(0.0, radius, dist3)) * pulse3;
    float glow4 = (1.0 - smoothstep(0.0, radius, dist4)) * pulse4;
    float glow5 = (1.0 - smoothstep(0.0, radius, dist5)) * pulse5;
    
    // Комбинируем все подсветки
    float total_glow = (glow1 + glow2 + glow3 + glow4 + glow5) * glow_intensity;
    
    // Добавляем подсветки к финальному цвету
    final_color = mix(final_color, glow_color, total_glow);
    
    // Добавляем небольшую вариацию цвета
    final_color.rgb += vec3(combined_fog * 0.1);
    
    COLOR = final_color;
}

