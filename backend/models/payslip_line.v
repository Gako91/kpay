module models

// PayslipLine est une retenue figée sur un bulletin au moment du calcul de paie :
// cotisation salariale ou patronale, impôt (IS, CN, IGR). Le PDF et les
// déclarations (DASC, État 301) lisent ces lignes au lieu de recalculer : le
// détail reste celui qui a produit le net, même si le contrat ou les règles changent.
@[table: 'payslip_line']
pub struct PayslipLine {
pub:
	id              int @[primary; sql: serial]
	organization_id int
	payslip_id      int
	position        int // ordre d'affichage
	code            string // ex: 'CNPS_RET', 'IS', 'IGR'
	label           string
	share           string // 'salarial' | 'patronal'
	base            i64    // assiette (FCFA ; 0 = forfait)
	rate            f64    // taux décimal (0 = forfait ou barème)
	amount          i64
}
