-- Unranked priest abilities need no spell_ranks chain; preserve customized chains.
DELETE FROM `spell_ranks`
WHERE `first_spell_id` IN (948089, 949316, 949377, 949378)
  AND `spell_id` = `first_spell_id`
  AND `rank` = 1
  AND `first_spell_id` IN (
    SELECT `first_spell_id` FROM (
      SELECT `first_spell_id` FROM `spell_ranks`
      GROUP BY `first_spell_id` HAVING COUNT(*) = 1
    ) AS `singletons`
  );
