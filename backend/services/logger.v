module services

import os
import sync
import time
import json2

// Niveau de log
pub enum LogLevel {
	debug
	info
	warn
	error_
}

// log_level_rank résout le niveau de log actif à chaque appel, sans variable
// globale (V déconseille les globals). La config est lue depuis l'environnement
// KPAY_LOG_LEVEL (info par défaut). En production, la quasi-totalité des appels
// étant filtrée avant l'émission, ce coût est négligeable devant l'I/O de log.
fn log_level_rank() int {
	env_level := os.getenv_opt('KPAY_LOG_LEVEL') or { 'info' }
	return match env_level.to_lower() {
		'debug' { 0 }
		'warn' { 2 }
		'error' { 3 }
		else { 1 }
	}
}

// log_json indique si les logs sont émis en JSON (une ligne par événement,
// KPAY_LOG_FORMAT=json) plutôt qu'en texte lisible (défaut).
fn log_json() bool {
	return (os.getenv_opt('KPAY_LOG_FORMAT') or { 'text' }).to_lower() == 'json'
}

// init_log_level configure le niveau de log minimum.
// Le niveau est lu depuis KPAY_LOG_LEVEL ; cette fonction permet de définir
// une valeur par défaut au démarrage si la variable n'est pas encore posée.
pub fn init_log_level(level string) {
	os.setenv('KPAY_LOG_LEVEL', level, true)
}

// ==================== IDENTIFIANT DE REQUÊTE ====================
//
// veb traite chaque requête de bout en bout sur un seul thread : l'identifiant
// de la requête en cours est associé au thread, ce qui permet à tous les
// log_info/log_warn des services de l'inclure sans changer leur signature.
// Les goroutines lancées par `spawn` (worker de jobs, calculs fan-out) tournent
// sur d'autres threads et n'héritent pas de l'identifiant.

struct RequestIds {
	ids shared map[u64]string
}

const request_ids = &RequestIds{}

// set_request_id associe un identifiant de requête au thread courant.
pub fn set_request_id(id string) {
	lock request_ids.ids {
		request_ids.ids[sync.thread_id()] = id
	}
}

// clear_request_id retire l'identifiant du thread courant (fin de requête).
pub fn clear_request_id() {
	lock request_ids.ids {
		request_ids.ids.delete(sync.thread_id())
	}
}

// current_request_id retourne l'identifiant de la requête du thread courant ('' hors requête).
pub fn current_request_id() string {
	rlock request_ids.ids {
		return request_ids.ids[sync.thread_id()] or { '' }
	}
	return ''
}

// ==================== ÉMISSION ====================

// LogSink sérialise l'écriture sur stdout : sans verrou, les lignes émises en
// parallèle par les threads de veb s'entremêlent (JSON invalide).
struct LogSink {
	written shared u64
}

const log_sink = &LogSink{}

fn emit(line string) {
	lock log_sink.written {
		println(line)
		log_sink.written++
	}
}

fn level_name(level LogLevel) string {
	return match level {
		.debug { 'debug' }
		.info { 'info' }
		.warn { 'warn' }
		.error_ { 'error' }
	}
}

fn rank(level LogLevel) int {
	return match level {
		.debug { 0 }
		.info { 1 }
		.warn { 2 }
		.error_ { 3 }
	}
}

// log_fields émet un événement avec des champs structurés.
// En JSON : {"ts","level","msg","request_id",...champs} sur une ligne.
// En texte : `<date> [LEVEL] [request_id] message clé=valeur...`.
pub fn log_fields(level LogLevel, message string, fields map[string]json2.Any) {
	// Filtrage par niveau : on n'émet que les messages >= niveau configuré
	if rank(level) < log_level_rank() {
		return
	}
	rid := current_request_id()
	if log_json() {
		mut ev := map[string]json2.Any{}
		ev['ts'] = time.utc().format_rfc3339()
		ev['level'] = level_name(level)
		ev['msg'] = message
		if rid.len > 0 {
			ev['request_id'] = rid
		}
		for k, v in fields {
			ev[k] = v
		}
		emit(json2.encode(ev))
		return
	}
	mut line := '${time.now().format_ss()} [${level_name(level).to_upper()}]'
	if level == .info || level == .warn {
		line += ' '
	}
	if rid.len > 0 {
		line += ' [${rid}]'
	}
	line += ' ${message}'
	for k, v in fields {
		line += ' ${k}=${v.str()}'
	}
	emit(line)
}

// Log sur la console
pub fn log(level LogLevel, message string) {
	log_fields(level, message, map[string]json2.Any{})
}

pub fn log_debug(message string) {
	log(.debug, message)
}

pub fn log_info(message string) {
	log(.info, message)
}

pub fn log_warn(message string) {
	log(.warn, message)
}

pub fn log_error(message string) {
	log(.error_, message)
}
