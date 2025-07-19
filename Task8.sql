-- Сivilization_trade_data
WITH civilization_caravans AS (
    SELECT
	    c.fortress_id,
	    c.civilization_type,
		COUNT(DISTINCT c.caravan_id) AS total_caravans
	FROM caravans c
	GROUP BY c.fortress_id, c.civilization_type
),
    civilization_total_trade_stats AS (
    SELECT
	    c.fortress_id,
	    c.civilization_type,
		SUM(tt.value) AS total_trade_value,
		SUM(CASE WHEN tt.balance_direction = 'export' THEN tt.value ELSE -tt.value END) AS trade_balance
	FROM caravans c
	JOIN trade_transactions tt ON tt.caravan_id = c.caravan_id
	GROUP BY c.fortress_id, c.civilization_type
),
    trade_diplomacy_data AS (
    SELECT
        c.fortress_id,
        c.civilization_type,
        tt.value AS trade_value,
        CASE 
            WHEN de.outcome = 'positive' THEN 1
            WHEN de.outcome = 'negative' THEN -1
            ELSE 0
        END AS diplomacy_score
    FROM caravans c
    JOIN trade_transactions tt ON tt.caravan_id = c.caravan_id
    JOIN diplomatic_events de ON de.caravan_id = c.caravan_id
),
    diplomatic_correlation_stats AS (
    SELECT
        fortress_id,
        civilization_type,
        CORR(trade_value, diplomacy_score) AS diplomatic_correlation
    FROM trade_diplomacy_data
    GROUP BY fortress_id, civilization_type
),
    civilization_trade_data AS (
    SELECT 
	    cc.fortress_id,
	    cc.civilization_type,
		cc.total_caravans, 
		ctts.total_trade_value, 
		ctts.trade_balance,
		(CASE 
		      WHEN ctts.trade_balance > 100000 THEN 'Favorable'
			  WHEN ctts.trade_balance < -100000 THEN 'Unfavorable'
			  ELSE 'Neutral'
		 END) AS trade_relationship,
		dcs.diplomatic_correlation,
		(SELECT JSON_ARRAYAGG(c.caravan_id) FROM caravans c
		 WHERE c.fortress_id = cc.fortress_id
			   AND c.civilization_type = cc.civilization_type) AS caravan_ids
	FROM civilization_caravans cc
	LEFT JOIN civilization_total_trade_stats ctts ON ctts.fortress_id = cc.fortress_id AND ctts.civilization_type = cc.civilization_type
	JOIN diplomatic_correlation_stats dcs ON dcs.fortress_id = cc.fortress_id AND dcs.civilization_type = cc.civilization_type 
	GROUP BY cc.fortress_id, cc.civilization_type, cc.total_caravans, ctts.total_trade_value, dcs.diplomatic_correlation, ctts.trade_balance
),
    civilization_trade_data_json AS (
    SELECT 
      fortress_id,
      JSON_ARRAYAGG(
        JSON_BUILD_OBJECT(
          'civilization_type', civilization_type,
          'total_caravans', total_caravans,
          'total_trade_value', total_trade_value,
          'trade_balance', trade_balance,
          'trade_relationship', trade_relationship,
		  'diplomatic_correlation', diplomatic_correlation,
          'caravan_ids', caravan_ids
        )
      ) AS civilization_data
    FROM civilization_trade_data
    GROUP BY fortress_id
),
-- Main fortress trade stats
    main_trading_stats AS (
    SELECT 
	    ctd.fortress_id,
		COUNT(civilization_type) AS total_trading_partners,
		SUM(ctd.total_trade_value) AS all_time_trade_value,
		SUM(ctd.trade_balance) AS all_time_trade_balance
	FROM civilization_trade_data ctd
	GROUP BY ctd.fortress_id
),
-- Critical_import_dependencies
    resource_dependency AS (
    SELECT 
	    c.fortress_id,
	    cg.material_type,
		ROUND(SUM(cg.quantity) / NULLIF(COUNT(DISTINCT c.civilization_type), 0), 2) AS dependency_score,
		SUM(cg.quantity) AS total_imported,
		COUNT(DISTINCT c.civilization_type) AS import_diversity,
		JSON_ARRAYAGG(cg.goods_id) AS resource_ids
	FROM caravans c
	JOIN caravan_goods cg ON cg.caravan_id = c.caravan_id AND cg.type = 'import' 
	GROUP BY c.fortress_id, cg.material_type
),
    resource_dependency_json AS (
    SELECT 
	    rd.fortress_id,
		JSON_ARRAYAGG(
          JSON_BUILD_OBJECT(
            'material_type', rd.material_type,
            'dependency_score', rd.dependency_score,
            'total_imported', rd.total_imported,
            'import_diversity', rd.import_diversity,
            'resource_ids', rd.resource_ids
          )
        ) AS critical_import_dependencies
	FROM resource_dependency rd
	GROUP BY rd.fortress_id
),
-- Export_effectiveness
    workshop_types_and_products AS (
    SELECT 
	    w.fortress_id,
	    w.type AS workshop_type,
		p.type AS product_type,
		AVG(p.value) AS avg_value,
		SUM(wp.quantity) AS total_products_quantity
	FROM workshops w
	JOIN workshop_products wp ON wp.workshop_id = w.workshop_id
	JOIN products p ON p.product_id = wp.product_id
	GROUP BY w.fortress_id, w.type, p.type
),
    fortress_products_export_stats AS (
    SELECT 
	    c.fortress_id,
		p.type AS product_type,
		SUM(cg.quantity) AS exported_quantity,
		AVG(cg.value) as avg_sale_value
	FROM caravans c 
	JOIN caravan_goods cg ON cg.caravan_id = c.caravan_id AND cg.type = 'export'
	JOIN products p ON p.product_id = cg.original_product_id
	group by c.fortress_id, p.type
),
    export_effectiveness AS (
    SELECT 
	    wtap.fortress_id,
		wtap.product_type,
		wtap.workshop_type,
		ROUND((fpes.exported_quantity::DECIMAL / NULLIF(wtap.total_products_quantity, 0)) * 100, 1) AS export_ratio,
		ROUND(fpes.avg_sale_value / NULLIF(wtap.avg_value, 0), 2) AS avg_markup,
		JSON_ARRAYAGG(w.workshop_id) AS workshop_ids
	FROM workshop_types_and_products wtap
	JOIN fortress_products_export_stats fpes ON fpes.fortress_id = wtap.fortress_id AND fpes.product_type = wtap.product_type
	JOIN workshops w ON wtap.fortress_id = w.fortress_id AND wtap.workshop_type = w.type
	GROUP BY wtap.fortress_id, wtap.workshop_type, wtap.product_type, fpes.exported_quantity, 
	         wtap.total_products_quantity, fpes.avg_sale_value, wtap.avg_value
),
    export_effectiveness_json AS (
    SELECT 
	    ee.fortress_id,
		JSON_ARRAYAGG(
          JSON_BUILD_OBJECT(
            'workshop_type', ee.workshop_type,
            'product_type', ee.product_type,
            'export_ratio', ee.export_ratio,
            'avg_markup', ee.avg_markup,
            'workshop_ids', ee.workshop_ids
          )
        ) AS export_effectiveness_array
	FROM export_effectiveness ee
	GROUP BY ee.fortress_id
),
    trade_growth AS (
    SELECT 
	    c.fortress_id,
		EXTRACT(YEAR FROM tt.date) AS year,
		EXTRACT(QUARTER FROM tt.date) AS quarter,
		SUM(tt.value) AS quarterly_value,
		SUM(tt.value * tt.balance_direction::INTEGER) AS quarterly_balance,
		COUNT(DISTINCT c.civilization_type) AS trade_diversity
	FROM trade_transactions tt
	JOIN caravans c ON c.caravan_id = tt.caravan_id
	GROUP BY c.fortress_id, year, quarter
), 
    trade_growth_json AS (
    SELECT
      fortress_id,
      JSON_ARRAYAGG(
        JSON_BUILD_OBJECT(
          'year', year,
          'quarter', quarter,
          'quarterly_value', quarterly_value,
          'quarterly_balance', quarterly_balance,
          'trade_diversity', trade_diversity
        )
        ORDER BY year, quarter
      ) AS trade_growth
    FROM trade_growth
    GROUP BY fortress_id
)
   
SELECT
    mts.fortress_id,
	mts.total_trading_partners,
	mts.all_time_trade_value,
	mts.all_time_trade_balance,
	ctdj.civilization_data,
	rdj.critical_import_dependencies,
	eej.export_effectiveness_array AS export_effectiveness,
	tgj.trade_growth AS trade_timeline
FROM main_trading_stats mts
LEFT JOIN civilization_trade_data_json ctdj ON ctdj.fortress_id = mts.fortress_id
LEFT JOIN resource_dependency_json rdj ON rdj.fortress_id = mts.fortress_id
LEFT JOIN export_effectiveness_json eej ON eej.fortress_id = mts.fortress_id
LEFT JOIN trade_growth_json tgj ON tgj.fortress_id = mts.fortress_id;
