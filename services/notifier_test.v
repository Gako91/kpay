module services

fn test_notification_queue_and_dispatcher() {
	mut dispatcher := new_notification_dispatcher()
	assert dispatcher.queue.count() == 0

	n1 := notify_payslip_generated('emp1@example.com', '01/2026')
	n2 := notify_payment_processed('emp2@example.com', 42, 45000000)

	dispatcher.queue.push(n1)
	dispatcher.queue.push(n2)

	assert dispatcher.queue.count() == 2

	sent := dispatcher.dispatch_all()
	assert sent == 2
	assert dispatcher.sent_count == 2
	assert dispatcher.queue.count() == 0
}
