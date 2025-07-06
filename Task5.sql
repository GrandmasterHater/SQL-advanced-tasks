SELECT 
    e.expedition_id, 
    e.destination, 
    e.status,
    ((SELECT COUNT(em.dwarf_id) * 1.0 FROM expedition_members em
     WHERE em.expedition_id = e.expedition_id AND em.survived IS TRUE)
     / 
     (SELECT COUNT(em.dwarf_id) FROM expedition_members em
      WHERE em.expedition_id = e.expedition_id)) 
    AS survival_rate, 
    (SELECT SUM(ea.value) FROM expedition_artifacts ea
     WHERE ea.expedition_id = e.expedition_id) 
    AS artifacts_value,
    (SELECT COUNT(es.site_id) FROM expedition_sites es
     WHERE es.expedition_id = e.expedition_id) 
    AS discovered_sites,
    ((SELECT COUNT(ec.creature_id) * 1.0 FROM expedition_creatures ec
     WHERE ec.expedition_id = e.expedition_id AND ec.outcome = 'good')
     / 
     (SELECT COUNT(ec.creature_id) * 1.0 FROM expedition_creatures ec
     WHERE ec.expedition_id = e.expedition_id AND ec.outcome = 'bad')) 
    AS encounter_success_rate,
    (
    (SELECT SUM(dsReturn.experience) FROM dwarf_skills dsReturn 
     WHERE dsReturn.Dwarf_ID IN (SELECT Dwarf_ID FROM expedition_members em
                                 WHERE em.expedition_id = e.expedition_id)
           AND dsReturn.date = (SELECT TOP 1 ds.date FROM dwarf_skills ds
                                WHERE ds.dwarf_id = dsReturn.Dwarf_ID
                                      AND ds.date >= e.return_date
                                ORDER BY ds.date ASC))
     -
    (SELECT SUM(dsDeparture.experience) FROM dwarf_skills dsDeparture 
     WHERE dsDeparture.Dwarf_ID IN (SELECT Dwarf_ID FROM expedition_members em
                                    WHERE em.expedition_id = e.expedition_id)
           AND dsDeparture.date = (SELECT TOP 1 ds.date FROM dwarf_skills ds
                                   WHERE ds.dwarf_id = dsDeparture.Dwarf_ID
                                         AND ds.date >= e.departure_date
                                   ORDER BY ds.date DESC))) 
    AS skill_improvement,
    DATEDIFF(HOUR, e.departure_date, e.return_date) 
    AS expedition_duration
    --overall_success_score - не понимаю на основе каких полей его выбирать.
     JSON_OBJECT( 'member_ids', (
        SELECT JSON_ARRAYAGG(em.dwarf_id)
        FROM expedition_members em
        WHERE em.expedition_id = e.expedition_id
        ),
        'artifact_ids', (
        SELECT JSON_ARRAYAGG(ea.artifact_id)
        FROM expedition_artifacts ea
        WHERE ea.expedition_id = e.expedition_id
        ),
        'site_ids', (
        SELECT JSON_ARRAYAGG(es.site_id)
        FROM expedition_sites es
        WHERE es.expedition_id = e.expedition_id
        )
     ) 
    AS related_entities
FROM expeditions e;