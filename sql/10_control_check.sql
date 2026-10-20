SELECT current_user() AS who, is_member('admins') AS in_admins;
SELECT 'ctrl_delta_plain' t, country, count(*) n FROM ${CATALOG}.xabac_ctrl.ctrl_delta_plain GROUP BY 2 ORDER BY 2;
SELECT 'ctrl_uniform' t, country, count(*) n FROM ${CATALOG}.xabac_ctrl.ctrl_uniform GROUP BY 2 ORDER BY 2;
SELECT 'ctrl_ice_rules' t, country, count(*) n FROM ${CATALOG}.xabac_ctrl.ctrl_ice_rules GROUP BY 2 ORDER BY 2;
SELECT 'ctrl_ice' t, email, iban FROM ${CATALOG}.xabac_ctrl.ctrl_ice ORDER BY customer_id LIMIT 2;
SELECT 'ctrl_ice_rules' t, email, iban FROM ${CATALOG}.xabac_ctrl.ctrl_ice_rules ORDER BY customer_id LIMIT 2;
SELECT table_name, data_source_format FROM ${CATALOG}.information_schema.tables WHERE table_schema = 'xabac_ctrl' ORDER BY 1;
