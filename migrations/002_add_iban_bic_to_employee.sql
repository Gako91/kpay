-- Migration 002: Ajout des colonnes IBAN / BIC sur la table employee
ALTER TABLE employee ADD COLUMN IF NOT EXISTS iban TEXT DEFAULT '';
ALTER TABLE employee ADD COLUMN IF NOT EXISTS bic TEXT DEFAULT '';
