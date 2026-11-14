module services

import math

// ==================== CLASSEUR EXCEL 97-2003 (.xls, BIFF8) ====================
//
// Écriture minimale d'un classeur .xls à une seule feuille, sans dépendance :
// E-DISA (CNPS) n'accepte que ce format. Le fichier est un conteneur OLE2
// (Compound File Binary, secteurs de 512 octets) qui contient un unique flux
// « Workbook » au format BIFF8 :
//   - globals : BOF, CODEPAGE, WINDOW1, 4 FONT, 16 XF, STYLE, BOUNDSHEET, EOF ;
//   - feuille : BOF, DIMENSIONS, WINDOW2, cellules (LABEL / NUMBER), EOF.
// Références : [MS-XLS] et [MS-CFB].

// XlsCell est une cellule : texte, ou nombre si is_number. Une cellule texte
// vide n'est pas écrite (cellule vide dans le classeur).
pub struct XlsCell {
pub:
	text      string
	number    f64
	is_number bool
}

// xls_text construit une cellule texte.
pub fn xls_text(s string) XlsCell {
	return XlsCell{
		text: s
	}
}

// xls_number construit une cellule numérique.
pub fn xls_number(n f64) XlsCell {
	return XlsCell{
		number: n
		is_number: true
	}
}

const xls_max_rows = 65536
const xls_max_cols = 256
const xls_cell_xf = u16(15) // premier XF de cellule (0..14 = XF de style)

const cfb_sector = 512
const cfb_end_of_chain = u32(0xFFFFFFFE)
const cfb_free_sect = u32(0xFFFFFFFF)
const cfb_fat_sect = u32(0xFFFFFFFD)
const cfb_no_stream = u32(0xFFFFFFFF)
const cfb_mini_cutoff = 4096

// generate_xls produit un fichier .xls (BIFF8) contenant une feuille sans en-tête.
pub fn generate_xls(sheet_name string, rows [][]XlsCell) ![]u8 {
	if rows.len > xls_max_rows {
		return error('Trop de lignes pour un fichier .xls (${rows.len} > ${xls_max_rows})')
	}
	mut n_cols := 0
	for row in rows {
		if row.len > n_cols {
			n_cols = row.len
		}
	}
	if n_cols > xls_max_cols {
		return error('Trop de colonnes pour un fichier .xls (${n_cols})')
	}
	workbook := biff8_workbook(sheet_name, rows, n_cols)!
	return cfb_wrap_workbook(workbook)
}

// ---------- encodage little-endian ----------

fn put_u16(mut b []u8, v u16) {
	b << u8(v & 0xFF)
	b << u8(v >> 8)
}

fn put_u32(mut b []u8, v u32) {
	b << u8(v & 0xFF)
	b << u8((v >> 8) & 0xFF)
	b << u8((v >> 16) & 0xFF)
	b << u8(v >> 24)
}

fn put_f64(mut b []u8, v f64) {
	bits := math.f64_bits(v)
	for i in 0 .. 8 {
		b << u8((bits >> (8 * u64(i))) & 0xFF)
	}
}

fn set_u32(mut b []u8, pos int, v u32) {
	b[pos] = u8(v & 0xFF)
	b[pos + 1] = u8((v >> 8) & 0xFF)
	b[pos + 2] = u8((v >> 16) & 0xFF)
	b[pos + 3] = u8(v >> 24)
}

// ---------- BIFF8 ----------

// biff_record ajoute un enregistrement BIFF (type, longueur, données).
fn biff_record(mut out []u8, rec_type u16, data []u8) ! {
	if data.len > 8224 {
		return error('Enregistrement BIFF trop long (${data.len} octets)')
	}
	put_u16(mut out, rec_type)
	put_u16(mut out, u16(data.len))
	out << data
}

// latin1 convertit une chaîne UTF-8 en octets Latin-1 (chaîne BIFF « compressée »).
// Les caractères hors Latin-1 sont remplacés par '?'.
fn latin1(s string) []u8 {
	mut out := []u8{cap: s.len}
	for r in s.runes() {
		if int(r) < 256 {
			out << u8(int(r))
		} else {
			out << `?`
		}
	}
	return out
}

fn biff_bof(dt u16) []u8 {
	mut d := []u8{}
	put_u16(mut d, 0x0600) // BIFF8
	put_u16(mut d, dt) // 0x0005 globals, 0x0010 feuille
	put_u16(mut d, 0x0DBB) // build
	put_u16(mut d, 0x07CC) // année du build
	put_u32(mut d, 0) // fichier historique
	put_u32(mut d, 0x06) // version la plus ancienne pouvant lire le fichier
	return d
}

fn biff_font() []u8 {
	mut d := []u8{}
	put_u16(mut d, 200) // hauteur en 1/20 de point (10 pt)
	put_u16(mut d, 0) // attributs
	put_u16(mut d, 0x7FFF) // couleur automatique
	put_u16(mut d, 400) // graisse normale
	put_u16(mut d, 0) // exposant
	d << u8(0) // soulignement
	d << u8(0) // famille
	d << u8(0) // jeu de caractères
	d << u8(0) // réservé
	name := 'Arial'
	d << u8(name.len)
	d << u8(0) // compressé
	d << name.bytes()
	return d
}

// biff_xf construit un enregistrement XF (format de cellule) par défaut.
fn biff_xf(style bool) []u8 {
	mut d := []u8{}
	put_u16(mut d, 0) // police 0
	put_u16(mut d, 0) // format « Standard »
	put_u16(mut d, if style { u16(0xFFF5) } else { u16(0x0001) }) // verrouillé ; style => parent 0xFFF
	d << u8(0x20) // alignement : bas
	d << u8(0) // rotation
	d << u8(0) // retrait
	d << u8(if style { 0xF4 } else { 0x00 }) // attributs utilisés
	put_u32(mut d, 0) // bordures
	put_u32(mut d, 0) // bordures / couleurs
	put_u16(mut d, 0x20C0) // motif : couleurs automatiques
	return d
}

fn biff8_workbook(sheet_name string, rows [][]XlsCell, n_cols int) ![]u8 {
	// --- Globals ---
	mut g := []u8{}
	biff_record(mut g, 0x0809, biff_bof(0x0005))!
	mut cp := []u8{}
	put_u16(mut cp, 1200) // UTF-16
	biff_record(mut g, 0x0042, cp)!
	mut w1 := []u8{}
	put_u16(mut w1, 0)
	put_u16(mut w1, 0)
	put_u16(mut w1, 0x3A5C)
	put_u16(mut w1, 0x23BE)
	put_u16(mut w1, 0x0038) // onglets visibles
	put_u16(mut w1, 0) // onglet actif
	put_u16(mut w1, 0) // premier onglet affiché
	put_u16(mut w1, 1) // onglets sélectionnés
	put_u16(mut w1, 0x0258) // largeur de la barre d'onglets
	biff_record(mut g, 0x003D, w1)!
	// Excel saute l'indice de police 4 : 4 polices suffisent pour un classeur minimal.
	for _ in 0 .. 4 {
		biff_record(mut g, 0x0031, biff_font())!
	}
	for _ in 0 .. 15 {
		biff_record(mut g, 0x00E0, biff_xf(true))!
	}
	biff_record(mut g, 0x00E0, biff_xf(false))! // XF 15 : cellules
	biff_record(mut g, 0x0293, [u8(0x00), 0x80, 0x00, 0xFF])! // style « Normal » intégré
	// BOUNDSHEET : position du BOF de la feuille, complétée après coup.
	name := latin1(sheet_name)
	if name.len == 0 || name.len > 31 {
		return error('Nom de feuille invalide')
	}
	mut bs := []u8{}
	put_u32(mut bs, 0)
	put_u16(mut bs, 0) // feuille visible, type feuille de calcul
	bs << u8(name.len)
	bs << u8(0)
	bs << name
	boundsheet_pos := g.len + 4 // début des données du BOUNDSHEET
	biff_record(mut g, 0x0085, bs)!
	biff_record(mut g, 0x000A, []u8{})!
	set_u32(mut g, boundsheet_pos, u32(g.len))

	// --- Feuille ---
	mut s := []u8{}
	biff_record(mut s, 0x0809, biff_bof(0x0010))!
	mut dim := []u8{}
	put_u32(mut dim, 0)
	put_u32(mut dim, u32(rows.len))
	put_u16(mut dim, 0)
	put_u16(mut dim, u16(n_cols))
	put_u16(mut dim, 0)
	biff_record(mut s, 0x0200, dim)!
	mut w2 := []u8{}
	put_u16(mut w2, 0x06B6) // quadrillage, en-têtes, feuille sélectionnée et active
	put_u16(mut w2, 0)
	put_u16(mut w2, 0)
	put_u32(mut w2, 64) // couleur du quadrillage : automatique
	put_u16(mut w2, 0)
	put_u16(mut w2, 0)
	put_u32(mut w2, 0)
	biff_record(mut s, 0x023E, w2)!
	for r, row in rows {
		for c, cell in row {
			mut d := []u8{}
			put_u16(mut d, u16(r))
			put_u16(mut d, u16(c))
			put_u16(mut d, xls_cell_xf)
			if cell.is_number {
				put_f64(mut d, cell.number)
				biff_record(mut s, 0x0203, d)! // NUMBER
			} else {
				if cell.text.len == 0 {
					continue
				}
				txt := latin1(cell.text)
				if txt.len > 255 {
					return error('Texte trop long en ligne ${r + 1}, colonne ${c + 1}')
				}
				put_u16(mut d, u16(txt.len))
				d << u8(0) // caractères 8 bits
				d << txt
				biff_record(mut s, 0x0204, d)! // LABEL
			}
		}
	}
	biff_record(mut s, 0x000A, []u8{})!

	mut out := g.clone()
	out << s
	return out
}

// ---------- Conteneur OLE2 (CFB v3) ----------

// cfb_dir_entry construit une entrée de répertoire de 128 octets.
fn cfb_dir_entry(name string, entry_type u8, child u32, start u32, size u32) []u8 {
	mut d := []u8{len: 128}
	if entry_type == 0 {
		// Entrée inutilisée : liens à NOSTREAM, le reste à zéro.
		set_u32(mut d, 68, cfb_no_stream)
		set_u32(mut d, 72, cfb_no_stream)
		set_u32(mut d, 76, cfb_no_stream)
		return d
	}
	mut i := 0
	for ch in name.bytes() {
		d[i] = ch // noms ASCII : UTF-16LE = octet + 0
		i += 2
	}
	name_len := u16((name.len + 1) * 2) // terminateur inclus
	d[64] = u8(name_len & 0xFF)
	d[65] = u8(name_len >> 8)
	d[66] = entry_type
	d[67] = 1 // noir (arbre rouge-noir)
	set_u32(mut d, 68, cfb_no_stream) // frère gauche
	set_u32(mut d, 72, cfb_no_stream) // frère droit
	set_u32(mut d, 76, child)
	set_u32(mut d, 116, start)
	set_u32(mut d, 120, size)
	return d
}

fn cfb_wrap_workbook(workbook []u8) ![]u8 {
	// Un flux de moins de 4096 octets irait dans le mini-flux : on complète
	// par des zéros (après l'EOF BIFF, ignorés par les lecteurs).
	mut stream := workbook.clone()
	for stream.len < cfb_mini_cutoff {
		stream << u8(0)
	}
	stream_size := stream.len
	for stream.len % cfb_sector != 0 {
		stream << u8(0)
	}
	n_wb := stream.len / cfb_sector
	n_dir := 1
	mut n_fat := 1
	for (n_wb + n_dir + n_fat) > n_fat * (cfb_sector / 4) {
		n_fat++
	}
	if n_fat > 109 {
		return error('Fichier .xls trop volumineux')
	}
	dir_sector := u32(n_wb)
	fat_start := n_wb + n_dir

	// En-tête (512 octets)
	mut h := []u8{len: cfb_sector}
	sig := [u8(0xD0), 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
	for i, b in sig {
		h[i] = b
	}
	h[24] = 0x3E // version mineure
	h[26] = 0x03 // version majeure 3
	h[28] = 0xFE // ordre des octets
	h[29] = 0xFF
	h[30] = 0x09 // secteurs de 2^9 = 512 octets
	h[32] = 0x06 // mini-secteurs de 2^6 = 64 octets
	set_u32(mut h, 44, u32(n_fat))
	set_u32(mut h, 48, dir_sector)
	set_u32(mut h, 56, u32(cfb_mini_cutoff))
	set_u32(mut h, 60, cfb_end_of_chain) // pas de mini-FAT
	set_u32(mut h, 68, cfb_end_of_chain) // pas de DIFAT supplémentaire
	for i in 0 .. 109 {
		v := if i < n_fat { u32(fat_start + i) } else { cfb_free_sect }
		set_u32(mut h, 76 + i * 4, v)
	}

	// Répertoire : racine, flux Workbook, deux entrées vides
	mut dir := []u8{}
	dir << cfb_dir_entry('Root Entry', 5, 1, cfb_end_of_chain, 0)
	dir << cfb_dir_entry('Workbook', 2, cfb_no_stream, 0, u32(stream_size))
	dir << cfb_dir_entry('', 0, 0, 0, 0)
	dir << cfb_dir_entry('', 0, 0, 0, 0)

	// FAT
	mut fat := []u8{}
	for i in 0 .. n_wb {
		put_u32(mut fat, if i == n_wb - 1 { cfb_end_of_chain } else { u32(i + 1) })
	}
	put_u32(mut fat, cfb_end_of_chain) // secteur du répertoire
	for _ in 0 .. n_fat {
		put_u32(mut fat, cfb_fat_sect)
	}
	for fat.len < n_fat * cfb_sector {
		put_u32(mut fat, cfb_free_sect)
	}

	mut out := h.clone()
	out << stream
	out << dir
	out << fat
	return out
}
