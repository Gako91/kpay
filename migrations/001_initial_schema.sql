-- Migration 001: Initial Schema
CREATE TABLE IF NOT EXISTS employee (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    iban TEXT DEFAULT '',
    bic TEXT DEFAULT '',
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS contract (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    base_salary BIGINT NOT NULL,
    hourly_rate BIGINT NOT NULL,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP,
    currency TEXT DEFAULT 'XOF'
);

CREATE TABLE IF NOT EXISTS tax_rule (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    rate DOUBLE PRECISION NOT NULL,
    is_employer BOOLEAN NOT NULL,
    ceiling BIGINT DEFAULT 0,
    fixed_amount BIGINT DEFAULT 0,
    country TEXT DEFAULT 'CI'
);

CREATE TABLE IF NOT EXISTS timesheet (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    month INTEGER NOT NULL,
    year INTEGER NOT NULL,
    hours_worked REAL NOT NULL DEFAULT 0,
    overtime_h REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS adjustment (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    month INTEGER NOT NULL,
    year INTEGER NOT NULL,
    amount BIGINT NOT NULL,
    description TEXT NOT NULL,
    date TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS payslip (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    period_start TIMESTAMP NOT NULL,
    period_end TIMESTAMP NOT NULL,
    gross_amount BIGINT NOT NULL,
    total_taxes BIGINT NOT NULL,
    net_amount BIGINT NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE,
    paid_at TIMESTAMP,
    pdf_path TEXT DEFAULT ''
);
