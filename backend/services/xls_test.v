module services

import os

// test_generate_xls_structure vérifie la signature OLE2 et le découpage en secteurs.
fn test_generate_xls_structure() {
	rows := [
		[xls_text('012345678901'), xls_text('KOUASSI'), xls_text('Jean Marc'),
			xls_text('15/03/1990'), xls_text('01/02/2020'), xls_text(''), xls_text('M'),
			xls_number(12), xls_number(4800000)],
	]
	data := generate_xls('DISA', rows) or { panic(err) }
	assert data[0..8] == [u8(0xD0), 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
	assert data.len % 512 == 0
	out := os.getenv('KPAY_XLS_OUT')
	if out.len > 0 {
		os.write_file_array(out, data) or { panic(err) }
	}
}
