module data

import models
import repository

// Seed des données initiales via le Repository
pub fn seed_data(mut repo repository.Repository) ! {
	// Vérifier si des règles fiscales existent déjà
	existing_rules := repo.get_all_tax_rules()
	if existing_rules.len > 0 {
		return
	}

	// Ajout de cotisations CNPS de base (Côte d'Ivoire)
	rules := [
		models.TaxRule{
			name: 'CNPS Retraite (part salariale)'
			rate: 0.0412
			is_employer: false
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Maladie-Maternité (part salariale)'
			rate: 0.0075
			is_employer: false
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Retraite (part patronale)'
			rate: 0.0586
			is_employer: true
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Prestations Familiales (part patronale)'
			rate: 0.07
			is_employer: true
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS AMV (part patronale)'
			rate: 0.026
			is_employer: true
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Accident du Travail (part patronale)'
			rate: 0.02
			is_employer: true
			country: 'CI'
		},
	]

	for rule in rules {
		repo.create_tax_rule(rule)!
	}
}
