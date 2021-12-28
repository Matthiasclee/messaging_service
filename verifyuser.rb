require "pstore"

users = PStore.new("users.pstore")

users.transaction do
	users[ARGV[0]][:verified] = true
	users.commit
end