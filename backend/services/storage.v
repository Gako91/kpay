module services

import common
import net.http
import crypto.sha256
import time

// StorageService encapsule l'accès au stockage d'objets MinIO / S3.
// Implémentation HTTP autonome (URL pré-signées AWS SigV4) sans dépendance externe.
pub struct StorageService {
pub:
	endpoint     string // ex: http://localhost:9000
	access_key   string
	secret_key   string
	bucket       string // ex: payslips
	use_ssl      bool
}

pub fn new_storage_service(config common.Config) StorageService {
	return StorageService{
		endpoint: config.minio_endpoint
		access_key: config.minio_access_key
		secret_key: config.minio_secret_key
		bucket: config.minio_bucket
		use_ssl: config.minio_endpoint.starts_with('https://')
	}
}

// ==================== AWS SigV4 (presigned URLs) ====================

const sigv4_service = 's3'
const sigv4_region = 'us-east-1'

// hmac_sha256 calcule HMAC-SHA256 (construction standard sur bloc de 64 octets).
fn hmac_sha256(key []u8, msg []u8) []u8 {
	block_size := 64
	mut k := key.clone()
	if k.len > block_size {
		k = sha256.sum(k)
	}
	for k.len < block_size {
		k << u8(0)
	}
	mut ipad := []u8{len: block_size, init: 0x36}
	mut opad := []u8{len: block_size, init: 0x5c}
	for i in 0 .. block_size {
		ipad[i] = k[i] ^ 0x36
		opad[i] = k[i] ^ 0x5c
	}
	mut inner_input := ipad.clone()
	inner_input << msg
	inner := sha256.sum(inner_input)
	mut outer_input := opad.clone()
	outer_input << inner
	return sha256.sum(outer_input)
}

fn hex_encode(data []u8) string {
	mut out := ''
	for b in data {
		out += b.hex()
	}
	return out
}

// percent_encode encode une valeur pour une query string AWS (réservé pour '/:' ).
fn percent_encode(value string) string {
	out := value.replace('/', '%2F')
	return out
}

// iso8601_basic retourne un horodatage au format AAAA-MM-JJTHH:MM:SSZ (UTC).
fn iso8601_basic(t time.Time) string {
	return '${t.year:04d}${t.month:02d}${t.day:02d}T${t.hour:02d}${t.minute:02d}${t.second:02d}Z'
}

// sign_presigned_url construit une URL HTTP pré-signée SigV4 pour PUT/GET sur un objet.
fn (s &StorageService) sign_presigned_url(method string, object_name string, expires int) !string {
	if s.endpoint.len == 0 || s.access_key.len == 0 {
		return error('MinIO non configuré (MINIO_ENDPOINT / MINIO_ACCESS_KEY manquants)')
	}
	clean_endpoint := s.endpoint.trim_right('/')
	now := time.utc()
	amz_date := iso8601_basic(now)
	date_stamp := amz_date[0..8]

	credential := '${s.access_key}/${date_stamp}/${sigv4_region}/${sigv4_service}/aws4_request'
	host := clean_endpoint.replace('http://', '').replace('https://', '')
	canonical_uri := '/' + s.bucket + '/' + object_name

	query := 'X-Amz-Algorithm=AWS4-HMAC-SHA256' +
		'&X-Amz-Credential=${percent_encode(credential)}' +
		'&X-Amz-Date=${amz_date}' +
		'&X-Amz-Expires=${expires}' +
		'&X-Amz-SignedHeaders=host' +
		'&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD'

	canonical_request := '${method}\n${canonical_uri}\n${query}\nhost:${host}\n\nhost\nUNSIGNED-PAYLOAD'

	string_to_sign := 'AWS4-HMAC-SHA256\n${amz_date}\n${date_stamp}/${sigv4_region}/${sigv4_service}/aws4_request\n${sha256.hexhash(canonical_request)}'

	date_key := hmac_sha256(('AWS4' + s.secret_key).bytes(), date_stamp.bytes())
	region_key := hmac_sha256(date_key, sigv4_region.bytes())
	service_key := hmac_sha256(region_key, sigv4_service.bytes())
	signing_key := hmac_sha256(service_key, 'aws4_request'.bytes())
	signature := hex_encode(hmac_sha256(signing_key, string_to_sign.bytes()))

	return '${clean_endpoint}${canonical_uri}?${query}&X-Amz-Signature=${signature}'
}

// ==================== OPÉRATIONS OBJETS ====================

// upload_file dépose un fichier binaire (ex: PDF) dans le bucket MinIO.
// object_name doit être scopé par organisation (ex: 'org_2/bulletin_42.pdf').
// Retourne le nom de l'objet déposé.
pub fn (s &StorageService) upload_file(object_name string, data []u8) !string {
	presigned := s.sign_presigned_url('PUT', object_name, 900)!
	resp := http.fetch(method: .put, url: presigned, data: data.bytestr()) or {
		return error("MinIO PUT '${object_name}': ${err}")
	}
	if resp.status_code < 200 || resp.status_code >= 300 {
		return error("MinIO PUT '${object_name}': HTTP ${resp.status_code} ${resp.body}")
	}
	return object_name
}

// download_file récupère un objet binaire depuis MinIO. Retourne none si absent.
pub fn (s &StorageService) download_file(object_name string) ![]u8 {
	presigned := s.sign_presigned_url('GET', object_name, 3600)!
	resp := http.get(presigned) or {
		return error("MinIO GET '${object_name}': ${err}")
	}
	if resp.status_code == 404 {
		return error("Objet introuvable dans MinIO (${object_name})")
	}
	if resp.status_code != 200 {
		return error("MinIO GET '${object_name}': HTTP ${resp.status_code} ${resp.body}")
	}
	return resp.body.bytes()
}