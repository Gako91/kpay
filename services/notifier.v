module services

import time

// Niveau de log
pub enum LogLevel {
	debug
	info
	warn
	error_
}

// Log sur la console
pub fn log(level LogLevel, message string) {
	timestamp := time.now().format_ss()
	level_str := match level {
		.debug { '[DEBUG]' }
		.info { '[INFO] ' }
		.warn { '[WARN] ' }
		.error_ { '[ERROR]' }
	}
	println('${timestamp} ${level_str} ${message}')
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

// Type de notification
pub enum NotificationType {
	payslip_generated
	payment_processed
	contract_expiring
	error_occurred
}

// Notification à envoyer
pub struct Notification {
pub:
	type_      NotificationType
	recipient  string
	subject    string
	message    string
	created_at time.Time
}

// File d'attente des notifications
pub struct NotificationQueue {
mut:
	notifications []Notification
}

pub fn new_notification_queue() NotificationQueue {
	return NotificationQueue{
		notifications: []Notification{}
	}
}

pub fn (mut q NotificationQueue) push(n Notification) {
	q.notifications << n
	log_info('Notification ajoutée: ${n.subject}')
}

pub fn (mut q NotificationQueue) pop() ?Notification {
	if q.notifications.len == 0 {
		return none
	}
	n := q.notifications[0]
	q.notifications.delete(0)
	return n
}

pub fn (q NotificationQueue) count() int {
	return q.notifications.len
}

// Crée une notification pour fiche de paie générée
pub fn notify_payslip_generated(employee_email string, period string) Notification {
	return Notification{
		type_:      .payslip_generated
		recipient:  employee_email
		subject:    'Votre bulletin de paie est disponible'
		message:    'Votre bulletin de paie pour la période ${period} est maintenant disponible.'
		created_at: time.now()
	}
}

// Crée une notification pour paiement effectué
pub fn notify_payment_processed(employee_email string, payslip_id int, net_amount i64) Notification {
	amount_fmt := format_cents(net_amount)
	return Notification{
		type_:      .payment_processed
		recipient:  employee_email
		subject:    'Virement de votre salaire effectué'
		message:    'Le virement de votre bulletin #${payslip_id} d\'un montant de ${amount_fmt} a été traité.'
		created_at: time.now()
	}
}

// Dispatcher pour envoyer les notifications dépilées
pub struct NotificationDispatcher {
pub mut:
	queue NotificationQueue
	sent_count int
}

pub fn new_notification_dispatcher() NotificationDispatcher {
	return NotificationDispatcher{
		queue: new_notification_queue()
		sent_count: 0
	}
}

pub fn (mut d NotificationDispatcher) dispatch_all() int {
	mut dispatched := 0
	for {
		item := d.queue.pop() or { break }
		log_info('DEPECHE NOTIFICATION [${item.type_}] -> ${item.recipient} : "${item.subject}"')
		dispatched++
	}
	d.sent_count += dispatched
	return dispatched
}

