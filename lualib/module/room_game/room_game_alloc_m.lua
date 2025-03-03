--桌子分配
local log = require "log"
local contriner_client = require "contriner_client"
local skynet = require "skynet"
local queue = require "skynet.queue"()
local timer = require "timer"

contriner_client:register("room_game_table_m")

local assert = assert
local pairs = pairs
local table = table
local ipairs = ipairs
local next = next

local SELF_ADDRESS = nil

local g_alloc_table_id = 1              --桌子id分配
local INIT_TABLE_ID = g_alloc_table_id  --初始id
local MAX_TABLE_ID = nil				--最大id

local alloc_plug = nil       --匹配插件

local g_table_map = {}
local g_player_map = {}
----------------------------------------------------------------------------------
--private
----------------------------------------------------------------------------------
local function alloc_table_id()
	local table_id = nil
	local cur_start_id = g_alloc_table_id
	while not table_id do
		if not g_table_map[g_alloc_table_id] then
			table_id = g_alloc_table_id
		end
		g_alloc_table_id = g_alloc_table_id + 1
		if g_alloc_table_id > MAX_TABLE_ID then
			g_alloc_table_id = INIT_TABLE_ID
		end
		if g_alloc_table_id == cur_start_id then
			break
		end
	end

	return SELF_ADDRESS .. ':' .. table_id,table_id
end

local function create_table(table_name, create_player_id)
    local table_id,num_id = alloc_table_id()
	if not table_id then
		log.info("alloc_table_id err ",table_id)
		return alloc_plug.tablefull()
	end

	local room_client = contriner_client:new("room_game_table_m",table_name,function() return false end)
	room_client:set_mod_num(num_id)
	local table_server_id = room_client:get_mod_server_id()
	local ok,errocode,errormsg = skynet.call(table_server_id,'lua','create_table',table_id,SELF_ADDRESS) 
	if ok then
		g_table_map[table_id] = {
			room_client = room_client,
			table_server_id = table_server_id,
			table_id = table_id,
			player_list = {},
		}
		local config = errocode
		alloc_plug.createtable(table_name,table_id,config,create_player_id)
		return table_id
	else
		return nil,errocode,errormsg
	end
end

local function join(player_id, gate, fd, hall_server_id, table_name, table_id)
    local t_info = g_table_map[table_id]
    if not t_info then
        return alloc_plug.table_not_exists()
    end
    local table_server_id = t_info.table_server_id
    local table_id = t_info.table_id
    local ok,errcode,errmsg = skynet.call(table_server_id,'lua','enter',table_id,player_id,gate,fd,hall_server_id)
    if not ok then
        log.info("enter table fail ",player_id,errcode,errmsg)
        return nil,errcode,errmsg
    else
        g_player_map[player_id] = t_info
        local player_list = t_info.player_list
        table.insert(player_list,player_id)

        alloc_plug.entertable(table_id,player_id)
        return table_server_id,table_id
    end
end

local function match_join(player_id, gate, fd, hall_server_id, table_name)
    assert(not g_player_map[player_id])
    local table_id = alloc_plug.match(player_id)
    local ok,errcode,errmsg
    if not table_id then
        table_id,errcode,errmsg = create_table(table_name)
        if not table_id then
            log.info("create_table err ",errcode,errmsg)
            return nil,errcode,errmsg
        end
    end

    return join(player_id, gate, fd, hall_server_id, table_name, table_id)
end

local function create_join(player_id, gate, fd, hall_server_id, table_name)
	assert(not g_player_map[player_id])
	local ok,errcode,errmsg = create_table(table_name)
	if not ok then
		return ok,errcode,errmsg
	end

	local table_id = ok
	return join(player_id, gate, fd, hall_server_id, table_name)
end

local function leave(player_id)
    local t_info = assert(g_player_map[player_id])
    local table_server_id = t_info.table_server_id
    local table_id = t_info.table_id
    local ok,errcode,errmsg = skynet.call(table_server_id,'lua','leave',table_id,player_id)
    if not ok then
        log.info("leave table fail ",table_id,player_id,errcode,errmsg)
        return nil,errcode,errmsg
    else
        local player_list = t_info.player_list
        for i = #player_list,1,-1 do
            if player_list[i] == player_id then
                table.remove(player_list,i)
                break
            end
        end
        alloc_plug.leavetable(table_id,player_id)
        if #player_list <= 0 then
            g_table_map[table_id] = nil
            alloc_plug.dismisstable(table_id)
        end
        g_player_map[player_id] = nil
        return true
    end
end
----------------------------------------------------------------------------------
--interface
----------------------------------------------------------------------------------
local interface = {}

----------------------------------------------------------------------------------
--CMD
----------------------------------------------------------------------------------
local CMD = {}
--创建进入房间
function CMD.create_join(player_id, gate, fd, hall_server_id, table_name)
	return queue(create_join, player_id, gate, fd, hall_server_id, table_name)
end

--匹配进入房间
function CMD.match_join(player_id, gate, fd, hall_server_id, table_name)
    return queue(match_join, player_id, gate, fd, hall_server_id, table_name)
end

--指定房间进入
function CMD.join(player_id, gate, fd, hall_server_id, table_name, table_id)
    return queue(join, player_id, gate, fd, hall_server_id, table_name, table_id)
end

--离开房间
function CMD.leave(player_id)
    return queue(leave, player_id)
end

function CMD.start(config)
	SELF_ADDRESS = skynet.self()
	assert(config.alloc_plug,"not alloc_plug")
	assert(config.MAX_TABLES,"not MAX_TABLES")  --最大桌子数量

	MAX_TABLE_ID = INIT_TABLE_ID + config.MAX_TABLES - 1

	alloc_plug = require (config.alloc_plug)
	assert(alloc_plug.init,"not match init")           --初始化
	assert(alloc_plug.match,"not match")		       --匹配
	assert(alloc_plug.tablefull,"not tablefull")       --桌子已满
    assert(alloc_plug.table_not_exists,"not table_not_exists")--桌子不存在
	assert(alloc_plug.createtable,"not createtable")   --创建桌子
	assert(alloc_plug.entertable,"not entertable")     --进入桌子
	assert(alloc_plug.leavetable,"not leavetable")     --离开桌子
	assert(alloc_plug.dismisstable,"not dismisstable") --解散桌子

	if alloc_plug.register_cmd then
		for name,func in pairs(alloc_plug.register_cmd) do
			assert(not CMD[name],"repeat cmd " .. name)
			CMD[name] = func
		end
	end

	alloc_plug.init(interface)
	return true
end

function CMD.check_exit()
	if not next(g_player_map) then
		log.info("g_player_map.is_empty can exit")
		return true
	else
		log.info("not g_player_map.is_empty can`t exit",g_player_map)
		return false
	end
end

function CMD.exit()
	return true
end

return CMD