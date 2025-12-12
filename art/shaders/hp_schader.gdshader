shader_type canvas_item;
render_mode blend_mix;

uniform float fill_percent : hint_range(0.0, 1.0) = 1.0;          // сколько заполнено (0–1)
uniform vec4 fill_color : source_color = vec4(1.0, 0.2, 0.2, 1.0); // основной красный
uniform vec4 flash_color : source_color = vec4(1.5, 1.8, 2.5, 1.0); // яркий белоголубой
uniform float flash_progress : hint_range(-1.0, 2.0) = -1.0;      // -1=скрыт, 0=у края, 1=прошёл
uniform float flash_width : hint_range(0.05, 0.4) = 0.15;         // ширина полоски
uniform float glow_over_edge : hint_range(0.0, 0.3) = 0.12;       // свечение за край (для урона)

void fragment() {
    vec2 uv = UV;  // UV всегда 0-1 по размеру ноды (независимо от размера бара)

    // Маска заполнения (резкая обрезка справа)
    float fill_mask = (uv.x <= fill_percent) ? 1.0 : 0.0;

    // Базовый цвет: текстура * красный * маска (вне заполнения = прозрачно)
    vec4 base = texture(TEXTURE, uv) * fill_color * fill_mask;

    // Бегущая полоска только при анимации (flash_progress >= 0)
    float flash_core = 0.0;
    float edge_glow = 0.0;
    
    if (flash_progress >= 0.0) {
        // Позиция вспышки: начинается от края заполнения и движется вправо
        // flash_progress: 0 = у края fill_percent, 1 = прошла до конца
        float flash_pos = fill_percent + flash_progress * (1.0 - fill_percent);
        
        // Яркая полоска (волна) - движется от края заполнения
        flash_core = smoothstep(flash_pos - flash_width, flash_pos, uv.x)
                   * smoothstep(flash_pos + flash_width, flash_pos, uv.x);
        
        // Свечение за обрезанным краем (для эффекта урона при уменьшении)
        if (flash_progress > 0.0) {
            float glow_left = flash_pos - glow_over_edge;
            edge_glow = smoothstep(glow_left, fill_percent, uv.x) * (1.0 - fill_mask);
        }
    }

    // Финальный цвет: база + волна поверх (только при анимации)
    COLOR = base;
    if (flash_progress >= 0.0) {
        // Волна использует цвет текстуры, но делает его ярче
        vec4 texture_color = texture(TEXTURE, uv) * fill_color;
        vec4 wave_color = texture_color * 1.5; // Делаем цвет текстуры ярче для волны
        COLOR = mix(COLOR, wave_color, flash_core * 0.8);
        // Свечение за краем использует цвет текстуры
        COLOR += edge_glow * texture_color * 0.6;
    }

    // Альфа: максимум от базы и вспышки
    COLOR.a = max(base.a, max(flash_core * 0.9, edge_glow * 0.6));
}