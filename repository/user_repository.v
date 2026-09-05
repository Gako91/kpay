module repository

import models

// ==================== USERS ====================

pub fn (r &Repository) get_user_by_id(user_id int) ?models.User {
	result := sql r.db {
		select from models.User where id == user_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_user_by_username(username string) ?models.User {
	result := sql r.db {
		select from models.User where username == username limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_all_users() []models.User {
	return sql r.db {
		select from models.User
	} or { [] }
}

pub fn (mut r Repository) create_user(user models.User) !int {
	existing := sql r.db {
		select from models.User where username == user.username
	} or { [] }
	if existing.len > 0 {
		return error("Le nom d'utilisateur '${user.username}' existe déjà")
	}
	inserted_id := sql r.db {
		insert user into models.User
	}!
	return inserted_id
}
