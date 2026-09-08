-- Seed par défaut : barème CNPS / DGI Côte d'Ivoire pour l'organisation 1.
-- Valeurs correspondant au référentiel légal ivoirien (lois en vigueur au 2026-01-01) :
--   Retraite 6.3% salarial / 7.7% patronal (plafond 45 SMIG = 3 375 000 FCFA/mois)
--   Prestations Familiales 5.75% et AT 2% (plafond 70 000 FCFA/mois)
--   Régime Complémentaire 1.2% (plafond 45 SMIG)
--   CMU 1 000 FCFA forfaitaire ; IS 1.2% sur 80% du brut ; CN & IGR via tranches.

INSERT INTO taxcomponent (id, organization_id, code, name, rate, basis_type, cap, fixed_amount, share, effective_from, is_active, country) VALUES
    (1, 1, 'CNPS_RET',   'CNPS Retraite',              0.0630, 'plafonne', 3375000, 0,    'salarial', '2026-01-01', TRUE, 'CI'),
    (2, 1, 'CNPS_RET_E', 'CNPS Retraite (patronale)',  0.0770, 'plafonne', 3375000, 0,    'patronal', '2026-01-01', TRUE, 'CI'),
    (3, 1, 'CMU',        'CMU Salarié',                0.0,    'forfait',  0,      1000, 'salarial', '2026-01-01', TRUE, 'CI'),
    (4, 1, 'CNPS_PF',    'Prestations Familiales',     0.0575, 'plafonne', 70000,  0,    'patronal', '2026-01-01', TRUE, 'CI'),
    (5, 1, 'CNPS_AT',    'Accident du Travail',        0.0200, 'plafonne', 70000,  0,    'patronal', '2026-01-01', TRUE, 'CI'),
    (6, 1, 'CNPS_RC',    'Régime Complémentaire',      0.0120, 'plafonne', 3375000, 0,    'patronal', '2026-01-01', TRUE, 'CI'),
    (7, 1, 'IS',         'Impôt sur Salaire (IS)',     0.0120, 'brut80',   0,      0,    'salarial', '2026-01-01', TRUE, 'CI'),
    (8, 1, 'CN',         'Contribution Nationale (CN)',0.0,    'brut80',   0,      0,    'salarial', '2026-01-01', TRUE, 'CI'),
    (9, 1, 'IGR',        'Impôt Général Revenu (IGR)', 0.0,    'brut',     0,      0,    'salarial', '2026-01-01', TRUE, 'CI');

-- CN : barème sur 80% du brut. flat = lower*rate - cumul_avant.
--   0-50k : 0% | 50k-130k : 1.5% (flat 750) | 130k-200k : 5% (flat 5300) | >200k : 10% (flat 15300)
-- IGR : barème mensuel sur le quotient familial Q = 85% * (80% brut - IS - CN) / parts. flat = constante légale.
INSERT INTO taxbracket (id, organization_id, component_code, lower_bound, upper_bound, rate, flat, effective_from, is_active) VALUES
    (1,  1, 'CN',    0,       50000,  0.0,        0,     '2026-01-01', TRUE),
    (2,  1, 'CN',    50000,   130000, 0.015,      750,   '2026-01-01', TRUE),
    (3,  1, 'CN',    130000,  200000, 0.05,       5300,  '2026-01-01', TRUE),
    (4,  1, 'CN',    200000,  -1,     0.10,       15300, '2026-01-01', TRUE),
    (5,  1, 'IGR',   0,       25000,  0.0,        0,     '2026-01-01', TRUE),
    (6,  1, 'IGR',   25000,   45583,  0.0909090909, 2273, '2026-01-01', TRUE),
    (7,  1, 'IGR',   45583,   81583,  0.1304347826, 4076, '2026-01-01', TRUE),
    (8,  1, 'IGR',   81583,   126583, 0.1666666667, 7031, '2026-01-01', TRUE),
    (9,  1, 'IGR',   126583,  220583, 0.2,         11250, '2026-01-01', TRUE),
    (10, 1, 'IGR',   220583,  389583, 0.2592592593, 24306, '2026-01-01', TRUE),
    (11, 1, 'IGR',   389583,  842666, 0.3103448276, 44181, '2026-01-01', TRUE),
    (12, 1, 'IGR',   842666,  -1,     0.375,       98633, '2026-01-01', TRUE);

-- Réaligne les séquences après insertion des ids explicites ci-dessus
-- (l'ORM V insère via nextval sur la colonne id).
SELECT setval(pg_get_serial_sequence('taxcomponent', 'id'), (SELECT COALESCE(MAX(id), 1) FROM taxcomponent), true);
SELECT setval(pg_get_serial_sequence('taxbracket', 'id'), (SELECT COALESCE(MAX(id), 1) FROM taxbracket), true);