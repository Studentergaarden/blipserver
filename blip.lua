#!/usr/bin/env lem
-- -*- coding: utf-8 -*-

--
-- This file is part of blipserver.
-- Copyright 2011 Emil Renner Berthing
--
-- blipserver is free software: you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
--
-- blipserver is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with blipserver.  If not, see <http://www.gnu.org/licenses/>.
--

local utils        = require 'lem.utils'
local queue        = require 'lem.queue'
local io           = require 'lem.io'
local postgres     = require 'lem.postgres'
local qpostgres    = require 'lem.postgres.queued'
local httpserv     = require 'lem.http.server'
local hathaway     = require 'lem.hathaway'
local inspect = require 'inspect'

local assert = assert
local format = string.format
local tonumber = tonumber

local function log_dev(conn, id, desc)
	print(conn, id, desc)
	local file = io.open("/home/pawse/lua/log/power_device.log", "a")
	local time = os.date("*t")
	file:write(("  %04d/%02d/%02d %02d:%02d:%02d\n"):format(time.year, time.month, time.day, time.hour, time.min, time.sec))
	file:write('added device: ' .. conn .. ', Id: ' .. id .. ', desc: ' .. desc .. '.'  .. "\n")
	file:close()
end
local function unquote(s)
	local repl = function(m) return string.char(tonumber(m, 16)) end
	local u = s:gsub('\\([0-9a-fA-F][0-9a-fA-F])', repl)
	return u
end


local sgbus = {}
--local function socket_handler(client)
utils.spawn(function()
	local client = assert(io.open('/dev/blipduino', 'r+'))
	print('client connected')

	local db = assert(postgres.connect('user=powermeter dbname=powermeter'))
	local now = utils.now
	assert(db:prepare('put', 'INSERT INTO readings VALUES ($1, $2, $3)'))

	local connect_log
	-- discard first two readings
	for i=1,2 do
		local line = assert(client:read('*l'))
		local connect = line:match("^(CONNECTED.+)")
		if connect then
			connect_log = connect
			print(connect)
		else
			local id, desc_q = line:match("^INFO%s+([0-9]+)%s+(.+)")
			if id then
				local desc = unquote(desc_q)
				--log_dev(connect_log, id, desc)
				-- run db-stuff
			end
		end
	end

	while true do
		local line = assert(client:read('*l'))
		local stamp = format('%0.f', now() * 1000)

		connect = line:match("^(CONNECTED.*)")
		if connect then
			connect_log = connect
			print(connect)
		else
			local id, desc_q = line:match("^INFO%s+([0-9]+)%s+(.+)")
			if id then
				local desc = unquote(desc_q)
				--log_dev(connect_log, id, desc)
					-- run db-stuff
			else
				-- fordi [0-9]+ ikke starter med ^, bliver v1 og v2 også fanget
				local id, val = line:match("([0-9]+)%s+([0-9]+)")
				if id then
					print(id, stamp, val)
					if not sgbus[id] then
						sgbus[id] = queue.new()
					end
					local q = sgbus[id]
					if q then
						q:signal(stamp, val)
					end
					assert(db:run('put', id, stamp, val))
				end
			end
		end
	end

	print('client disconnected')
	client:close()
end
)
--local serial = assert(io.open('/dev/blipduino', 'r'))
--local tcp_socket = assert(io.tcp.listen('*', '8081'))
--utils.spawn(tcp_socket.autospawn, tcp_socket, socket_handler)
--utils.spawn(socket_handler(serial))


local function sendfile(content, path)
   return function(req, res)
      res.headers['Content-Type'] = content
      res.file = path
   end
end

-- hathaway.debug = print
hathaway.import()

GET('/',               sendfile('text/html; charset=UTF-8',       'index.html'))
GET('/index.html',     sendfile('text/html; charset=UTF-8',       'index.html'))
GET('/jquery.js',      sendfile('text/javascript; charset=UTF-8', 'jquery.js'))
GET('/jquery.flot.js', sendfile('text/javascript; charset=UTF-8', 'jquery.flot.js'))
GET('/excanvas.js',    sendfile('text/javascript; charset=UTF-8', 'excanvas.js'))
GET('/favicon.ico',    sendfile('image/x-icon',                   'favicon.ico'))

local function apiheaders(headers)
   headers['Content-Type'] = 'text/javascript; charset=UTF-8'
   headers['Cache-Control'] = 'max-age=0, must-revalidate'
   headers['Access-Control-Allow-Origin'] = '*'
   headers['Access-Control-Allow-Methods'] = 'GET'
   headers['Access-Control-Allow-Headers'] = 'origin, x-requested-with, accept'
   headers['Access-Control-Max-Age'] = '60'
end

local function apioptions(req, res)
   apiheaders(res.headers)
   res.status = 200
end

local function add_json(res, values)
   res:add('[')

   local n = #values
   if n > 0 then
      for i = 1, n-1 do
         local point = values[i]
         res:add('[%s,%s],', point[1], point[2])
      end
      local point = values[n]
      res:add('[%s,%s]', point[1], point[2])
   end

   res:add(']')
end


local function add_json5(res, values)
  res:add('[')

  local n = #values
  if n > 0 then
    for i = 1, n-1 do
      local point = values[i]
      res:add('[%s,%s,%s,%s,%s],', point[1], point[2], point[3], point[4], point[5])
    end
    local point = values[n]
    res:add('[%s,%s,%s,%s,%s]', point[1], point[2], point[3], point[4], point[5])
  end

  res:add(']')
end


local db = assert(qpostgres.connect('user=powermeter dbname=powermeter'))
assert(db:prepare('get',  'SELECT stamp, ms FROM readings WHERE id = $1 AND stamp >= $2 ORDER BY stamp LIMIT 20000'))
assert(db:prepare('last', 'SELECT stamp, ms FROM readings WHERE id = $1 ORDER BY stamp DESC LIMIT 1'))
assert(db:prepare('aggregate', 'SELECT $3*DIV(stamp - $2, $3) hour_stamp, COUNT(ms) FROM readings WHERE id = $1 and stamp >=$2 AND stamp < $2+$3*$4 GROUP BY hour_stamp ORDER BY hour_stamp'))
assert(db:prepare('hourly', 'SELECT stamp, events, wh, min_ms, max_ms FROM usage_hourly WHERE id = $1 AND stamp >= $2 AND stamp <= $3 ORDER BY stamp'))
assert(db:prepare('usage', 'SELECT COUNT(*) FROM readings WHERE id = $1 AND stamp >= $2'))
assert(db:prepare('aggregate_hourly', 'SELECT $3*DIV(stamp - $2, $3) hour_stamp, SUM(wh) FROM usage_hourly WHERE id = $1 and stamp >=$2 AND stamp < $2+$3*$4 GROUP BY hour_stamp ORDER BY hour_stamp'))


OPTIONSM('^/blip/(%d+)$', apioptions)
GETM('^/blip/(%d+)$', function(req, res, dev)
	-- dev is a string here. But dev is also a string when received through the
	-- serial port, when the table(sgbus) is indexed
	apiheaders(res.headers)
	local q = sgbus[dev]
	if q then
	   local stamp, val = q:get()
	   if stamp then
		  res:add('[%s,%s]', stamp, val)
	   end
	end
end)


OPTIONSM('^/last/(%d+)$', apioptions)
GETM('^/last/(%d+)$', function(req, res, dev)
	apiheaders(res.headers)
	if #ms > 15 then
	   httpserv.bad_request(req, res)
	   return
	end
	apiheaders(res.headers)

	local point = assert(db:run('last',dev))[1]
	res:add('[%s,%s]', point[1], point[2])
end)


OPTIONSM('^/since/(%d+)/(%d+)$', apioptions)
GETM('^/since/(%d+)/(%d+)$', function(req, res, dev, since)
	if #since > 15 then
		httpserv.bad_request(req, res)
		return
	end
	apiheaders(res.headers)
	add_json(res, assert(db:run('get', dev, since)))
end)

OPTIONSM('^/aggregate/(%d+)/(%d+)/(%d+)/(%d+)$', apioptions)
GETM('^/aggregate/(%d+)/(%d+)/(%d+)/(%d+)$', function(req, res, dev, since, interval, count)
	if #since > 15 or #interval > 15 or #count > 15 or tonumber(count) > 1000 then
		httpserv.bad_request(req, res)
		return
	end
	apiheaders(res.headers)
	add_json(res, assert(db:run('aggregate', dev, since, interval, count)))
end)

OPTIONSM('^/aggregate_hourly/(%d+)/(%d+)/(%d+)/(%d+)$', apioptions)
GETM('^/aggregate_hourly/(%d+)/(%d+)/(%d+)/(%d+)$', function(req, res, dev, since, interval, count)
	if #since > 15 or #interval > 15 or #count > 15 or tonumber(count) > 1000 then
		httpserv.bad_request(req, res)
		return
	end
	apiheaders(res.headers)
	add_json(res, assert(db:run('aggregate_hourly', dev, since, interval, count)))
end)

OPTIONSM('^/hourly/(%d+)/(%d+)/(%d+)$', apioptions)
GETM('^/hourly/(%d+)/(%d+)/(%d+)$', function(req, res, dev, since, last)
  if #since > 15 or #last > 15 then
    httpserv.bad_request(req, res)
    return
  end
  apiheaders(res.headers)
  add_json5(res, assert(db:run('hourly', dev, since, last)))
end)

OPTIONSM('^/last/(%d+)/(%d+)$', apioptions)
GETM('^/last/(%d+)/(%d+)$', function(req, res, dev, ms)
	if #ms > 15 then
		httpserv.bad_request(req, res)
		return
	end
	apiheaders(res.headers)

	local since = format('%0.f',
		utils.now() * 1000 - tonumber(ms))

	add_json(res, assert(db:run('get', dev,since)))
end)

OPTIONSM('^/usage/(%d+)/(%d+)$', apioptions)
GETM('^/usage/(%d+)/(%d+)$', function(req, res, dev, ms)
		if #ms > 15 then
			httpserv.bad_request(req, res)
		   return
		end
		apiheaders(res.headers)
		local since = format('%0.f',
							 utils.now() * 1000 - tonumber(ms))
		local blips = assert(db:run('usage', dev, since))[1]
		res:add('[%s]', blips[1]) 
end)

assert(Hathaway('*', arg[1] or 8080))

-- vim: syntax=lua ts=2 sw=2 noet:
