# KPay - Système de Paie Haute Performance

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/your-org/kpay)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Langage](https://img.shields.io/badge/langage-V-orange.svg)](https://vlang.io/)

**KPay** est un système de paie moderne et performant développé en **V**, conçu pour gérer la paie des employés avec une architecture modulaire et évolutive.

## 🚀 Fonctionnalités

- **Gestion des employés** : CRUD complet pour les employés (création, modification, suppression logique)
- **Contrats de travail** : Gestion des contrats avec salaire de base, taux horaire et dates de début/fin
- **Calcul de paie automatique** :
  - Salaire brut avec ajustements (primes, heures supplémentaires)
  - Cotisations sociales configurables (CNPS Côte d'Ivoire par défaut)
  - Calcul du net à payer
- **Bulletins de paie** : Génération et stockage des bulletins mensuels
- **Export de données** :
  - Export CSV des employés et bulletins
  - Export XML SEPA pour les virements bancaires
- **Déclarations sociales** : DISA annuelle CNPS au format d'entrée E-DISA (.xls), registre scellé (SHA-256 + chaînage)
- **Documents OpenAPI / Swagger UI** : Spécification complète et interface interactive sur `/docs`
- **Authentification JWT** : Connexion via `POST /auth/login` (token Bearer JWT, RBAC admin / payroll_officer / accountant / employee), fallback clé API (`X-Api-Key`)
- **Dossier salarié** : contrats (avenant, clôture), primes et retenues, relevés d'heures depuis la page Employés ; la paie utilise le contrat en vigueur sur la période
- **Carence maladie** : les jours de carence (Paramètres RH) sont retenus sur la paie des arrêts maladie approuvés (salaire de base / 30 par jour)
- **Workflow d'approbation** : Bulletins brouillon → soumis → approuvé → payé ; un brouillon (y compris rejeté) peut être recalculé
- **Détail figé** : chaque retenue (code, part, assiette, taux, montant) est enregistrée avec le bulletin (`payslip_line`) ; le PDF et les déclarations lisent ce détail au lieu de recalculer
- **Journal d'audit** : Traçabilité des actions sensibles (login, paie, approbations...)
- **Notifications** : Système de notification pour les événements (bulletin généré, paiement effectué), envoi réel par SMTP
- **Pool de connexions** : PostgreSQL avec pool paramétrable (stats exposées via `/health/db`)
- **CI/CD** : Pipeline GitHub Actions (compilation, tests, build production)
- **Base de données PostgreSQL** : Persistance des données avec transactions ACID

## 📁 Architecture du Projet

```
kpay/
├── main.v                  # Point d'entrée de l'application
├── v.mod                   # Configuration du module V
├── api/                    # Routes et handlers HTTP
│   ├── router.v           # Configuration du routeur et middleware d'auth
│   ├── employee_route.v   # Routes employees
│   └── payroll_route.v    # Routes payroll et exports
├── common/                 # Utilitaires communs
│   ├── config.v           # Configuration via variables d'environnement
│   └── utils.v            # Fonctions utilitaires (formatage, validation)
├── core/                   # Logique métier principale
│   ├── calculator.v       # Moteur de calcul de paie
│   ├── formulas.v         # Formules de calcul (prorata, congés, etc.)
│   └── *_test.v           # Tests unitaires
├── data/                   # Données initiales
│   └── seed.v             # Seed des règles fiscales CNPS
├── dto/                    # Data Transfer Objects
│   ├── common.v           # Structures de requêtes/réponses
│   └── validation.v       # Validation des entrées
├── models/                 # Modèles de données
│   ├── employee.v         # Modèle Employé
│   ├── contract.v         # Modèle Contrat
│   ├── payslip.v          # Modèle Bulletin de paie
│   ├── tax_rule.v         # Modèle Règle fiscale
│   └── timesheet.v        # Modèle Feuille de temps / Ajustements
├── repository/             # Couche d'accès aux données
│   ├── base.v             # Connexion DB et transactions
│   ├── employee_repository.v
│   ├── contract_repository.v
│   ├── payslip_repository.v
│   ├── tax_rule_repository.v
│   └── timesheet_repository.v
└── services/               # Services métier
    ├── employee_service.v  # Service employés
    ├── contract.v          # Service contrats
    ├── payroll_service.v   # Service paie
    ├── exporter.v          # Génération de fichiers (CSV, XML)
    └── notifier.v          # Système de notifications et logs
```

## ⚙️ Configuration

### Variables d'environnement

Créez un fichier `.env` à la racine du projet :

```bash
# Serveur
KPAY_PORT=8080

# Base de données PostgreSQL
KPAY_DB_HOST=localhost
KPAY_DB_PORT=5432
KPAY_DB_USER=kpay
KPAY_DB_PASSWORD=votre_mot_de_passe
KPAY_DB_NAME=kpay_db

# Environnement (dev, staging, prod)
KPAY_ENV=dev

# Niveau de log (debug, info, warn, error)
KPAY_LOG_LEVEL=info
# Format des logs : text (lisible, défaut) ou json (une ligne par événement)
KPAY_LOG_FORMAT=text

# Token exigé par /metrics (Authorization: Bearer <token>) ; vide = public
KPAY_METRICS_TOKEN=

# Authentification JWT (obligatoire) — 32 caractères minimum en production
KPAY_JWT_SECRET=votre_secret_jwt_long

# Clé API (optionnelle, vide = désactivée) — droits admin sur l'organisation 1
KPAY_API_KEY=
KPAY_JWT_EXPIRATION_HOURS=24

# Pool de connexions PostgreSQL (optionnel)
KPAY_DB_POOL_MAX_OPEN=10
KPAY_DB_POOL_MAX_IDLE=2
KPAY_DB_POOL_CONN_MAX_LIFETIME=0   # secondes (0 = illimité)

# SMTP - notifications email (optionnel, false = logs console)
KPAY_SMTP_ENABLED=false
KPAY_SMTP_HOST=smtp.gmail.com
KPAY_SMTP_PORT=587
KPAY_SMTP_USERNAME=
KPAY_SMTP_PASSWORD=
KPAY_SMTP_FROM=kpay@localhost
KPAY_SMTP_SSL=false
KPAY_SMTP_STARTTLS=true
```

### Prérequis

- **V language** ≥ 0.5.x ([Installation](https://vlang.io))
- **PostgreSQL** ≥ 12.x
- **veb** : Framework web V (dépendance externe)

## 🛠️ Installation

1. **Cloner le dépôt**

   ```bash
   git clone https://github.com/your-org/kpay.git
   cd kpay
   ```

2. **Installer les dépendances**

   ```bash
   v install
   ```

3. **Configurer la base de données**

   ```sql
   CREATE DATABASE kpay_db;
   CREATE USER kpay WITH PASSWORD 'votre_mot_de_passe';
   GRANT ALL PRIVILEGES ON DATABASE kpay_db TO kpay;
   ```

4. **Définir la clé API**

   ```bash
   export KPAY_API_KEY=$(openssl rand -hex 32)
   ```

5. **Lancer l'application**
   ```bash
   v run .
   ```

## 📡 API Reference

### Authentification

La plupart des routes nécessitent un **token JWT Bearer** (obtenu via `POST /auth/login`) :

```
Authorization: Bearer <token>
```

Pour la compatibilité/intégrations, le header `X-Api-Key` reste accepté et équivaut au rôle `admin`.

Routes publiques (aucune authentification) : `/`, `/health*`, `/metrics`, `/docs`, `/openapi.yaml`, `/auth/login`, `/auth/register`.

### Endpoints

#### Info & Health

| Méthode | Endpoint  | Description           |
| ------- | --------- | --------------------- |
| `GET`   | `/`       | Informations de l'API |
| `GET`   | `/health` | Health check          |

#### Employés

| Méthode | Endpoint                  | Description                            |
| ------- | ------------------------- | -------------------------------------- |
| `GET`   | `/employees`              | Liste tous les employés actifs         |
| `GET`   | `/employees/:id`          | Récupère un employé par ID             |
| `POST`  | `/employees`              | Crée un nouvel employé                 |
| `GET`   | `/contracts/:employee_id` | Récupère le contrat actif d'un employé |

#### Paie

| Méthode | Endpoint                     | Description                                                   |
| ------- | ---------------------------- | ------------------------------------------------------------- |
| `POST`  | `/payroll/calculate`         | Calcule la paie pour un employé (sans sauvegarder)            |
| `POST`  | `/payroll/run`               | Génère et sauvegarde la paie mensuelle pour tous les employés |
| `POST`  | `/payroll/run-employee`      | Génère le bulletin d'un salarié oublié (contrat saisi après coup) |
| `GET`   | `/payroll/missing`           | Salariés sous contrat sur la période sans bulletin            |
| `PUT`   | `/contracts/:id/end`         | Clôt un contrat (un nouveau contrat clôt le précédent la veille) |
| `GET`   | `/payslips/:id`              | Consulte un bulletin de paie                                  |
| `GET`   | `/payslips/:id/pdf`          | Télécharge le bulletin au format PDF                          |
| `GET`   | `/payslips/:id/lines`        | Détail figé des retenues (code, assiette, taux, montant)      |
| `POST`  | `/payslips/:id/recalculate`  | Recalcule un bulletin en brouillon (prime tardive, rejet…)    |
| `POST`  | `/payslips/:id/submit`       | Soumet un bulletin pour approbation                           |
| `POST`  | `/payslips/:id/approve`      | Approuve un bulletin soumis                                   |
| `POST`  | `/payslips/:id/reject`       | Refuse un bulletin (retour en brouillon)                      |
| `POST`  | `/payslips/:id/pay`          | Marque un bulletin comme payé (doit être approuvé)            |

#### Audit & Supervision

| Méthode | Endpoint      | Description                              |
| ------- | ------------- | ---------------------------------------- |
| `GET`   | `/health/db`  | Statistiques du pool PostgreSQL (admin)  |
| `GET`   | `/audit-logs` | Journal d'audit paginé/filtré (admin)    |

#### Congés

| Méthode | Endpoint              | Description                                |
| ------- | --------------------- | ------------------------------------------ |
| `POST`  | `/leaves`             | Soumet une demande de congé               |
| `GET`   | `/leaves`             | Liste les demandes (`?employee_id=` filtre) |
| `PUT`   | `/leaves/:id/status`  | Approuve / refuse une demande              |

#### Exports

| Méthode | Endpoint                 | Description                                   |
| ------- | ------------------------ | --------------------------------------------- |
| `GET`   | `/exports/employees/csv` | Exporte les employés en CSV                   |
| `GET`   | `/exports/sepa?month=&year=` | Virements SEPA XML des bulletins approuvés (net à payer) |
| `GET`   | `/exports/disa/preview?year=` | Aperçu DISA : lignes E-DISA et anomalies |
| `POST`  | `/exports/disa`          | Génère et scelle le fichier E-DISA de l'année |
| `GET`   | `/exports/declarations`  | Registre des déclarations scellées            |
| `GET`   | `/exports/declarations/verify` | Vérifie le chaînage du registre         |
| `GET`   | `/exports/declarations/:id/file` | Télécharge un fichier scellé (empreinte vérifiée) |

### Exemples de Requêtes

#### Se connecter (obtention du JWT)

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "votre_mot_de_passe"}' \
  | jq -r '.token')
```

#### Créer un employé

```bash
curl -X POST http://localhost:8080/employees \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Jean",
    "last_name": "Dupont",
    "email": "jean.dupont@example.com"
  }'
```

#### Calculer la paie

```bash
curl -X POST http://localhost:8080/payroll/calculate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "employee_id": 1,
    "month": 1,
    "year": 2026
  }'
```

#### Lancer la paie mensuelle

```bash
curl -X POST http://localhost:8080/payroll/run \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "month": 1,
    "year": 2026
  }'
```

## 🧪 Tests

Tests unitaires (depuis `backend/`) :

```bash
v test core/ common/ services/ api/
```

Tests d'intégration contre un vrai PostgreSQL (ids d'insertion, transactions,
isolation multi-tenant, migrations). Ils sont ignorés sans `KPAY_TEST_DB_HOST` :

```bash
docker run -d --rm --name kpay-test-pg -p 127.0.0.1:5433:5432 \
  -e POSTGRES_USER=kpay -e POSTGRES_PASSWORD=kpay -e POSTGRES_DB=kpay_test postgres:16-alpine
KPAY_TEST_DB_HOST=127.0.0.1 KPAY_TEST_DB_PORT=5433 v test repository/
```

La CI GitHub Actions exécute les deux, puis publie l'image sur
`ghcr.io/gako91/kpay-backend` à chaque push sur `main`.

## 📈 Observabilité

- **Identifiant de requête** : chaque réponse porte un en-tête `X-Request-Id`
  (repris de la requête s'il est fourni, généré sinon). Il figure dans toutes
  les lignes de log émises pendant la requête.
- **Logs** : une ligne `http_request` par requête (méthode, chemin, statut,
  durée, organisation, utilisateur). Avec `KPAY_LOG_FORMAT=json` (activé dans
  `compose.yml`), chaque ligne est un objet JSON. Les corps de requête ne sont
  jamais journalisés.
- **Métriques Prometheus** sur `GET /metrics` :
  - `kpay_http_requests_total{method,route,status}`
  - `kpay_http_request_duration_seconds` (histogramme par méthode et route)
  - état du pool PostgreSQL (`kpay_db_*`)

  Les ids numériques des chemins sont remplacés par `:id`. Les requêtes
  refusées avant routage sont regroupées sous `route="_refused"` (401, 429)
  et `route="_preflight"` (CORS).

## 📄 Déclarations sociales (DISA)

`POST /exports/disa {"year": 2026}` produit le fichier d'entrée du logiciel **E-DISA** de la CNPS :
classeur Excel 97-2003 (`.xls`), sans ligne d'en-tête, une ligne par salarié et 9 colonnes :

| Col. | Donnée | Source KPay |
| ---- | ------ | ----------- |
| A | N° CNPS (12 chiffres) | `employee.cnps_number` |
| B | Nom (majuscules, sans caractères spéciaux) | `last_name` normalisé |
| C | Prénoms | `first_name` normalisé |
| D | Date de naissance (JJ/MM/AAAA) | `employee.birth_date` |
| E | Date d'embauche | début du premier contrat |
| F | Date de départ (vide si en poste) | fin du dernier contrat, si tous sont clos dans l'année |
| G | Périodicité M / J / H | `employee.salary_type` |
| H | Temps de travail | M : mois avec bulletin ; H : heures des relevés |
| I | Salaire brut annuel | somme des bruts des bulletins approuvés ou payés |

- **Anomalies** : `GET /exports/disa/preview` liste les données manquantes ou mal formées. L'export est refusé (422) tant qu'il reste une anomalie bloquante, y compris un bulletin de l'année encore en brouillon ou soumis. La périodicité journalière (J) n'est pas encore prise en charge : KPay ne suit pas les jours travaillés.
- **Registre scellé** : chaque export est déposé dans MinIO (`org_<id>/declarations/`) et inscrit dans `declaration_export`, avec un numéro de version, l'empreinte SHA-256 du fichier et un `chain_hash` qui le relie à l'export précédent de l'organisation. La table n'accepte que des ajouts : un trigger refuse `UPDATE` et `DELETE`. `GET /exports/declarations/verify` recalcule la chaîne et signale la première entrée modifiée ; le téléchargement vérifie l'empreinte du fichier (409 s'il a été altéré).
- **Accès** : permission `declaration.export` (gestionnaire de paie, comptable, admin). Page frontend « Déclarations sociales ».

## 🔒 Sécurité

- **Authentification** : Token JWT via `POST /auth/login`, clé API `X-Api-Key` optionnelle (désactivée par défaut, rôle admin sur l'organisation 1)
- **RBAC** : Rôles `admin`, `payroll_officer`, `accountant`, `employee` — les routes sensibles vérifient les autorisations
- **Transactions DB** : Les opérations critiques (génération de paie) utilisent des transactions pour garantir l'intégrité des données
- **Validation des entrées** : Toutes les requêtes sont validées avant traitement

## 🌍 Cotisations Sociales (CNPS - Côte d'Ivoire)

Le système inclut par défaut les cotisations CNPS ivoiriennes :

### Part Salariale

- **Retraite** : 4.12%
- **Maladie-Maternité** : 0.75%

### Part Patronale

- **Retraite** : 5.86%
- **Prestations Familiales** : 7.00%
- **AMV** : 2.60%
- **Accident du Travail** : 2.00%

Ces taux sont configurables via la table `tax_rule` en base de données.

## 📝 Licence

Ce projet est sous licence **MIT**. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

## 🤝 Contribution

Les contributions sont les bienvenues ! Veuillez suivre ces étapes :

1. Forker le projet
2. Créer une branche de fonctionnalité (`git checkout -b feature/AmazingFeature`)
3. Committer vos changements (`git commit -m 'Add some AmazingFeature'`)
4. Pusher vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrir une Pull Request

## 📞 Support

Pour toute question ou problème, veuillez ouvrir une issue sur le dépôt GitHub.

---

**Développé avec ❤️ en V Language**
