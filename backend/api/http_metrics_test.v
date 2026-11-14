module api

fn test_route_label_normalise_les_ids() {
	assert route_label('/employees/42') == '/employees/:id'
	assert route_label('/employees/42/contracts?page=2') == '/employees/:id/contracts'
	assert route_label('/events/jobs/7?token=abc') == '/events/jobs/:id'
	assert route_label('/admin/roles/manager/permissions') == '/admin/roles/manager/permissions'
	assert route_label('/') == '/'
}

fn test_valid_request_id() {
	assert valid_request_id('3f2c9a1e-7b4d-4c1a-9e8f-0a1b2c3d4e5f')
	assert valid_request_id('trace_01.abc')
	assert !valid_request_id('')
	assert !valid_request_id('a'.repeat(65))
	assert !valid_request_id('id avec espaces')
	assert !valid_request_id('injection\n{"level":"error"}')
}

fn test_metrics_render_prometheus() {
	m := new_http_metrics()
	m.observe('GET', '/employees/:id', 200, 0.003)
	m.observe('GET', '/employees/:id', 200, 0.2)
	m.observe('GET', '/employees/:id', 404, 0.001)
	m.observe('POST', '_refused', 401, 0.0005)
	out := m.render()

	assert out.contains('kpay_http_requests_total{method="GET",route="/employees/:id",status="200"} 2')
	assert out.contains('kpay_http_requests_total{method="GET",route="/employees/:id",status="404"} 1')
	assert out.contains('kpay_http_requests_total{method="POST",route="_refused",status="401"} 1')
	// Buckets cumulés : 2 requêtes <= 5 ms, 3 <= 250 ms, toutes en +Inf
	assert out.contains('kpay_http_request_duration_seconds_bucket{method="GET",route="/employees/:id",le="0.005"} 2')
	assert out.contains('kpay_http_request_duration_seconds_bucket{method="GET",route="/employees/:id",le="0.25"} 3')
	assert out.contains('kpay_http_request_duration_seconds_bucket{method="GET",route="/employees/:id",le="+Inf"} 3')
	assert out.contains('kpay_http_request_duration_seconds_count{method="GET",route="/employees/:id"} 3')
}

fn test_label_escape() {
	assert label_escape('a"b\\c') == 'a\\"b\\\\c'
}
