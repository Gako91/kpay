module services

import core

fn test_payslip_lines_roundtrip() {
	sal := [core.TaxLine{
		name: 'CNPS Retraite'
		amount: 25200
		code: 'CNPS_RET'
		share: 'salarial'
		base: 400000
		rate: 0.063
	}, core.TaxLine{
		name: 'Ancienne règle'
		amount: 1000
	}]
	pat := [core.TaxLine{
		name: 'Prestations Familiales'
		amount: 4025
		code: 'CNPS_PF'
		share: 'patronal'
		base: 70000
		rate: 0.0575
	}]
	lines := payslip_lines(sal, pat)
	assert lines.map(it.position) == [1, 2, 3]
	assert lines.map(it.share) == ['salarial', 'salarial', 'patronal']
	assert lines[0].code == 'CNPS_RET' && lines[0].base == 400000 && lines[0].rate == 0.063
	s2, p2, total := lines_to_tax_lines(lines)
	assert s2.len == 2 && p2.len == 1
	assert total == 4025
	assert s2[0].amount == 25200 && p2[0].base == 70000
}
