module services

import net.s3
import common

// StorageService gère l'interaction avec MinIO / S3 via le module standard net.s3
pub struct StorageService {
pub:
	client s3.Client
	bucket string
}

// new_storage_service initialise le client S3 avec les identifiants configurés
pub fn new_storage_service(config common.Config) StorageService {
	client := s3.new_client(s3.Credentials{
		endpoint: config.minio_endpoint
		access_key_id: config.minio_access_key
		secret_access_key: config.minio_secret_key
		bucket: config.minio_bucket
	})

	return StorageService{
		client: client
		bucket: config.minio_bucket
	}
}

// upload_file dépose un fichier binaire (ex: PDF) dans le bucket MinIO
pub fn (s &StorageService) upload_file(object_name string, data []u8) !string {
	clean_obj := object_name.trim_left('/')
	mut c := s.client
	c.put(clean_obj, data)!
	return '${s.bucket}/${clean_obj}'
}

// download_file télécharge un fichier binaire depuis MinIO
pub fn (s &StorageService) download_file(object_name string) ![]u8 {
	mut clean_obj := object_name.trim_left('/')
	if clean_obj.starts_with('${s.bucket}/') {
		clean_obj = clean_obj[s.bucket.len + 1..]
	}
	mut c := s.client
	return c.get(clean_obj)!
}

// presigned_url génère une URL pré-signée pour le téléchargement direct
pub fn (s &StorageService) presigned_url(object_name string, expires_in int) !string {
	mut clean_obj := object_name.trim_left('/')
	if clean_obj.starts_with('${s.bucket}/') {
		clean_obj = clean_obj[s.bucket.len + 1..]
	}
	mut c := s.client
	return c.presign(clean_obj, expires_in: expires_in)!
}
