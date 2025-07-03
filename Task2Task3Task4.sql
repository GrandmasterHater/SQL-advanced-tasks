--2.
SELECT 
    Dwarves.dwarf_id,
    Dwarves.name,
    Dwarves.age,
    Dwarves.profession,
    JSON_OBJECT( 'skill_ids', (
        SELECT JSON_ARRAYAGG(Dwarf_Skills.skill_id)
        FROM Dwarf_Skills
        WHERE Dwarf_Skills.dwarf_id = Dwarves.dwarf_id
        ),
        'assignment_ids', (
        SELECT JSON_ARRAYAGG(Dwarf_Assignments.assignment_id)
        FROM Dwarf_Assignments
        WHERE Dwarf_Assignments.dwarf_id = Dwarves.dwarf_id
        ),
        'squad_ids', (
        SELECT JSON_ARRAYAGG(Squad_Members.squad_id)
        FROM Squad_Members
        WHERE Squad_Members.dwarf_id = Dwarves.dwarf_id
        ),
        'equipment_ids', (
        SELECT JSON_ARRAYAGG(Dwarf_Equipment.equipment_id)
        FROM Dwarf_Equipment
        WHERE Dwarf_Equipment.dwarf_id = Dwarves.dwarf_id
        )
     ) AS related_entities
FROM Dwarves; 

--3.
SELECT 
    w.workshop_id,
    w.name,
    w.type,
    w.quality,
    JSON_OBJECT( 'craftsdwarf_ids', (
        SELECT JSON_ARRAYAGG(wcd.dwarf_id)
        FROM workshop_craftsdwarves wcd
        WHERE wcd.workshop_id = w.workshop_id 
        ),
        'project_ids', (
        SELECT JSON_ARRAYAGG(p.project_id)
        FROM projects p
        WHERE p.workshop_id = w.workshop_id
        ),
        'input_material_ids', (
        SELECT JSON_ARRAYAGG(wm_in.material_id)
        FROM workshop_materials wm_in
        WHERE wm_in.workshop_id = w.workshop_id AND wm_in.is_input IS TRUE
        ),
        'output_product_ids', (
        SELECT JSON_ARRAYAGG(wm_out.material_id)
        FROM workshop_materials wm_out
        WHERE wm_out.workshop_id = w.workshop_id AND wm_out.is_input IS FALSE
        )
     ) AS related_entities
FROM workshops w; 

--4.
SELECT 
    ms.squad_id,
    ms.name,
    ms.formation_type,
    ms.leader_id,
    JSON_OBJECT( 'member_ids', (
        SELECT JSON_ARRAYAGG(sm.dwarf_id)
        FROM squad_members sm
        WHERE sm.squad_id = ms.squad_id 
        ),
        'equipment_ids', (
        SELECT JSON_ARRAYAGG(se.equipment_id)
        FROM squad_equipment se
        WHERE se.squad_id = ms.squad_id 
        ),
        'operation_ids', (
        SELECT JSON_ARRAYAGG(so.operation_id)
        FROM squad_operations so
        WHERE so.squad_id = ms.squad_id 
        ),
        'training_schedule_ids', (
        SELECT JSON_ARRAYAGG(st.schedule_id)
        FROM squad_training st
        WHERE st.squad_id = ms.squad_id 
        ),
        'battle_report_ids', (
        SELECT JSON_ARRAYAGG(sb.report_id)
        FROM squad_battles sb
        WHERE sb.squad_id = ms.squad_id 
        )
     ) AS related_entities
FROM military_squads ms; 