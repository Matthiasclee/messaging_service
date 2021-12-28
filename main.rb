require "./MLServer.rb"
require "pstore"
require "digest"
require "json"
require 'uri'
require "time"
#

$users = PStore.new("users.pstore")
$messages = PStore.new("messages.pstore")

$sessions = {}

def send_message(to, from, body)
	$messages.transaction do
		if !$messages[to][from]
			$messages[to][from] = []
		end
		if !$messages[from][to]
			$messages[from][to] = []
		end
		$messages.commit
	end
	$messages.transaction do
		$messages[to][from] << {:type => :send, :body => URI.unescape(body).gsub("<", "&#60;").gsub("+", " ")}
		$messages[from][to] << {:type => :receive, :body => URI.unescape(body).gsub("<", "&#60;").gsub("+", " ")}
		$messages.commit
	end
end
def main()
	def verified(user)
		if $users.transaction{$users[user][:verified]}
			return "✔"
		else
			return ""
		end
	end
	def path(client, params)
		if params["method"] == "GET"
			if params["path"] == "/"
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					if params["get_params"]["logout"] == "true"
						$sessions.delete(params["cookies"]["session"])
						redirect(client, "/")
					else
						session = params["cookies"]["session"]
						user = $sessions[session]
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/home.html").gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s))
					end
				else
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/index.html"))
				end
			elsif params["path"] == "/login"
				response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/login.html"))
			elsif params["path"] == "/signup"
				response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/signup.html"))
			elsif params["path"] == "/user"
				if $users.transaction{$users[params["get_params"]["user"]]}
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/about_user.html").gsub("__username__", params["get_params"]["user"]).gsub("__verified__", verified(params["get_params"]["user"])).gsub("__created_on__", Time.at($users.transaction{$users[params["get_params"]["user"]][:created_at]}).month.to_s + "-" + Time.at($users.transaction{$users[params["get_params"]["user"]][:created_at]}).day.to_s + "-" + Time.at($users.transaction{$users[params["get_params"]["user"]][:created_at]}).year.to_s).gsub("__about_me__", $users.transaction{$users[params["get_params"]["user"]][:about_me]}.to_s.gsub("\n", "<br>")).gsub("__displayname__", $users.transaction{$users[params["get_params"]["user"]][:display_name]}.to_s))
				else
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/about_user.html").gsub("__username__", "Non-Existant").gsub("__verified__", "").gsub("__created_on__", "N/A").gsub("__about_me__", "N/A").gsub("__displayname__", "N/A"))
				end
			elsif params["path"] == "/raw_user_data"
				if !$users.transaction{$users[params["get_params"]["user"]]}
					response(client, 404, ["Content-Type: text/plain"], "ERR:USER_DOES_NOT_EXIST")
				else
					user = $users.transaction{$users[params["get_params"]["user"]]}
					user.delete(:password)
					response(client, 200, ["Content-Type: application/json"], JSON.generate(user).to_s)
				end
			elsif params["path"] == "/settings"
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					if params["get_params"]["logout"] == "true"
						$sessions.delete(params["cookies"]["session"])
						redirect(client, "/")
					else
						session = params["cookies"]["session"]
						user = $sessions[session]
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/settings.html").gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s))
					end
				else
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/invalid_login.html"))
				end
			elsif params["path"] == "/messages"
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					user = $sessions[params["cookies"]["session"]]
					if !$messages.transaction{$messages[user]}
						$messages.transaction do
							$messages[user] = {}
							$messages.commit
						end
					end
					all_threads = $messages.transaction{$messages[user].keys}
					final_html = "<br>"
					for thread in all_threads do
						if $users.transaction{$users[thread]}
							final_html = final_html + "<a style = 'color: blue;' href = '/thread/#{thread}#send'>#{$users.transaction{$users[thread][:display_name]}.to_s}<a style=\"color: #2589db; text-decoration: none;\" href=\"javascript:void(alert('@#{thread} is a verified user.'))\">#{verified(thread)}</a></a>" + "<br>"						
						else
							final_html = final_html + "<a style = 'color: blue;' href = '/thread/#{thread}#send'>@#{thread} [Deleted]</a>" + "<br>"
						end
					end
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("html/messages.html").gsub("__messages__", final_html).gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s))
				else
					redirect(client, "/")
				end
			elsif params["path"] == "/messages/new"
				session = params["cookies"]["session"]
				user = $sessions[session]
				data = {}
				for parameter in params["data"].split("&") do
					data[parameter.split("=")[0]] = parameter.split("=")[1]
				end
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("html/new_message.html").gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s))
				else
					redirect(client, "/")
				end
			elsif params["path"].split("/")[1] == "thread" && params["path"].split("/")[2]
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					session = params["cookies"]["session"]
					user = $sessions[session]
					data = {}
					for parameter in params["data"].split("&") do
						data[parameter.split("=")[0]] = parameter.split("=")[1]
					end
					final = "<br>"
					for msg in $messages.transaction{$messages[user][params["path"].split("/")[2]]} do
						if msg[:type] == :send
							final = final + "<div style = 'border: 4px solid white; border-radius: 15px; background-color:#8f8e8b;'><h3 style = 'text-align: left; margin-left: 10px;'>#{msg[:body].to_s.gsub("\\n", "<br>").gsub("<", "&#60;").gsub("&#60;br>", "<br>")}</h3></div>"
						else
							final = final + "<div style = 'border: 4px solid white; border-radius: 15px; background-color:#0088ff;'><h3 style = 'text-align: right; margin-right: 10px;'>#{msg[:body].gsub("\\n", "<br>").gsub("<", "&#60;")}</h3></div>"
						end
					end
					if $users.transaction{$users[params["path"].split("/")[2]]}
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("html/thread.html").gsub("__thread__", final).gsub("__to__", params["path"].split("/")[2]).gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s).gsub("__to_verify__", verified(params["path"].split("/")[2])).gsub("__to_displayname__", $users.transaction{$users[params["path"].split("/")[2]][:display_name]}.to_s))
					else
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("html/thread.html").gsub("__thread__", final).gsub("__to__", params["path"].split("/")[2]).gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s).gsub("__to_verify__", "").gsub("__to_displayname__", "[Deleted]"))
					end
				else
					redirect(client, "/")
				end
			elsif params["path"].split("/")[1] && $users.transaction{$users[params["path"].split("/")[1]]}
				redirect(client, "/user?user=#{params["path"].split("/")[1]}")
			else
				error(client, 404)
			end
		elsif params["method"] == "POST"
			if params["path"] == "/login"
				data = {}
				for parameter in params["data"].split("&") do
					data[parameter.split("=")[0]] = parameter.split("=")[1]
				end
				if $users.transaction{$users[data["user"]]} && $users.transaction{$users[data["user"]][:password]} == Digest::SHA256.hexdigest("Mmmm... Salt" + data["password"])
					session = rand(10000000000000000000000000000000000000000..99999999999999999999999999999999999999999).to_s
					$sessions[session] = data["user"]
					response(client, 200, ["Content-Type: text/html; charset=utf-8", "Set-Cookie: session=#{session}; Path=/; Max-age=172800"], "<meta http-equiv='refresh' content='0; URL=/' />Logged In! Click <a style = 'color:blue;' href = '/'>here</a> to go home.")
				else
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/invalid_login.html"))
				end
			elsif params["path"] == "/signup"
				data = {}
				for parameter in params["data"].split("&") do
					data[parameter.split("=")[0]] = parameter.split("=")[1]
				end
				if $users.transaction{$users[data["user"].gsub(" ", "_")]}
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("./html/username_taken.html"))
				else
					if data["user"].length > 1
						$users.transaction do
							$users[data["user"].gsub(" ", "_")] = {:password => Digest::SHA256.hexdigest("Mmmm... Salt" + data["password"]), :created_at => Time.now.to_i, :about_me => "", :verified => nil, :display_name => data["user"]}
							$users.commit
						end
						$messages.transaction do
							$messages[data["user"]] = {}
							$messages.commit
						end
						session = rand(10000000000000000000000000000000000000000..99999999999999999999999999999999999999999).to_s
						$sessions[session] = data["user"].gsub(" ", "_")
						response(client, 200, ["Content-Type: text/html; charset=utf-8", "Set-Cookie: session=#{session}; Path=/; Max-age=172800"], "Account Created! Click <a style = 'color:blue;' href = '/'>here</a> to go home.")
					else
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("html/invalidlength.html"))
					end
				end
			elsif params["path"] == "/signup_api"
				data = {}
				for parameter in params["data"].split("&") do
					data[parameter.split("=")[0]] = parameter.split("=")[1]
				end
				if $users.transaction{$users[data["user"].gsub(" ", "_")]}
					response(client, 200, ["Content-Type: text/html; charset=utf-8"], "ERR:Taken")
				else
					if data["user"].length > 1
						$users.transaction do
							$users[data["user"].gsub(" ", "_")] = {:password => Digest::SHA256.hexdigest("Mmmm... Salt" + data["password"]), :created_at => Time.now.to_i, :about_me => "", :verified => nil, :display_name => data["user"]}
							$users.commit
						end
						$messages.transaction do
							$messages[data["user"]] = {}
							$messages.commit
						end
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], "Success")
					else
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], "ERR:invalidlength")
					end
				end
			elsif params["path"] == "/login_api"
				data = {}
				for parameter in params["data"].split("&") do
					data[parameter.split("=")[0]] = parameter.split("=")[1]
				end
				if $users.transaction{$users[data["user"]]} && $users.transaction{$users[data["user"]][:password]} == Digest::SHA256.hexdigest("Mmmm... Salt" + data["password"])
					response(client, 200, ["Content-Type: text/plain"], "Success")
				else
					response(client, 200, ["Content-Type: text/plain"], "Fail")
				end
			elsif params["path"] == "/modify_user"
				data = {}
				for parameter in params["data"].split("&") do
					data[parameter.split("=")[0]] = parameter.split("=")[1]
				end
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					session = params["cookies"]["session"]
					user = $sessions[session]
					$users.transaction do
						if data.keys.include?("deleteacct") && Digest::SHA256.hexdigest("Mmmm... Salt" + data["deleteacct"]) == $users[user][:password]
							$users.delete(user)
							$sessions.delete(session)
							$users.commit
						end
						for key in data.keys
							if key == "password"
								$users[user][key.to_sym] = Digest::SHA256.hexdigest("Mmmm... Salt" + data[key])
							elsif key != "verified"
								$users[user][key.to_sym] = URI.unescape(data[key]).gsub("<", "&#60;").gsub("+", " ")
							end
						end
						$users.commit
					end
					redirect(client, "/settings")
				else
					redirect(client, "/")
				end
			elsif params["path"] == "/messages/new"
				if params["cookies"].keys.include?("session") && $sessions.keys.include?(params["cookies"]["session"])
					session = params["cookies"]["session"]
					user = $sessions[session]
					data = {}
					for parameter in params["data"].split("&") do
						data[parameter.split("=")[0]] = parameter.split("=")[1]
					end
					if !$users.transaction{$users[data["to"]]}
						response(client, 200, ["Content-Type: text/html; charset=utf-8"], File.read("html/user_does_not_exist_messages.html").gsub("__username__", user).gsub("__verified__", verified(user)).gsub("__displayname__", $users.transaction{$users[user][:display_name]}.to_s))
					else
						send_message(data["to"], user, data["message"])
						redirect(client, "/thread/#{data["to"]}#send")
					end
				else
					redirect(client, "/")
				end
			else
				error(client, 404)
			end
		else
			error(client, 405)
		end
	end
end

start_params = {
	"remove-trailing-slash" => true
}

begin
	start(start_params)
rescue Interrupt
	puts "\nExiting..."
end