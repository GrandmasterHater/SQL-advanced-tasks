WITH main_battle_stats AS (
    SELECT 
	    COUNT(attack_id) AS total_recorded_attacks,
		COUNT (DISTINCT creature_id) AS unique_attackers,
		COALESCE(ROUND((COUNT(CASE WHEN outcome = 'Defeat' THEN attack_id END)::DECIMAL 
		    / NULLIF(COUNT(attack_id), 0)) * 100, 2), 0) AS overall_defense_success_rate
	FROM creature_attacks
),
active_threats AS (
    SELECT 
	    c.type AS creature_type,
		c.threat_level,
		MAX(cs.date) AS last_sighting_date,
		ct.distance_to_fortress AS territory_proximity,
		c.estimated_population AS estimated_numbers
	FROM creatures c
	JOIN creature_sightings cs ON cs.creature_id = c.creature_id
	JOIN creature_territories ct ON ct.creature_id = c.creature_id
	GROUP BY c.type, c.threat_level, ct.distance_to_fortress, c.estimated_population
),
threat_level_assessment AS (
    SELECT 
        CASE 
            WHEN AVG(at.threat_level) >= 4.5 THEN 'Critical'
            WHEN AVG(at.threat_level) >= 3.5 THEN 'High'  
            WHEN AVG(at.threat_level) >= 2.5 THEN 'Moderate'
            WHEN AVG(at.threat_level) >= 1.5 THEN 'Low'
            ELSE 'Minimal'
        END AS current_threat_level
    FROM active_threats at
),
zone_vulnerability AS (
    SELECT
	    l.zone_id,
		l.location_id,
		l.zone_type AS zone_name, 
		--vulnerability_score
		COUNT(DISTINCT CASE WHEN ca.outcome = 'Victory' THEN ca.attack_id END) AS historical_breaches,
		l.fortification_level,
		mcz.response_time_minutes AS military_response_time 
		--defense_coverage - найти через отряды которые сражались в этом месте
	FROM locations l
	JOIN creature_attacks ca ON ca.location_id = l.location_id
	JOIN military_coverage_zones mcz ON mcz.zone_id = l.zone_id
	GROUP BY l.zone_id, l.location_id, l.zone_type, l.fortification_level, mcz.response_time_minutes
),
defense_effectiveness AS (
   SELECT 
       ds.type as defense_type,
	   ROUND(((COUNT(CASE WHEN ca.outcome = 'Defeat' THEN ca.attack_id END))::DECIMAL  / NULLIF(COUNT(ca.attack_id), 0)) * 100, 2) 
	       AS effectiveness_rate,
	   AVG(ca.casualties) AS avg_enemy_casualties
   FROM defense_structures ds 
   JOIN creature_attacks ca ON ca.location_id = ds.location_id
   GROUP BY ds.type
),
squad_battle_skills AS (
    SELECT 
	    ms.squad_id,
		ms.name AS squad_name,
		COUNT(DISTINCT sm.dwarf_id) AS active_members,
		AVG(CASE WHEN s.skill_type = 'Combat' THEN ds.level END) AS avg_combat_skill,
		COUNT(DISTINCT sb.report_id) AS squad_battles,
		COUNT (DISTINCT CASE WHEN sb.outcome = 'Victory' THEN sb.report_id END) AS squad_victories
	FROM military_squads ms
	JOIN squad_members sm ON sm.squad_id = ms.squad_id AND sm.exit_date IS NULL
	JOIN dwarf_skills ds ON ds.dwarf_id = sm.dwarf_id
	JOIN skills s ON s.skill_id = ds.skill_id
	JOIN squad_battles sb ON sb.squad_id = ms.squad_id
	GROUP BY ms.squad_id, ms.name
),
security_history AS (
    SELECT 
	    EXTRACT(year FROM ca.date) AS year,
		COALESCE(ROUND((COUNT(CASE WHEN ca.outcome = 'Defeat' THEN ca.attack_id END)::DECIMAL 
		    / NULLIF(COUNT(ca.attack_id), 0)) * 100, 2), 0) AS defense_success_rate,
		COUNT(ca.attack_id) AS total_attacks,
		SUM(ca.enemy_casualties) AS casualties
	FROM creature_attacks ca
	GROUP BY year
),
security_evolution AS (
    SELECT
	    sh.year,
		LAG(sh.defense_success_rate) OVER (ORDER BY year) AS prev_defense_success_rate
	FROM security_history sh
),
seasonal_attacks AS (
    SELECT 
        EXTRACT(month FROM ca.date) AS attack_month,
        (CASE 
            WHEN EXTRACT(month FROM ca.date) IN (12, 1, 2) THEN 'Winter'
            WHEN EXTRACT(month FROM ca.date) IN (3, 4, 5) THEN 'Spring'
            WHEN EXTRACT(month FROM ca.date) IN (6, 7, 8) THEN 'Summer'
            ELSE 'Autumn'
         END) AS season,
        COUNT(ca.attack_id) AS attacks_count,
        AVG(c.threat_level) AS avg_threat_level
    FROM creature_attacks ca
    JOIN creatures c ON c.creature_id = ca.creature_id
    GROUP BY attack_month, season
)
SELECT 
    total_recorded_attacks,
	unique_attackers,
	overall_defense_success_rate,
	JSON_BUILD_OBJECT( 'threat_assessment', 
        JSON_BUILD_OBJECT(
            'current_threat_level', (SELECT current_threat_level FROM threat_level_assessment),
			'seasonal_patterns', (
                SELECT JSON_ARRAYAGG(
                    JSON_BUILD_OBJECT(
                        'season', sa.season,
                        'attack_count', sa.attacks_count,
                        'avg_threat_level', sa.avg_threat_level
                    )
                )
                FROM seasonal_attacks sa
            ),
			'active_threats', (
                SELECT
				    JSON_ARRAYAGG(
                        JSON_BUILD_OBJECT(
                            'creature_type', ath.creature_type,
							'threat_level', ath.threat_level,
							'last_sighting_date', ath.last_sighting_date,
							'territory_proximity', ath.territory_proximity,
							'estimated_numbers', ath.estimated_numbers,
							'creature_ids', (SELECT JSON_ARRAYAGG(c.creature_id)
							                 FROM creatures c 
											 WHERE c.type = ath.creature_type)
						)
					)
				FROM active_threats ath
			)
		)
	) AS security_analysis,
	(SELECT JSON_ARRAYAGG(
		JSON_BUILD_OBJECT(
                'zone_id', zv.zone_id,
				'zone_name', zv.zone_name,
			 -- 'vulnerability_score', 1, -- -- всё еще не понимаю как считать параметры "...score"
				'historical_breaches', zv.historical_breaches,
				'fortification_level', zv.fortification_level,
				'military_response_time', zv.military_response_time,
				'defense_coverage', JSON_BUILD_OBJECT(
                'structure_ids', (SELECT JSON_ARRAYAGG(ds.structure_id)
						          FROM defense_structures ds
								  WHERE ds.location_id IN (zv.location_id)),
					'squad_ids', (SELECT JSON_ARRAYAGG(squad_id)
						          FROM (SELECT DISTINCT mcz.squad_id 
										FROM military_coverage_zones mcz
										WHERE zv.zone_id IN (mcz.zone_id)))								
					)
				)
			)
	 FROM zone_vulnerability zv
	) AS vulnerability_analysis,
	(SELECT 
	    JSON_ARRAYAGG(
            JSON_BUILD_OBJECT(
                'defense_type', de.defense_type,
				'effectiveness_rate', de.effectiveness_rate,
				'avg_enemy_casualties', de.avg_enemy_casualties,
				'structure_ids', (SELECT JSON_ARRAYAGG(structure_id)
				                  FROM defense_structures ds
								  WHERE ds.type IN (de.defense_type)))) 
	 FROM defense_effectiveness de) 
	 AS defense_effectiveness,
	 (SELECT JSON_ARRAYAGG(
         JSON_BUILD_OBJECT(
             'squad_id', sbs.squad_id,
			 'squad_name', sbs.squad_name,
			 --'readiness_score', , -- всё еще не понимаю как считать параметры "...score"
			 'active_members', sbs.active_members,
			 'avg_combat_skill', sbs.avg_combat_skill,
			 'combat_effectiveness', ROUND((sbs.squad_victories::DECIMAL / NULLIF(sbs.squad_battles, 0)), 2),
			 'response_coverage', (SELECT JSON_ARRAYAGG(
			                                  JSON_BUILD_OBJECT(
                                                  'zone_id', mcz.zone_id,
												  'response_time', mcz.response_time_minutes
											  ))
								   FROM military_coverage_zones mcz
								   WHERE mcz.squad_id = sbs.squad_id)
		 )
	 ) 
	 FROM squad_battle_skills sbs) AS military_readiness_assessment,
	(SELECT JSON_ARRAYAGG(
                JSON_BUILD_OBJECT(
                    'year', sh.year, 
					'defense_success_rate', sh.defense_success_rate,
					'total_attacks', sh.total_attacks,
					'casualties', sh.casualties,
					'year_over_year_improvement', COALESCE(sh.defense_success_rate - se.prev_defense_success_rate, 0)
				)
	)
	FROM security_history sh
	LEFT JOIN security_evolution se ON sh.year = se.year) AS security_evolution
FROM main_battle_stats;
