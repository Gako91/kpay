# Roadmap KPay — Système de Paie Haute Performance

> Vision produit découpée en 5 piliers, avec état des lieux, phasage et tâches.
> Convention : `[x]` = fait, `[ ]` = à faire. Priorité : P0 → P3.

---

## Phase 0 — Socle technique (prérequis SaaS)

Avant de construire les fonctionnalités, sécuriser le socle.

- [x] **Migration au schéma multi-tenant complet**
  - [x] Ajouter `organization_id` sur toutes les tables métier (contract, payslip, leave_request, tax_rule, audit)
  - [x] Ajouter une clause `WHERE organization_id = <tenant courant>` sur 100 % des repository
  - [x] Restreindre le seed / les routes de gestion à l'organisation active
  - [x] Endpoint d'administration : création d'organisation + utilisateur admin dédié
- [ ] **Pipeline CI/CD renforcé**
  - [ ] Build Docker + push image (GHCR), job frontend (build prod) déjà présent
  - [ ] Tests backend automatisés dans la CI (déjà en place : core/common/services)
  - [ ] Tests d'intégration avec PostgreSQL dans la CI
- [ ] **Observabilité**
  - [ ] Logs structurés JSON, tracing des requêtes (correlation id)
  - [ ] Métriques Prometheus sur `/metrics` (durées par route, erreurs, compteurs)

---

## Pilier 1 — 🏢 Espace Employé & Gestion des Congés (Self-Service & HR)

**Objectif** : un portail libre-service employé + un workflow congés à 2 niveaux.

### 1.1 Portail Libre-Service Employé (ESS)

- [x] **Consultation des bulletins (self-service)**
  - [x] Endpoint `GET /me/payslips` : liste les bulletins de l'employé connecté uniquement
  - [x] Endpoint `GET /me/payslips/:id/pdf` : téléchargement sécurisé (JWT + propriétaire vérifié)
  - [x] Page frontend « Mes bulletins » avec filtre par mois/année
- [ ] **Mise à jour des informations personnelles avec validation RH**
  - [ ] Endpoint `PUT /me/profile` : RIB, adresse, téléphone (changements mis en file d'attente)
  - [ ] Table `profile_change_request` (status : en_attente | approuve | refuse, dates de demande/validation)
  - [ ] Workflow RH : `GET /profile-changes`, `POST /profile-changes/:id/approve|reject`
  - [ ] Page frontend « Mon profil » (formulaire + historique des demandes)
  - [ ] L'anomalie RIB est reportée sur l'export SEPA tant que non validée

### 1.2 Gestion des Congés & Absences — Workflow 2 niveaux

- [ ] **Hiérarchie manager**
  - [ ] Ajout `manager_id` sur `employee` (+ bump RIB/contrat)
  - [ ] Migration : auto-rattachement manager = admin organisation par défaut
- [ ] **Workflow N+1 → RH**
  - [ ] État `en_attente` → validation N+1 (`approve_mgr`) → validation RH (`approve_rh`) → `approuve`
  - [ ] Refus possible à chaque niveau avec motif (`rejection_reason`)
  - [ ] Notifications (queue existante) à chaque étape du workflow
- [ ] **Soldes de congés**
  - [ ] Table `leave_balance` par employé/année (congé payé, RTT, maladie, sans solde)
  - [ ] Endpoint `GET /me/leave-balance`
  - [ ] Déduction automatique du solde lors de la validation RH
  - [ ] Cumul automatique en début d'année + prorata pour les nouvelles embauches
  - [ ] Afficher le solde sur le bulletin de paie (post-calcul)
- [ ] **Abandons / congés maladie**
  - [ ] Type `maladie` avec justificatif (upload PDF, limite taille/type)
  - [ ] Règles de carence et délai de déclaration configurable par organisation

---

## Pilier 2 — 🌍 Multi-Tenancy & Moteur de Règles Dynamique (SaaS & Multi-pays)

**Objectif** : isolation stricte par organisation + règles fiscales paramétrables sans recompilation.

### 2.1 Multi-Entreprises (termes de Phase 0)

- [ ] Isolation stricte : toutes les requêtes DB scoped par `organization_id` (cf. Phase 0)
- [ ] Validation : test d'isolation inter-organisations (impossible de lire/écrire les données d'une autre organisation)

### 2.2 Moteur de Règles Fiscales Configurables

- [ ] **Modèle de données**
  - [ ] Table `tax_rule` : ajout `effective_from` (date d'effet), `organization_id`, `is_active`
  - [ ] Modèle réel des cotisations : `tax_component` (retraite, maladie, AMV, AT, prestations familiales…) avec `rate`, `cap`, `basis_type` (brut/plafonne), `share` (salarial/patronal)
  - [ ] Tranches ITS/IGR : table `tax_bracket` (min, max, rate) avec vérification de non-recouvrement
- [ ] **Logique**
  - [ ] `core/tax_engine.v` : évaluation d'une fiche de paie contre les règles actives à la date de la période (pas à la date de calcul)
  - [ ] Historique : changement de loi → nouvelle règle avec `effective_from`, les périodes passées restent stables (« pour éviter de recompiler »)
- [ ] **Paramétrage & API**
  - [ ] `GET/POST/PUT /admin/tax-components`, `GET/POST/PUT /admin/tax-brackets` (admin, par organisation)
  - [ ] Comparaison avant/après d'une règle (impact sur le net)
  - [ ] Page frontend « Règles sociales » : éditeur de taux/tranches avec aperçu d'impact

---

## Pilier 3 — 🔒 Sécurité d'Entreprise & Contrôle d'Accès

**Objectif** : RBAC fin + authentification multi-facteurs et SSO.

### 3.1 RBAC Avancé

- [ ] Table `permission` + `role_permission` (granularité par action, pas seulement par rôle)
  - [ ] Rôles : Admin, Gestionnaire RH, Comptable, Manager, Employé
  - [ ] Permissions type : `payslip.read.self` / `payslip.read.all`, `leave.approve.mgr` / `leave.approve.rh`, `payroll.run`, `tax_rule.manage`, `user.manage`
- [ ] Middleware `require_permission('payroll.run')` dans le router (rendu plus souple que `has_role`)
- [ ] Administration des rôles : `GET/POST/PUT /admin/roles`, `GET/POST/PUT /admin/roles/:id/permissions`
- [ ] Page frontend « Rôles & permissions »

### 3.2 Authentification Avancée

- [ ] **MFA TOTP**
  - [ ] Enrôlement : `POST /mfa/enroll` (secret + QR code), `POST /mfa/verify` (code TOTP)
  - [ ] Login en 2 étapes : `POST /auth/login` → `challenge: 'totp'` → `POST /auth/login/mfa`
  - [ ] Code de secours (backup codes) + révocation
- [ ] **SSO OAuth2 / OIDC**
  - [ ] Dépendance V compatible OIDC (ou implémentation minimale Authorization Code + PKCE)
  - [ ] Fournisseurs : Microsoft 365, Google Workspace, Keycloak (issuer/audience/claims configurables)
  - [ ] Lien compte externe ↔ utilisateur KPay (email match strict)
  - [ ] Page frontend « Sécurité » : activer MFA, connecter un fournisseur SSO

---

## Pilier 4 — ⚡ Asynchronisme & Batch Processing

**Objectif** : paie de masse en arrière-plan + suivi temps réel.

### 4.1 File de Traitement Asynchrone

- [ ] **Table `job`** : type, payload, status (pending | running | done | failed), progress, error, timestamps
- [ ] **Queue Worker** (goroutine unique ou pool Go-backed dans le process V)
  - [ ] `POST /payroll/run` crée un job au lieu de traiter en ligne
  - [ ] Génération des bulletins en parallèle (fan-out par employé, réduction des temps pour des milliers d'employés)
  - [ ] Relance / retry avec backoff exponentiel et dead-letter
  - [ ] Scellement : si le job échoue à mi-chemin, les bulletins produits restent cohérents (transaction par lot)
- [ ] **Surveillance** : `GET /jobs/:id`, `GET /jobs` (pagination), purge des jobs terminés

### 4.2 Notifications & Suivi en Temps Réel

- [ ] **Server-Sent Events (SSE)** — plus simple que WebSocket pour un sens unique
  - [ ] Endpoint `GET /events/jobs/:id` (flux d'avancement : 0 % → 100 %, échec éventuel)
  - [ ] Broadcast sur toutes les pages frontend via `EventSource`
- [ ] **Frontend**
  - [ ] Page « Paie » : barre de progression temps réel pendant `payroll/run`
  - [ ] Toasts de notification à la fin d'un job (succès/échec)

---

## Pilier 5 — 🏛️ Déclaratifs Sociaux, Fiscaux & Paiements

**Objectif** : conformité CNPS/DGI + paiement automatisé multi-canal.

### 5.1 États Récapitulatifs & Déclarations

- [ ] **DISA (CNPS)** : export officiel (CSV/XML normé) par période
  - [ ] `POST /exports/disa` avec mois/année → fichier + version scellée en archive
- [ ] **État 301 (DGI)** : récapitulatif trimestriel des retenues ITS/IGR
  - [ ] `POST /exports/tax-301` avec trimestre/année → XML/tableur normé
- [ ] **Registre historique** : chaque export enregistré avec hash (audit trail anti-régression)

### 5.2 Intégrations Payouts (Mobile Money / Banque)

- [ ] **Abstraction `PaymentProvider`** (interface unique)
  - [ ] SEPA XML (existant) → provider `sepa`
  - [ ] Provider `momo` : Orange Money, MTN, Wave via API (sandbox d'abord)
  - [ ] Provider banque : webhooks de statut (initié, payé, rejeté)
- [ ] **Table `payout`** : montant, destinataire, provider, status, transaction_ref, timestamps
  - [ ] Webhooks entrant : `POST /webhooks/:provider` avec signature vérifiée (HMAC)
  - [ ] Reconciliation quotidienne : rapprocher les confirmations avec l'état des bulletins « payé »
- [ ] **Frontend**
  - [ ] Page « Paiements » : lancer une paie bancaire/mobile, suivi par statut, réconciliation manuelle

---

## Suivi d'avancement (récapitulatif)

| Pilier | Priorisation | Dépend de |
|---|---|---|
| Phase 0 — Socle multi-tenant complet | P0 | — |
| Pilier 1 — ESS & congés | P1 | Phase 0 (tenants), jungle relation manager |
| Pilier 2 — Moteur de règles | P1 | Phase 0 (règles scoped par org) |
| Pilier 3 — RBAC fin + MFA/SSO | P2 | Phase 0 |
| Pilier 4 — Async + SSE | P2 | Pilier 2 (détermination du net en batch) |
| Pilier 5 — Déclaratifs & paiements | P3 | Pilier 2 (taux historisés), Pilier 4 (paiement en masse) |