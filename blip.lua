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

local sgbus = {}

utils.spawn(function()
	local serial = assert(io.open('/dev/blipduino', 'r'))
	local db = assert(postgres.connect('user=powermeter dbname=powermeter'))
	local now = utils.now
	assert(db:prepare('put', 'INSERT INTO readings VALUES ($1, $2, $3)'))

	-- discard first two readings
	assert(serial:read('*l'))
	assert(serial:read('*l'))

	while true do
		local line = assert(serial:read('*l'))
		local stamp = format('%0.f', now() * 1000)

		--dev is id
		local dev, val = line:match("(%S+)%s+(.+)")
		if dev then
		   -- REMEMBER: ID SHOULD BE STRING. otherwise change the /blip call
		   if dev == 'V2' then
			  dev = tostring(2)
		   else
			  dev = tostring(1)
		   end
		   --print(stamp, ms)
		   if not sgbus[dev] then
			  sgbus[dev] = queue.new()
			end
			local q = sgbus[dev]
			if q then
			   q:signal(stamp, val)
			end
			assert(db:run('put', dev, stamp, val))
		end
	end
end)


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
