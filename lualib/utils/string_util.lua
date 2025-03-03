local M = {}

local tremove = table.remove
local tinsert = table.insert
local tunpack = table.unpack
local sgmatch = string.gmatch
local next = next
local pairs = pairs

--[[
	函数作用域：M 的成员函数
	函数名称: split
	描述:字符串分割，可以嵌套分割 例如：split('1:2_3:4','_',':') res = {{1,2},{3,4}}
	参数:
		- inputstr (string): 被分割字符串
		- ... 分隔符列表
]]
function M.split(inputstr, ...)
    local seps = {...}
    local sep = tremove(seps,1)

    if sep == nil then
        return inputstr
    end
    local result={}
    for str in sgmatch(inputstr, "([^"..sep.."]+)") do
        tinsert(result,str)
    end
    if seps and next(seps) then
        for k,v in pairs(result) do
            result[k] = M.split(v,tunpack(seps))
        end
    end

    return result
end

return M