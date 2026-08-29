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
- **Authentification API** : Sécurisation par clé API (header `X-Api-Key`)
- **Notifications** : Système de notification pour les événements (bulletin généré, paiement effectué)
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

# Clé API pour l'authentification (OBLIGATOIRE)
KPAY_API_KEY=votre_cle_api_secrete
```

### Prérequis

- **V language** ≥ 0.4.x ([Installation](https://vlang.io))
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

Toutes les routes (sauf `/` et `/health`) nécessitent le header :
```
X-Api-Key: votre_cle_api
```

### Endpoints

#### Info & Health
| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `GET` | `/` | Informations de l'API |
| `GET` | `/health` | Health check |

#### Employés
| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `GET` | `/employees` | Liste tous les employés actifs |
| `GET` | `/employees/:id` | Récupère un employé par ID |
| `POST` | `/employees` | Crée un nouvel employé |
| `GET` | `/contracts/:employee_id` | Récupère le contrat actif d'un employé |

#### Paie
| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `POST` | `/payroll/calculate` | Calcule la paie pour un employé (sans sauvegarder) |
| `POST` | `/payroll/run` | Génère et sauvegarde la paie mensuelle pour tous les employés |
| `GET` | `/payslips/:id` | Consulte un bulletin de paie |
| `POST` | `/payslips/:id/pay` | Marque un bulletin comme payé |

#### Exports
| Méthode | Endpoint | Description |
|---------|----------|-------------|
| `GET` | `/exports/employees/csv` | Exporte les employés en CSV |
| `GET` | `/exports/sepa` | Génère un fichier XML SEPA pour les virements |

### Exemples de Requêtes

#### Créer un employé
```bash
curl -X POST http://localhost:8080/employees \
  -H "X-Api-Key: votre_cle_api" \
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
  -H "X-Api-Key: votre_cle_api" \
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
  -H "X-Api-Key: votre_cle_api" \
  -H "Content-Type: application/json" \
  -d '{
    "month": 1,
    "year": 2026
  }'
```

## 🧪 Tests

Exécuter les tests unitaires :
```bash
v test ./core/
```

## 🔒 Sécurité

- **Clé API obligatoire** : Toutes les routes protégées vérifient le header `X-Api-Key`
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
