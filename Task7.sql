WITH squad_stats AS (
    SELECT 
	    ms.squad_id,
		ms.name AS squad_name,
		ms.formation_type,
		d.name AS leader_name
	FROM military_squads ms
	LEFT JOIN dwarves d ON d.dwarf_id = ms.leader_id
	GROUP BY ms.squad_id, d.name
),
    squad_battle_stats AS (
    SELECT
	    sb.squad_id,
	    COUNT(sb.report_id) AS total_battles,
		COUNT(CASE WHEN sb.outcome = 'victory' THEN sb.report_id END) AS victories,
		SUM(sb.casualties) AS total_casualties,
		SUM(sb.enemy_casualties) AS total_enemy_casualties
	FROM squad_battles sb
	GROUP BY sb.squad_id
),
    squad_members_stats AS (
    SELECT 
	   sm.squad_id,
	   COUNT(CASE WHEN sm.exit_date IS NULL THEN sm.dwarf_id END) AS current_members,
	   COUNT(DISTINCT sm.dwarf_id) AS total_members_ever,
	   AVG(COALESCE(ds_after.level, 0) - COALESCE(ds_before.level, 0)) AS avg_combat_skill_improvement
	FROM squad_members sm
	LEFT JOIN dwarf_skills ds_before ON ds_before.dwarf_id = sm.dwarf_id
	JOIN dwarf_skills ds_after ON ds_after.dwarf_id = ds_before.dwarf_id
	          AND ds_after.skill_id = ds_before.skill_id
	WHERE ds_before.date < sm.join_date 
	      AND (ds_after.date > sm.exit_date OR sm.exit_date IS NULL)
	GROUP BY sm.squad_id
),
    squad_equipment_stats AS (
    SELECT 
	    se.squad_id,
		COALESCE(AVG(e.quality), 0) AS avg_equipment_quality
	FROM squad_equipment se
	LEFT JOIN equipment e ON e.equipment_id = se.equipment_id
	GROUP BY se.squad_id
),
    squad_training_stats AS (
    SELECT
	    st.squad_id,
		COUNT(st.schedule_id) AS total_training_sessions,
		AVG(st.effectiveness) AS avg_training_effectiveness
	FROM squad_training st
	GROUP BY st.squad_id
)
SELECT 
    ss.squad_id,
	ss.squad_name,
	ss.formation_type,
	ss.leader_name,
	sbs.total_battles,
	sbs.victories,
	COALESCE(ROUND((sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 100, 2), 0) AS victory_percentage,
	COALESCE(ROUND(sbs.total_casualties::DECIMAL / NULLIF(sms.total_members_ever, 0), 2), 0) AS casualty_rate,
	COALESCE(ROUND(sbs.total_enemy_casualties::DECIMAL / NULLIF(sbs.total_casualties, 0), 2), 0) AS casualty_exchange_ratio,
    sms.current_members,
	sms.total_members_ever,
	COALESCE(ROUND((sms.current_members::DECIMAL / NULLIF(sms.total_members_ever, 0)) * 100, 2), 0) AS retention_rate,
	ses.avg_equipment_quality,
	sts.total_training_sessions,
	sts.avg_training_effectiveness,
	CORR(COALESCE(sts.avg_training_effectiveness, 0), COALESCE(ROUND((sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 100, 2), 0)) AS training_battle_correlation,
	sms.avg_combat_skill_improvement,
	((COALESCE(ROUND((sbs.victories::DECIMAL / NULLIF(sbs.total_battles, 0)) * 100, 2), 0) / 100.0) * 0.33 +
    (COALESCE(ROUND(1 - sbs.total_casualties::DECIMAL / NULLIF(sms.total_members_ever, 0), 2), 0) / 100.0) * 0.33 +
	(COALESCE(ROUND((sms.current_members::DECIMAL / NULLIF(sms.total_members_ever, 0)) * 100, 2), 0) / 100.0) * 0.33 
	) AS overall_effectiveness_score,
	JSON_BUILD_OBJECT(
        'member_ids', (
            SELECT JSON_ARRAYAGG(sm.dwarf_id)
            FROM squad_members sm 
            WHERE sm.squad_id = ss.squad_id
        ),
        'equipment_ids', (
            SELECT JSON_ARRAYAGG(se.equipment_id)
            FROM squad_equipment se
            WHERE se.squad_id = ss.squad_id
        ),
        'battle_report_ids', (
            SELECT JSON_ARRAYAGG(sb.report_id)
            FROM squad_battles sb
            WHERE sb.squad_id = ss.squad_id
        ),
        'training_ids', (
            SELECT JSON_ARRAYAGG(st.schedule_id)
            FROM squad_training st
            WHERE st.squad_id = ss.squad_id
        )
    ) AS related_entities
FROM squad_stats ss
JOIN squad_members_stats sms ON sms.squad_id = ss.squad_id
JOIN squad_equipment_stats ses ON ses.squad_id = ss.squad_id
JOIN squad_training_stats sts ON sts.squad_id = ss.squad_id
JOIN squad_battle_stats sbs ON sbs.squad_id = ss.squad_id
GROUP BY ss.squad_id, ss.squad_name, ss.formation_type, ss.leader_name, 
sms.current_members, sms.total_members_ever, ses.avg_equipment_quality, sms.avg_combat_skill_improvement,
sts.total_training_sessions, sts.avg_training_effectiveness,
sbs.total_battles, sbs.victories, sbs.total_casualties, sbs.total_enemy_casualties
ORDER BY overall_effectiveness_score DESC;
