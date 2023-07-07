
local log = require "log"
local skynet = require "skynet"
local contriner_client = require "contriner_client"
local queue = require "skynet.queue"
local timer = require "timer"
local pcall = pcall
local next = next

local g_player_map = {}
local g_fd_map = {}

local M = {}

function M.join(player_id,player_info,fd,gate)
	local agent = g_player_map[player_id]

	if not agent then
	 	agent = {
			player_id = player_id,
			player_info = player_info,
			fd = fd,
			gate = gate,
			queue = queue(),
		}
		g_player_map[player_id] = agent
	else
		if agent.is_goout then
			log.fatal("退出中 ....",player_id)
			return 
		end
		g_fd_map[agent.fd] = nil
		agent.fd = fd
	end

	g_fd_map[fd] = agent
	return agent.queue(function()
		if not agent.match_client then
			agent.match_client = contriner_client:new("match_m",nil,function() return false end)
			local room_server,table_id = agent.match_client:mod_call('match',player_id,player_info,fd,skynet.self())
			if not room_server then
				return false
			else
				return true
			end

			agent.room_server = room_server
			agent.table_id = table_id
		else
			local room_server = agent.room_server
			local table_id = agent.table_id
			skynet.send(room_server,'lua','reconnect',player_id,table_id,fd)
		end

		pcall(skynet.call,agent.gate,'forward',fd)
		return true
	end)
end

function M.disconnect(player_id)
	local agent = g_player_map[player_id]
	if not agent then 
		log.fatal("disconnect not agent ",player_id)
		return
	end

	g_fd_map[agent.fd] = nil
	agent.fd = 0

	local room_server = agent.room_server
	local table_id = agent.table_id

	log.error("disconnect:",room_server,player_id,table_id)
	skynet.send(room_server,'lua','disconnect',player_id,table_id)
end

function M.goout(player_id)
	local agent = g_player_map[player_id]
	if not agent then
		log.error("goout not agent ",player_id)
		return
	end
	agent.is_goout = true
	return agent.queue(function()
		local match_client = agent.match_client
		if not match_client:mod_call('leave',player_id) then
			log.error("leave faild !!! ",player_id)
			return
		end

		g_player_map[player_id] = nil
		g_fd_map[agent.fd] = nil
		skynet.send(agent.gate,'lua','kick',agent.fd)
		skynet.send('.login','lua','goout',player_id)
		return true
	end)
end

function M.send_request(fd,packname,tab)
	local agent = g_fd_map[fd]
	if not agent then
		log.error("send_request not agent ",fd,packname,tab)
		return
	end

	log.info("send_request:",fd,packname,tab)
	local room_server = agent.room_server
	local table_id = agent.table_id
	local player_id = agent.player_id

	skynet.send(room_server,'lua','request',player_id,table_id,packname,tab)
end

function M.get_agent(fd)
	return g_fd_map[fd]
end

function M.is_empty()
	return not next(g_player_map)
end

return M