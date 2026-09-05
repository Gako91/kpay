-- Migration 005: Module de gestion des congés et absences
CREATE TABLE IF NOT EXISTS leave_request (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL,
    leave_type TEXT NOT NULL, -- 'conge_paye', 'rtt', 'maladie', 'sans_solde'
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    days_count REAL NOT NULL,
    reason TEXT DEFAULT '',
    status TEXT DEFAULT 'en_attente', -- 'en_attente', 'approuve', 'refuse'
    approved_by TEXT DEFAULT '',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_leave_request_employee ON leave_request(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_request_status ON leave_request(status);
