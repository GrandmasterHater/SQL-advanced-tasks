WITH workshop_stats AS (
    SELECT 
        w.workshop_id,
        w.name AS workshop_name,
        w.type AS workshop_type,
        COUNT(wc.dwarf_id) AS num_craftsdwarves,
        SUM(wp.quantity) AS total_quantity_produced,
        SUM(COALESCE(wp.quantity, 0) * COALESCE(p.value, 0)) AS total_production_value, 
        (DATEDIFF(MAX(wp.production_date), MIN(wp.production_date)) + 1) AS production_rate_days,
        SUM(wm.quantity) as total_materials_quantity
    FROM workshops w
    JOIN workshop_craftsdwarves wc ON wc.workshop_id = w.workshop_id
    JOIN workshop_products wp ON wp.workshop_id = w.workshop_id
    JOIN products p ON p.workshop_id = w.workshop_id
    JOIN workshop_materials wm ON wm.workshop_id = w.workshop_id
    GROUP BY w.workshop_id, w.name, w.type
),
  craftsdwarves_stats AS (
    SELECT 
        wc.workshop_id,
        wc.dwarf_id,
        AVG(ds.level) AS dwarf_avg_skill,
        (SUM(p.quality * p.value) / NULLIF(SUM(p.value), 0)) AS weighted_avg_quality,
        COALESCE(ROUND((CAST(COUNT(p.created_by)::DECIMAL) / (DATEDIFF(MAX(wp.production_date), MIN(wp.production_date)) + 1)), 2), 0) AS productivity
    FROM workshop_craftsdwarves wc
    JOIN dwarf_skills ds ON ds.dwarf_id = wc.dwarf_id
    JOIN products p ON wc.dwarf_id = p.created_by
    JOIN workshop_products wp ON wp.workshop_id = wc.workshop_id AND wp.product_id = p.product_id
    GROUP BY wc.workshop_id, wc.dwarf_id 
)
SELECT 
    ws.workshop_id,
    ws.workshop_name,
    ws.workshop_type,
    ws.num_craftsdwarves,
    ws.total_quantity_produced,
    ws.total_production_value,
    COALESCE(ROUND((CAST(ws.total_quantity_produced::DECIMAL) / ws.production_rate_days), 2), 0) AS daily_production_rate,
    COALESCE(ROUND((CAST(ws.total_production_value::DECIMAL) / NULLIF(ws.total_materials_quantity, 0)), 2), 0) AS value_per_material_unit,
    --workshop_utilization_percent - не понятно как считать без даты начала производства продукта, как рассчитать простои?
    COALESCE(ROUND((CAST(ws.total_materials_quantity::DECIMAL) / NULLIF(ws.total_quantity_produced, 0)), 2), 0) AS material_conversion_ratio,
    COALESCE(ROUND(AVG(cs.dwarf_avg_skill), 2), 0) AS average_craftsdwarf_skill,
    COALESCE(AVG(ROUND((CAST(cs.weighted_avg_quality::DECIMAL) / NULLIF(cs.dwarf_avg_skill, 0)), 2)), 0) AS skill_quality_correlation,
    COALESCE(AVG(cs.productivity), 0) AS average_craftsdwarf_productivity,
    JSON_OBJECT(
        'craftsdwarf_ids', (
            SELECT JSON_ARRAYAGG(wc.dwarf_id)
            FROM workshop_craftsdwarves wc 
            WHERE wc.workshop_id = ws.workshop_id
        ),
        'product_ids', (
            SELECT JSON_ARRAYAGG(p.product_id)
            FROM products p 
            WHERE p.workshop_id = ws.workshop_id
        ),
        'material_ids', (
            SELECT JSON_ARRAYAGG(wm.material_id)
            FROM (
                SELECT DISTINCT wm.material_id
                FROM workshop_materials wm
                WHERE wm.workshop_id = ws.workshop_id
            ) AS unique_materials
        ),
        'project_ids', (
            SELECT JSON_ARRAYAGG(pr.project_id)
            FROM projects pr
            WHERE pr.workshop_id = ws.workshop_id
        )
    ) AS related_entities
FROM workshop_stats ws 
LEFT JOIN craftsdwarves_stats cs ON cs.workshop_id = ws.workshop_id
GROUP BY ws.workshop_id, 
    ws.workshop_name, 
    ws.workshop_type, 
    ws.num_craftsdwarves, 
    ws.total_quantity_produced, 
    ws.total_production_value, 
    ws.production_rate_days,
    ws.total_materials_quantity;

