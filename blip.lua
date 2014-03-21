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
local io           = require 'lem.io'
local postgres     = require 'lem.postgres'
local qpostgres    = require 'lem.postgres.queued'
local httpserv     = require 'lem.http.server'
local hathaway     = require 'lem.hathaway'

local assert = assert
local format = string.format
local tonumber = tonumber

local get_blipv1, put_blipv1
do
   local thisthread, suspend, resume
      = utils.thisthread, utils.suspend, utils.resume
   local queue, n = {}, 0

   -- queue thread(from http request) until put-blip is called
   function get_blipv1()
      n = n + 1;
      queue[n] = thisthread()

      return suspend()
   end

   -- resume all http request with the recieved ms.
   function put_blipv1(stamp, ms)
      print(stamp, ms, n)
      for i = 1, n do
         resume(queue[i], stamp, ms)
         queue[i] = nil
      end

      n = 0
   end
end

local get_blipv2, put_blipv2
do
   local thisthread, suspend, resume
      = utils.thisthread, utils.suspend, utils.resume
   local queue, n = {}, 0

   function get_blipv2()
      n = n + 1;
      queue[n] = thisthread()

      return suspend()
   end

   function put_blipv2(stamp, ms)
      print(stamp, ms, n)
      for i = 1, n do
         resume(queue[i], stamp, ms)
         queue[i] = nil
      end

      n = 0
   end
end



utils.spawn(function()

      -- local serial = assert(io.open('/dev/blipduino', 'r'))
      local serial = assert(io.open('/dev/ttyACM0', 'r'))
      -- local serial = assert(io.open('/dev/arduino', 'r'))
      -- local serial = assert(io.open('/dev/ttyUSB0', 'r'))
      local db = assert(postgres.connect('user=powermeter dbname=powermeter'))
      local now = utils.now
      assert(db:prepare('putV1', 'INSERT INTO readingsv1 VALUES ($1, $2)'))
      assert(db:prepare('putV2', 'INSERT INTO readingsv2 VALUES ($1, $2)'))

      -- discard first two readings
      assert(serial:read('*l'))
      assert(serial:read('*l'))

      while true do
         local line = assert(serial:read('*l'))
         local variable, ms = line:match("(%S+)%s+(.+)")
         local stamp = format('%0.f', now() * 1000)

         if variable == "V1" then
            put_blipv1(stamp, ms)
            assert(db:run('putV1', stamp, ms))
         elseif variable == "V2" then
            put_blipv2(stamp, ms)
            assert(db:run('putV2', stamp, ms))
         end

      end
end)

local function sendfile(content, path)
   return function(req, res)
      res.headers['Content-Type'] = content
      res.file = path
   end
end

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

local db = assert(qpostgres.connect('user=powermeter dbname=powermeter'))
assert(db:prepare('getv1',  'SELECT stamp, ms FROM readingsv1 WHERE stamp >= $1 ORDER BY stamp LIMIT 2000'))
assert(db:prepare('lastv1', 'SELECT stamp, ms FROM readingsv1 ORDER BY stamp DESC LIMIT 1'))
assert(db:prepare('usagev1', 'SELECT COUNT(*) FROM readingsv1 WHERE stamp >= $1'))

assert(db:prepare('getv2',  'SELECT stamp, ms FROM readingsv2 WHERE stamp >= $1 ORDER BY stamp LIMIT 2000'))
assert(db:prepare('lastv2', 'SELECT stamp, ms FROM readingsv2 ORDER BY stamp DESC LIMIT 1'))
assert(db:prepare('usagev2', 'SELECT COUNT(*) FROM readingsv2 WHERE stamp >= $1'))


OPTIONS('/blipv1', apioptions)
GET('/blipv1', function(req, res)
       apiheaders(res.headers)

       -- get_blip queues and returns when a blip is recieved
       local stamp, ms = get_blipv1()
       res:add('[%s,%s]', stamp, ms)
end)
OPTIONS('/blipv2', apioptions)
GET('/blipv2', function(req, res)
       apiheaders(res.headers)

       local stamp, ms = get_blipv2()
       res:add('[%s,%s]', stamp, ms)
end)


-- add API functions here
local function defineapi(ver)

   OPTIONS('/last' .. ver, apioptions)
   GET('/last' .. ver, function(req, res)
          apiheaders(res.headers)

          local point = assert(db:run('last' .. ver))[1]
          res:add('[%s,%s]', point[1], point[2])
   end)

   OPTIONSM('^/since'.. ver .. '/(%d+)$', apioptions)
   GETM('^/since' .. ver .. '/(%d+)$', function(req, res, since)
           -- if since is longer than 15 digit ...
           if #since > 15 then
              httpserv.bad_request(req, res)
              return
           end
           apiheaders(res.headers)
           add_json(res, assert(db:run('get' .. ver, since)))
   end)

   OPTIONSM('^/last' .. ver .. '/(%d+)$', apioptions)
   GETM('^/last' .. ver .. '/(%d+)$', function(req, res, ms)
           if #ms > 15 then
              httpserv.bad_request(req, res)
              return
           end
           apiheaders(res.headers)

           local since = format('%0.f',
                                utils.now() * 1000 - tonumber(ms))

           add_json(res, assert(db:run('get' .. ver, since)))
   end)

   OPTIONSM('^/usage' .. ver .. '/(%d+)$', apioptions)
   GETM('^/usage' .. ver .. '/(%d+)$', function(req, res, ms)
           if #ms > 15 then
              httpserv.bad_request(req, res)
              return
           end
           apiheaders(res.headers)

           local since = format('%0.f',
                                utils.now() * 1000 - tonumber(ms))
           local blips = assert(db:run('usage' .. ver, since))[1]
           res:add('[%s]', blips[1])
   end)
end

-- init API's defined above
defineapi('v1')
defineapi('v2')

hathaway.debug = print
assert(Hathaway('*', arg[1] or 8080))

-- vim: syntax=lua ts=2 sw=2 noet:
