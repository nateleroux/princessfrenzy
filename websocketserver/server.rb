require 'eventmachine'
require 'em-websocket'
require_relative 'game.rb'
require_relative 'arrow.rb'
require_relative 'user.rb'
require_relative 'helpers.rb'

def send_move_message(game,ws,user)
  message = Game::MOVE + Game::DELIMITER + user.id + Game::DELIMITER + user.dir.to_s + Game::DELIMITER + user.x.to_s + Game::DELIMITER + user.y.to_s + Game::DELIMITER + user.dead.to_s
  ws.send message
end

def send_specific_move_message(game,ws,user,x,y)
  message = Game::MOVE + Game::DELIMITER + user.id + Game::DELIMITER + user.dir.to_s + Game::DELIMITER + x.to_s + Game::DELIMITER + y.to_s + Game::DELIMITER + user.dead.to_s
  ws.send message
end

def send_winning_message(game,ws,userId)
  message = Game::WINNING + Game::DELIMITER + userId
  ws.send message
end

def send_server_message_message(game,ws,message)
  message = Game::SERVER_MESSAGE + Game::DELIMITER + message
  ws.send message
end

def send_arrow_message(game,ws,arrow)
  message = Game::ARROW + Game::DELIMITER + arrow.id + Game::DELIMITER + arrow.dir.to_s + Game::DELIMITER + arrow.x.to_s + Game::DELIMITER + arrow.y.to_s + Game::DELIMITER + arrow.level.file
  ws.send message
end


def send_leaderboard_message(game,ws,html)
  message = Game::LEADERBOARD + Game::DELIMITER + html
  ws.send message
end

def send_level_message(game,ws,file)
  message = Game::LEVEL + Game::DELIMITER + file
  ws.send message
end

def send_princess_message(game,ws,x,y,dir)
  message = Game::PRINCESS + Game::DELIMITER + x.to_s + Game::DELIMITER + y.to_s + Game::DELIMITER + dir.to_s
  ws.send message
end

def send_die_message(game,ws,user)
  message = Game::DIE + Game::DELIMITER + user.id
  ws.send message
end

def send_banned_message(game,ws)
  message = Game::BANNED
  ws.send message
end

def send_chat_message(game,ws,sender,message)
  message = Game::CHAT + Game::DELIMITER + sender + Game::DELIMITER + message.to_s
  ws.send message
end

def add_user_to_level(game,user,level)
    send_level_message(game, user.ws, level.file)

    user.x = level.spawn["x"]
    user.y = level.spawn["y"]

    level.users.each do |user_already_in_level|
      send_move_message(game,user.ws,user_already_in_level) #Tell this person about all the players
    end

    if level.file == "2.json"
      send_princess_message(game,user.ws,level.princess_point["x"],level.princess_point["y"],level.princess_dir)
    end

    level.users.push(user)
    user.level = level

    level.users.each do |user_already_in_level|
      send_move_message(game,user_already_in_level.ws,user) #Tell each player about this new person
    end

    level.arrows.each do |arrow|
      send_arrow_message(game, user.ws, arrow)
    end
end

def remove_user_from_game(game,user)
  #Is this user the current winner?
  if user == game.current_winner
    game.current_winner = nil
	user.level.users.each do |u|
      send_server_message_message(game,u.ws,user.id + " gives up the princess. " + game.princess_time.to_s + " seconds left.")
      send_winning_message(game,u.ws,"_null")
    end
  end
  remove_user_from_level(game,user,user.level)
  game.users.delete(user)
end

def remove_user_from_level(game,user,level)
  level.users.delete(user)

  if level.file == "2.json"
    send_princess_message(game,user.ws,-1,-1,Game::DIRECTION_RIGHT)
  end

  user.x = -1
  user.y = -1
  
  #Tell all users that this guy is out of here..
  level.users.each do |user_already_in_level|
    send_move_message(game,user_already_in_level.ws,user)
  end

  #Tell this users to delete display objects of old users
   level.users.each do |user_already_in_level|
    send_specific_move_message(game,user.ws,user_already_in_level,-1,-1)
  end
end

def handle_chat(user,ws,params,game)
  if user.id == nil || user == nil || params[1] == nil
    return
  end
  puts user.id.to_s + " : " + params[1]
  game.sockets.each do |ws|
    send_chat_message(game,ws,user.id.to_s,params[1])
  end
end

def handle_login(ws,params,game)
  if params[1] == nil || params[1] == ""
    return
  end
  if !does_user_exist?(params[1],game)
    ws.send Game::OK_RESPONSE

    port, ip = Socket.unpack_sockaddr_in(ws.get_peername)

    if params[1] == "bryceisadmin7220"
      user = User.new("Bryce", ws, Game::DIRECTION_UP, 5, 5, true, ip)
    else
      user = User.new(params[1], ws, Game::DIRECTION_UP, 5, 5, false, ip)
    end

    if game.current_winner != nil
      send_winning_message(game,user.ws,game.current_winner.id)
    end

    game.users.push(user)

    add_user_to_level(game,user,game.levels[0][0])
  end
end

def handle_move(user,ws,params,game)
  if user==nil || user.dead
    return
  end
  
  if Time.now < user.next_move - Game::PLAYER_FUDGE_ACTION_TIME
	return
  end
  
  user.next_move = Time.now + Game::PLAYER_MOVE_TIME
  
  dir = user.dir
  x = user.x
  y = user.y
  
  # where do they want to go?
  user.dir = params[1].to_s
  
  if params[1].to_s == Game::DIRECTION_UP.to_s
	y -= 1
  elsif params[1].to_s == Game::DIRECTION_DOWN.to_s
    y += 1
  elsif params[1].to_s == Game::DIRECTION_LEFT.to_s
    x -= 1
  elsif params[1].to_s == Game::DIRECTION_RIGHT.to_s
    x += 1
  else
    # this is an invalid direction....
    user.dir = dir
  end
  
  # now lets make sure they can actually move there
  if x >= 0 && x < Game::MAP_WIDTH && y >= 0 && y < Game::MAP_HEIGHT && user.level.collision[y][x] == 0 && user.level.player_collision[y][x] == 0
    user.x = x
	user.y = y
  end

  user.level.warps.each do |warp|
    if warp.x == user.x && warp.y == user.y
        remove_user_from_level(game,user,user.level)
        add_user_to_level(game,user,warp.level)
    end
  end

  if user.level == Level.levels["2.json"]
    if user.x == Level.levels["2.json"].princess_point["x"] && user.y == Level.levels["2.json"].princess_point["y"] && game.current_winner != user
      game.current_winner = user
      user.level.users.each do |u|
        send_server_message_message(game,u.ws,user.id + " claims the princess. " + game.princess_time.to_s + " seconds left.")
        send_winning_message(game,u.ws,user.id)
      end
    end
  end

  user.level.users.each do |user_in_level|
    send_move_message(game,user_in_level.ws,user)
  end
end

def handle_arrow(user,ws,params,game)
  if user==nil || user.dead
    return
  end
  
  if Time.now < user.next_arrow - Game::PLAYER_FUDGE_ACTION_TIME
	return
  end
  
  user.next_arrow = Time.now + Game::PLAYER_ARROW_TIME

  #if user.level == game.levels[0][0]
  #  sendServerMessageMessage(game,ws,"You cannot fire arrows here.")
  #  return
  #end

  if user.dir.to_s == Game::DIRECTION_UP.to_s && user.level.collision[user.y-1][user.x] == 0
    x = user.x
    y = user.y-1
  elsif user.dir.to_s == Game::DIRECTION_DOWN.to_s && user.level.collision[user.y+1][user.x] == 0
    x = user.x
    y = user.y+1
  elsif user.dir.to_s == Game::DIRECTION_LEFT.to_s && user.level.collision[user.y][user.x-1] == 0
    x = user.x-1
    y = user.y
  elsif user.dir.to_s == Game::DIRECTION_RIGHT.to_s && user.level.collision[user.y][user.x+1] == 0
    x = user.x+1
    y = user.y
  else
    return
  end
  arrow = Arrow.new(game.arrow_ids.to_s, user.dir, x, y, user.level, user.id)
  game.arrow_ids+=1
  game.arrows.push(arrow)

  arrow.level.users.each do |user|
    send_arrow_message(game, user.ws, arrow)
  end
end

def parse_message(ws,msg,game)
  params = msg.split(Game::DELIMITER)

	if msg[0] == Game::LOGIN
    handle_login(ws,params,game)
    return
  end

  user = get_user_from_ws(game,ws)

  if user == nil
    return
  end

  if is_user_banned?(game,user)
    send_banned_message(game, ws)
    return
  end

  user.last_action = Time.now

	if msg[0] == Game::MOVE
    handle_move(user,ws,params,game)
  elsif msg[0] == Game::ARROW
    handle_arrow(user,ws,params,game)
  elsif msg[0] == Game::CHAT
    handle_chat(user,ws,params,game)
  elsif msg[0] == "V"
    #die("Goodbye")
  end
end

game = Game.new

EventMachine.run {
    EM.add_periodic_timer(1) do
      game.princess_time-=1
      if game.princess_time == 0
        if game.current_winner !=nil
          game.current_winner.wins+=1

          game.users.each do |user|
            send_server_message_message(game,user.ws,game.current_winner.id.to_s + " held onto the princess, and wins the round.")
          end
        
          game.current_winner = nil
        end
        game.princess_time = 60
        Level.levels["2.json"].randomize_princess

        Level.levels["2.json"].users.each do |user|
          send_princess_message(game,user.ws,Level.levels["2.json"].princess_point["x"],Level.levels["2.json"].princess_point["y"],Level.levels["2.json"].princess_dir)
          send_winning_message(game,user.ws,"_null")
        end

        #Send leaderboard info
        game.users = game.users.sort! { |a, b|  a.wins <=> b.wins }

        game.users = game.users.reverse

        html = ""
        game.users.each do |user|
          html = html+"<li>" + user.id + " - " + user.wins.to_s + "</li>"
        end

        game.users.each do |user|
          send_leaderboard_message(game,user.ws,html)
        end

      end
    end
    EM.add_periodic_timer(30) do
      #let server see list of users
      puts "Connected users:"
      game.users.each do |user|
        puts user.id + " " + user.ip
        if user.last_action + Game::TIMEOUT_SECONDS < Time.now
          user.ws.close_websocket
        end
      end
    end
    EM.add_periodic_timer(0.05) do
      game.arrows.each do |arrow|

        game.users.each do |user|
          if arrow.level.collision[arrow.y][arrow.x] !=0
            arrow.x = -1
            arrow.y = -1
          end

          if arrow.owner != user.id && user.x == arrow.x && user.y == arrow.y && user.dead == false && arrow.level == user.level
            send_server_message_message(game, user.ws, "You will be revived in 20 seconds.")
            user.dead = true
            game.sockets.each do |ws|

              # delete arrow
              arrow.x = -1
              arrow.y = -1

              timer = EventMachine::Timer.new(20) do
                if user!=nil
                  user.dead = false
				  user.spawn_protection = Time.now + 1
                end
              end
              send_die_message(game, ws, user)
            end
          end
        end

        arrow.level.users.each do |user|
          send_arrow_message(game, user.ws, arrow)
        end

		
		# we move the arrows after checking collision
		if arrow.x >= 0 && arrow.y >= 0 && arrow.x < Game::MAP_WIDTH && arrow.y < Game::MAP_HEIGHT
			if arrow.dir.to_s == Game::DIRECTION_UP.to_s
				arrow.y-=1
			elsif arrow.dir.to_s == Game::DIRECTION_DOWN.to_s
				arrow.y+=1
			elsif arrow.dir.to_s == Game::DIRECTION_LEFT.to_s
				arrow.x-=1
			elsif arrow.dir.to_s == Game::DIRECTION_RIGHT.to_s
				arrow.x+=1
			end
		else
          game.arrows.delete(arrow)
        end

      end
    end

    EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 8080) do |ws|
        ws.onopen {
          game.sockets.push(ws)
        }

        ws.onclose {
          id = ""

          #Remove the user
          game.users.each do |user|
            if user.ws == ws
              id = user.id
              remove_user_from_game(game,user)
            end
          end

          #Remove the Socket
          game.sockets.delete(ws)

          #Inform players he left
          game.sockets.each do |socket|
            send_chat_message(game, socket, "THE SERVER SAYS", id.to_s + " has left.")
            socket.send Game::QUIT + Game::DELIMITER + id
          end
        }

        ws.onmessage { |msg|
        	parse_message(ws,msg,game)
        }
    end
}
