module api

import strings

// Bornes (en secondes) de l'histogramme des durées de requête.
const duration_buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

struct DurationHistogram {
mut:
	counts []u64 // un compteur par borne (non cumulé)
	sum    f64
	count  u64
}

struct HttpMetricsData {
mut:
	requests  map[string]u64            // clé "method|route|status"
	durations map[string]DurationHistogram // clé "method|route"
}

// HttpMetrics agrège les compteurs HTTP au format Prometheus.
// Partagé entre les threads de veb : accès protégés par `shared`/`lock`.
pub struct HttpMetrics {
	data shared HttpMetricsData
}

pub fn new_http_metrics() &HttpMetrics {
	return &HttpMetrics{}
}

// observe enregistre une requête terminée.
fn (m &HttpMetrics) observe(method string, route string, status int, seconds f64) {
	req_key := '${method}|${route}|${status}'
	dur_key := '${method}|${route}'
	lock m.data {
		m.data.requests[req_key] = (m.data.requests[req_key] or { u64(0) }) + 1
		mut h := m.data.durations[dur_key] or {
			DurationHistogram{
				counts: []u64{len: duration_buckets.len}
			}
		}
		for i, bound in duration_buckets {
			if seconds <= bound {
				h.counts[i]++
				break
			}
		}
		h.sum += seconds
		h.count++
		m.data.durations[dur_key] = h
	}
}

// render produit les métriques HTTP au format d'exposition Prometheus (texte).
fn (m &HttpMetrics) render() string {
	mut sb := strings.new_builder(4096)
	rlock m.data {
		sb.writeln('# HELP kpay_http_requests_total Nombre de requetes HTTP traitees')
		sb.writeln('# TYPE kpay_http_requests_total counter')
		mut req_keys := m.data.requests.keys()
		req_keys.sort()
		for k in req_keys {
			parts := k.split('|')
			sb.writeln('kpay_http_requests_total{method="${parts[0]}",route="${label_escape(parts[1])}",status="${parts[2]}"} ${m.data.requests[k]}')
		}
		sb.writeln('')
		sb.writeln('# HELP kpay_http_request_duration_seconds Duree de traitement des requetes HTTP')
		sb.writeln('# TYPE kpay_http_request_duration_seconds histogram')
		mut dur_keys := m.data.durations.keys()
		dur_keys.sort()
		for k in dur_keys {
			parts := k.split('|')
			labels := 'method="${parts[0]}",route="${label_escape(parts[1])}"'
			h := m.data.durations[k] or { continue }
			mut cumulative := u64(0)
			for i, bound in duration_buckets {
				cumulative += h.counts[i]
				sb.writeln('kpay_http_request_duration_seconds_bucket{${labels},le="${bound}"} ${cumulative}')
			}
			sb.writeln('kpay_http_request_duration_seconds_bucket{${labels},le="+Inf"} ${h.count}')
			sb.writeln('kpay_http_request_duration_seconds_sum{${labels}} ${h.sum:.6f}')
			sb.writeln('kpay_http_request_duration_seconds_count{${labels}} ${h.count}')
		}
	}
	return sb.str()
}

// label_escape échappe une valeur de label Prometheus.
fn label_escape(s string) string {
	return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
}

// route_label normalise un chemin pour limiter la cardinalité des métriques :
// query string retirée, segments numériques remplacés par `:id`.
// Ex : /employees/42/contracts?x=1 → /employees/:id/contracts
fn route_label(url string) string {
	path := url.all_before('?')
	segments := path.split('/')
	mut out := []string{cap: segments.len}
	for seg in segments {
		out << if seg.len > 0 && seg.is_int() { ':id' } else { seg }
	}
	return out.join('/')
}
