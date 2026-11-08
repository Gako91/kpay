-- Migration 016: suppression de la table orpheline leave_request
--
-- La migration 005 avait créé `leave_request`, mais l'ORM V nomme la table du
-- modèle LeaveRequest `leaverequest` (sans underscore) : c'est elle que l'application
-- lit et écrit. `leave_request` n'a jamais été utilisée.
--
-- Par précaution, elle n'est supprimée que si elle est vide ; sinon on la laisse
-- en place et un avertissement est émis pour un examen manuel.
DO $$
BEGIN
    IF to_regclass('public.leave_request') IS NULL THEN
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM leave_request) THEN
        RAISE WARNING 'leave_request contient des données : table conservée, à migrer manuellement vers leaverequest';
    ELSE
        DROP TABLE leave_request;
    END IF;
END
$$;
