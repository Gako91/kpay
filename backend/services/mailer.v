module services

import net.smtp
import common
import time

// MailerService envoie des emails via SMTP (net.smtp).
// Seul l'hôte SMTP est requis ; username/password optionnels selon le relais.
pub struct MailerService {
pub:
	enabled  bool
	host     string
	port     int
	username string
	password string
	from     string
	ssl      bool
	starttls bool
}

// new_mailer_service construit le service mail depuis la configuration.
pub fn new_mailer_service(config common.Config) MailerService {
	return MailerService{
		enabled: config.smtp_enabled
		host: config.smtp_host
		port: config.smtp_port
		username: config.smtp_username
		password: config.smtp_password
		from: config.smtp_from
		ssl: config.smtp_ssl
		starttls: config.smtp_starttls
	}
}

// send envoie un email. Si le service est désactivé, l'opération est un no-op
// (les notifications restent journalisées sur la console).
pub fn (m &MailerService) send(to string, subject string, body string) ! {
	if !m.enabled {
		return
	}
	if m.host.len == 0 {
		return error('SMTP désactivé — hôte non configuré (KPAY_SMTP_HOST)')
	}

	mut client := smtp.new_client(smtp.Config{
		server: m.host
		port: m.port
		username: m.username
		password: m.password
		from: m.from
		ssl: m.ssl
		starttls: m.starttls
		timeout: 15 * time.second
	})!
	defer {
		client.quit() or {}
	}

	client.send(smtp.Mail{
		from: m.from
		to: to
		subject: subject
		body: body
		body_type: .text
	})!
	log_info('Email envoyé à ${to}: ${subject}')
}

// send_bulk envoie le même email à plusieurs destinataires.
pub fn (m &MailerService) send_bulk(to []string, subject string, body string) ! {
	for email in to {
		m.send(email, subject, body)!
	}
}
