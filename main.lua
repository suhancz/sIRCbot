package.path = package.path..";./?/init.lua;./src/?.lua"
require "settings"
irc = require "irc"
irc.set = require "irc.set"
util = require "irc.util"

sqlite3 = require "luasql.sqlite3"
local sqlenv = sqlite3.sqlite3()
local sql = sqlenv:connect('IGYdb.sqlite')
sql:setautocommit(true, "IMMEDIATE")
sql:execute("PRAGMA journal_mode=memory")

local sleep = require "socket".sleep
local sircbot = irc.new{nick = "sIRCbot"}
sircbot:connect(server_ip)
sircbot:join(schannel)
sircbot:setMode{target = sircbot.nick, add = "B"}

function pretty_az(input)
  if ((input > 9 and input < 20) or (input > 99 and input < 200) or (input > 9999 and input < 20000)) then
    return "A "..input.."."
  end
  local number = tonumber(tostring(input):sub(1,1))
  if (number == 1 or number == 5) then
    return "Az "..input.."."
  else
   return "A "..input.."."
  end
end

function settopic()
  local igy_cnt_query = sql:execute("SELECT MAX(id) FROM igyek")
  local igy_cnt = igy_cnt_query:fetch()
  igy_cnt_query:close()
  local join_cnt_query = sql:execute("SELECT MAX(id) FROM igyek_join")
  local join_cnt = join_cnt_query:fetch()
  join_cnt_query:close()
  local symbols_query = sql:execute("SELECT symbol FROM symbols")
  local leaf = symbols_query:fetch()
  local cigarette = symbols_query:fetch()
  symbols_query:close()
  local newtopic = leaf.." "..igy_cnt.." "..cigarette.." "
  local sticky_bullets_query = sql:execute("SELECT bullet FROM bulletin WHERE sticky=1 ORDER BY regdate DESC LIMIT 3")
  local sticky_bullets = sticky_bullets_query:fetch()
  while sticky_bullets do
    newtopic = newtopic.."-[ "..sticky_bullets.." ]- "
    if (newtopic:len() > 120) then
      sticky_bullets = nil
      sticky_bullets_query:close()
    else
      sticky_bullets = sticky_bullets_query:fetch()
    end
  end
  local bullets_query = sql:execute("SELECT bullet FROM bulletin WHERE sticky=0 ORDER BY regdate DESC LIMIT 10")
  local bullets = bullets_query:fetch()
  while bullets do
    if (newtopic:len() + bullets:len() > 465) then
      bullets = nil
      bullets_query:close()
    else
      newtopic = newtopic.."-[ "..bullets.." ]- "
      bullets = bullets_query:fetch()
    end
  end
  sircbot:send("TOPIC "..schannel.." :"..newtopic)
end

sircbot:hook("OnJoin", function(user, channel)
  local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'") 
  local igyer_id = igyer_id_query:fetch()
  igyer_id_query:close()
  if (igyer_id and channel == schannel) then
    local igyer_query = sql:execute("SELECT welcome,lastseen,igyer FROM igyerek WHERE id="..igyer_id)
    local igyer = igyer_query:fetch({},"a")
    igyer_query:close()
    local timediff_query = sql:execute("SELECT (strftime('%s','now','localtime') - strftime('%s','"..igyer.lastseen.."')) / 3600") 
    local timediff = timediff_query:fetch()
    timediff_query:close()
    if (igyer.welcome and timediff > 1) then
      sircbot:sendChat(channel, igyer.welcome)
    end
    sql:execute("UPDATE igyerek SET lastseen=datetime('now','localtime') WHERE id="..igyer_id)
  end
end)

sircbot:hook("OnPart", function(user, channel)
  local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'")
  local igyer_id = igyer_id_query:fetch()
  igyer_id_query:close()
  if (igyer_id and channel == schannel) then
    sql:execute("UPDATE igyerek SET lastseen=datetime('now','localtime') WHERE id="..igyer_id)
  end
end)

sircbot:hook("OnQuit", function(user, channel)
  local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'")
  local igyer_id = igyer_id_query:fetch()
  igyer_id_query:close()
  if (igyer_id and channel == schannel) then
    sql:execute("UPDATE igyerek SET lastseen=datetime('now','localtime') WHERE id="..igyer_id)
  end
end)

sircbot:hook("OnTopic", function(channel, topic)
  print("OnTopic Called")
end)

sircbot:hook("OnChat", function(user, channel, message)
  local fcommand = message:gmatch("[%S]+")
  local command = fcommand()
  
  if (channel == schannel and (command == "!igy" or command == "!tak" or command == "!így")) then
    local comment = sql:escape(message:sub(6))
    local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'") 
    local igyer_id = igyer_id_query:fetch()
    igyer_id_query:close()
    local multi_query = sql:execute("SELECT id,igyer_id,comment FROM igyek WHERE regdate > datetime('now','1 hour','-5 minutes') AND comment LIKE '"..comment:sub(1,5).."%' LIMIT 1")
    local multi = multi_query:fetch({},"a")
    multi_query:close()
    if (igyer_id) then
      if (not multi or comment:len() == 0 or multi.igyer_id == igyer_id) then
        sql:execute("INSERT INTO igyek(igyer_id, comment, regdate) VALUES("..igyer_id..", '"..comment.."', datetime('now','localtime'))")
        local igyek_query = sql:execute("SELECT COUNT(*) FROM igyek WHERE igyer_id="..igyer_id)
        local igyek = igyek_query:fetch()
        igyek_query:close()
        local sum_igyek_query = sql:execute("SELECT MAX(id) FROM igyek")
        local sum_igyek = sum_igyek_query:fetch()
        sum_igyek_query:close()
        sircbot:sendChat(channel,"Jó mokkolást "..user.nick.."! Ez "..tostring(pretty_az(igyek)):lower().." ígyed itt, valamint "..tostring(pretty_az(sum_igyek)):lower().." így a sIRCen!")
        settopic()
      else
        local double_multi_query = sql:execute("SELECT id FROM igyek_join WHERE igyer_id="..igyer_id.." AND igy_id="..multi.id)
        local double_multi = double_multi_query:fetch()
        double_multi_query:close()
        if (double_multi) then
          sircbot:sendChat(channel,"Jó mokkolást "..user.nick.."! Ezt már egyszer beígyelted, nem számoljuk.")
        else
          sql:execute("INSERT INTO igyek_join(igy_id, igyer_id, regdate) VALUES("..multi.id..", "..igyer_id..", datetime('now','localtime'))")
          local orig_igyer_query = sql:execute("SELECT igyer FROM igyerek WHERE id="..multi.igyer_id)
          local orig_igyer = orig_igyer_query:fetch()
          orig_igyer_query:close()
          local sum_multi_query = sql:execute("SELECT COUNT(*) FROM igyek_join WHERE igyer_id="..igyer_id)
          local sum_multi = sum_multi_query:fetch()
          sum_multi_query:close()
          sircbot:sendChat(channel,"Jó mokkolást "..user.nick.."! Az ígyet pedig "..orig_igyer.." ígyelte! Eddig "..sum_multi.." ígybe csatlakoztál bele")
        end
      end
    else
      sircbot:sendChat(channel,"Jó mokkolást "..user.nick.."! Regisztrálatlan host, nem számoljuk.")
    end
  end
  
  if (channel == schannel and command  == "!seen") then
    local igyer = fcommand()
    if (sircbot:whois(igyer)["userinfo"]) then
      sircbot:sendChat(channel, igyer.." épp itt van.")
    else
      local lastseen_query = sql:execute("SELECT lastseen FROM igyerek WHERE igyer='"..sql:escape(igyer).."'")
      local lastseen = lastseen_query:fetch()
      lastseen_query:close()
      if (lastseen) then
        sircbot:sendChat(channel, igyer.." legutóbb ekkor volt itt: "..lastseen)
      else
        sircbot:sendChat(channel,"Nem regisztrált ígyer! ("..igyer..")")
      end
    end
  end
  
  if (channel == schannel and command == "!top") then
    local legigyebb_query = sql:execute("SELECT igyer, igyer_id, COUNT(1) AS c FROM igyek LEFT JOIN igyerek ON igyek.igyer_id=igyerek.id GROUP BY igyer ORDER BY c DESC LIMIT 1") 
    local legigyebb = legigyebb_query:fetch({}, "a")
    legigyebb_query:close()
    local sum_multi_query = sql:execute("SELECT COUNT(*) FROM igyek_join LEFT JOIN igyerek ON igyek_join.igyer_id=igyerek.id WHERE igyer_id="..legigyebb.igyer_id)
    local sum_multi = sum_multi_query:fetch()
    sum_multi_query:close()
    sircbot:sendChat(channel,"Éppen "..legigyebb.igyer.." a legígyebb, összesen "..legigyebb.c.." ígyet ígyelt el és "..sum_multi.." ígybe ígyelt bele!")
  end
  
  if (channel == schannel and command == "!top3") then
    local legigyebbek_query = sql:execute("SELECT igyer, igyer_id, COUNT(1) AS c FROM igyek LEFT JOIN igyerek ON igyek.igyer_id=igyerek.id GROUP BY igyer ORDER BY c DESC LIMIT 3") 
    local legigyebbek = legigyebbek_query:fetch({}, "a")
    local cnt = 1
    local output = ""
    while legigyebbek do
      output = output..cnt..".:"..legigyebbek.igyer.."("..legigyebbek.c.."). "
      legigyebbek = legigyebbek_query:fetch({},"a")
      cnt = cnt + 1
    end
    sircbot:sendChat(channel,"A legígyebbek: "..output)
  end
  
  if (channel == schannel and command == "!howwuz") then
    local arg1 = fcommand()
    if (arg1 == nil) then
      sircbot:sendChat(channel, "Melyik így érdekel?")
      sircbot:sendChat(user.nick, "Help: !howwuz igy vagy !howwuz nick igy")
      return
    end
    local igy_id = tonumber(arg1)
    if (igy_id) then
      local max_query = sql:execute("SELECT MAX(id) FROM igyek;")
      local max = max_query:fetch()
      max_query:close()
      local multi_query = sql:execute("SELECT igyer FROM igyek_join LEFT JOIN igyerek ON igyek_join.igyer_id=igyerek.id WHERE igy_id="..igy_id)
      local multi = multi_query:fetch()
      if (igy_id > 0 and igy_id <= max) then
        local igy_query = sql:execute("SELECT igyer,comment,igyek.regdate FROM igyek LEFT JOIN igyerek ON igyek.igyer_id=igyerek.id WHERE igyek.id="..igy_id)
        local igy = igy_query:fetch({},"a")
        igy_query:close()      
        if (not multi and igy.comment == "") then
          sircbot:sendChat(channel, pretty_az(igy_id).." ígyet "..igy.igyer.." ígyelte "..igy.regdate.."-kor.")
        elseif (not multi and igy.comment ~= "") then
          sircbot:sendChat(channel, pretty_az(igy_id).." ígyet "..igy.igyer.." ígyelte, kommentje "..igy.comment.." "..igy.regdate.."-kor.")
        elseif (multi) then
          local output = ""
          while multi do
            output = output..multi..","
            multi = multi_query:fetch()
          end
          output = output:sub(1,-2)
          sircbot:sendChat(channel,pretty_az(igy_id).." ígyet "..igy.igyer.." ígyelte, kommentje "..igy.comment.." "..igy.regdate.."-kor. Ígyelt(ek) még: "..output)
        end
      else
        sircbot:sendChat(channel, "Nincs ilyen így")  
      end
    else
      local arg2 = fcommand()
      if (arg2 == nil) then
        sircbot:sendChat(channel, "Melyik így érdekel?")
        sircbot:sendChat(user.nick, "!howwuz igy vagy !howwuz nick igy")
        return
      end
      local igyer = sql:escape(arg1)
      local igy_cnt = tonumber(arg2)
      if (igy_cnt == nil) then
        sircbot:sendChat(channel, "Melyik így érdekel?")
        sircbot:sendChat(user.nick, "!howwuz igy vagy !howwuz nick igy")
        return
      end
      local igyer_id_query = sql:execute("SELECT id FROM igyerek WHERE igyer='"..igyer.."'")
      local igyer_id = igyer_id_query:fetch()
      igyer_id_query:close()
      if (igyer_id) then
        local max_query = sql:execute("SELECT COUNT(*) FROM igyek WHERE igyer_id="..igyer_id)
        local max = max_query:fetch()
        max_query:close()
        if (igy_cnt > 0 and igy_cnt <= max) then
          local igy_query = sql:execute("SELECT igyek.id,comment,igyek.regdate FROM igyek LEFT JOIN igyerek ON igyek.igyer_id=igyerek.id WHERE igyer_id="..igyer_id.." LIMIT 1 OFFSET "..igy_cnt-1)
          local igy = igy_query:fetch({},"a")
          igy_query:close()
          local multi_query = sql:execute("SELECT igyer FROM igyek_join LEFT JOIN igyerek ON igyek_join.igyer_id=igyerek.id WHERE igy_id="..igy.id)
          local multi = multi_query:fetch()
          if (not multi and igy.comment == "") then
            sircbot:sendChat(channel, igyer.." "..igy_cnt..". ígyét "..igy.regdate.."-kor ígyelte.")
          elseif (not multi and igy.comment ~= "") then
            sircbot:sendChat(channel, igyer.." "..igy_cnt..". ígyének kommentje "..igy.comment..", "..igy.regdate.."-kor.")
          elseif (multi) then
            local output = ""
            while multi do
              output = output..multi..","
              multi = multi_query:fetch()
            end
            output = output:sub(1,-2)
            sircbot:sendChat(channel, igyer.." "..igy_cnt..". ígyének kommentje "..igy.comment..", "..igy.regdate.."-kor. Ígyelt(ek) még: "..output)
          end
        else
          sircbot:sendChat(channel, "Nincs ilyen így")
        end
      else
        sircbot:sendChat(channel, "Ismeretlen ígyer ("..igyer..")")
      end
    end
  end 
  
  if (channel == schannel and command == "!last") then
    local igyer = fcommand()
    local last_query
    if (not igyer) then
      last_query = sql:execute("SELECT igyek.id,igyer FROM igyek LEFT JOIN igyerek ON igyek.igyer_id=igyerek.id WHERE igyek.id=(SELECT MAX(id) FROM igyek)")
    else
      local igyer_id_query = sql:execute("SELECT id FROM igyerek WHERE igyer='"..sql:escape(igyer).."'")
      local igyer_id = igyer_id_query:fetch()
      if (igyer_id) then
        last_query = sql:execute("SELECT igyek.id,igyer FROM igyek LEFT JOIN igyerek ON igyek.igyer_id=igyerek.id WHERE igyek.id=(SELECT MAX(id) FROM igyek WHERE igyer_id="..igyer_id..")")
      else
        sircbot:sendChat(channel, "Ismeretlen ígyer("..igyer..")")
        return
      end
    end
    local last = last_query:fetch({},"a")
    last_query:close()
    local multi_query = sql:execute("SELECT igyer FROM igyek_join LEFT JOIN igyerek ON igyek_join.igyer_id=igyerek.id WHERE igy_id="..last.id)
    local multi = multi_query:fetch()
    if (not multi) then
      if (not igyer) then
        sircbot:sendChat(channel,"Utoljára "..last.igyer.." ígyelte "..pretty_az(last.id).." ígyet.")
      else
        sircbot:sendChat(channel, igyer.." utoljára "..pretty_az(last.id).." ígyet ígyelte.")
      end
    else
      local output = ""
      while multi do
        output = output..multi..","
        multi = multi_query:fetch()
      end
      output = output:sub(1,-2)
      if (not igyer) then
        sircbot:sendChat(channel, "Utoljára "..last.igyer.." ígyelte "..pretty_az(last.id).." ígyet. Ígyelt(ek) még: "..output)
      else
        sircbot:sendChat(channel, igyer.."  utoljára "..pretty_az(last.id).." ígyet igyelte. Ígyelt(ek) még: "..output)
      end
    end
    multi_query:close()
  end
  
  if (channel == schannel and command == "!stat") then
    local igyer = fcommand()
    if (not igyer) then
      local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'") 
      local igyer_id = igyer_id_query:fetch()
      igyer_id_query:close()
      if (not igyer_id) then
        sircbot:sendChat(channel,"Ismeretlen ígyer ("..user.nick..")")
        return
      end
      local igyek_query = sql:execute("SELECT COUNT(*) FROM igyek WHERE igyer_id="..igyer_id)
      local igyek = igyek_query:fetch()
      igyek_query:close()
      local multi_query = sql:execute("SELECT COUNT(*) FROM igyek_join WHERE igyer_id="..igyer_id)
      local multi = multi_query:fetch()
      multi_query:close()
      sircbot:sendChat(channel, "Eddig "..igyek.." ígyet ígyeltél el és "..multi.." ígybe ígyeltél bele.")
    else
      local host
      if (sircbot:whois(igyer)['userinfo']) then
        host = sircbot:whois(igyer)['userinfo'][4]
      end
      local igyer_id
      if (not host) then
        local igyer_id_query = sql:execute("SELECT id FROM igyerek WHERE igyer='"..sql:escape(igyer).."'") 
        igyer_id = igyer_id_query:fetch()
        igyer_id_query:close()
      else
        local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..host.."'") 
        igyer_id = igyer_id_query:fetch()
        igyer_id_query:close()
      end
      if (igyer_id) then
        local igyek_query = sql:execute("SELECT COUNT(*) FROM igyek WHERE igyer_id="..igyer_id)
        local igyek = igyek_query:fetch()
        igyek_query:close()
        local multi_query = sql:execute("SELECT COUNT(*) FROM igyek_join WHERE igyer_id="..igyer_id)
        local multi = multi_query:fetch()
        multi_query:close()
        sircbot:sendChat(channel, igyer.." eddig "..igyek.." ígyet ígyelt el és "..multi.." ígybe ígyelt bele.")
      else
        sircbot:sendChat(channel, "Ismeretlen ígyer ("..igyer..")")
      end
    end
  end
  
  if (channel == schannel and command == "!rules") then
    rules()
  end
  
  if (channel == schannel and command == "!addtopic") then
    local private = tonumber((fcommand())) -- nil input works this way
    if (not private or private > 1 or private < 0) then
      sircbot:sendChat(user.nick, "Privát vagy nem?")
      return
    end
    local sticky = tonumber((fcommand())) -- nil input works this way
    if (not sticky or private > 1 or private < 0) then
      sircbot:sendChat(user.nick, "Maradjon látható??")
      return
    end
    local bullet = message:sub(15)
    if (bullet ~= nil) then
      local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'")
      local igyer_id = igyer_id_query:fetch()
      igyer_id_query:close()
      if (igyer_id) then
        sql:execute("INSERT INTO bulletin (igyer_id,bullet,regdate,private,sticky) VALUES ("..igyer_id..",'"..sql:escape(bullet).."',datetime('now','localtime'),"..private..","..sticky..")")
        sircbot:sendChat(user.nick, "Hozzáadva")
        settopic()
      else
        sircbot:sendChat(user.nick, "Nem ismerlek, regisztrálj előbb")
      end
    else
      sircbot:sendChat(user.nick, "Mit akarsz hozzáadni?")
    end
  end
  
  if (channel == sircbot.nick and command == "reg") then
    local nick = sql:escape(fcommand())
    if (nick == nil) then 
      sircbot:sendChat(user.nick, "Adj meg egy nicket!")
      return 
    end
    local password = sql:escape(fcommand())
    if (password == nil) then 
      sircbot:sendChat(user.nick, "Adj meg egy jelszót!")
      return 
    end
    local host_query = sql:execute("SELECT id FROM hosts WHERE host='"..user.host.."'")
    local host = host_query:fetch()
    host_query:close()
    if (host) then
      sircbot:sendChat(user.nick, "Host már regisztrálva")
      return
    end
    local igyer_query = sql:execute("SELECT igyerek.id,pass FROM igyerek LEFT JOIN hosts ON igyerek.id=hosts.igyer_id WHERE igyer='"..nick.."'")
    local igyer = igyer_query:fetch({},"a")
    igyer_query:close()    
    if (not igyer and password) then
      sql:execute("INSERT INTO igyerek(igyer,pass,regdate,lastseen) VALUES('"..nick.."', '"..password.."', datetime('now','localtime'), datetime('now','localtime'))")
      local igyer_id = sql:execute("SELECT id FROM igyerek WHERE igyer='"..nick.."'"):fetch()
      sql:execute("INSERT INTO hosts(igyer_id, host) VALUES("..igyer_id..", '"..user.host.."')")
      sircbot:sendChat(user.nick,"Sikeresen regisztráltál. (hostod: "..user.host..")")
    elseif (password == igyer.pass) then
        sql:execute("INSERT INTO hosts(igyer_id, host) VALUES("..igyer.id..", '"..user.host.."')")
        sircbot:sendChat(user.nick,"Host regisztrálva, most már innen is igyelhetsz.")
    elseif (password ~= igyer.pass and password ~= nil) then
      sircbot:sendChat(user.nick,"Hibás jelszó.")
    end
  end
  
  if (channel == sircbot.nick and command == "welcome") then
    local welcome = sql:escape(message:sub(9))
    local igyer_id_query = sql:execute("SELECT igyer_id FROM hosts WHERE host='"..user.host.."'")
    local igyer_id = igyer_id_query:fetch()
    igyer_id_query:close()
    if (igyer_id) then
      sql:execute("UPDATE igyerek SET welcome='"..welcome.."' WHERE id="..igyer_id)
      sircbot:sendChat(user.nick, "Üzenet rögzítve ("..welcome..").")
    else
      sircbot:sendChat(user.nick, "Nem tudom ki vagy regisztrálj előbb.")
    end
  end

  if (channel == sircbot.nick and command == "listtopics") then
    local bullets_query = sql:execute("SELECT bulletin.id,bullet,bulletin.regdate,igyer FROM bulletin LEFT JOIN igyerek ON igyer_id=igyerek.id ORDER BY bulletin.regdate DESC LIMIT 20")
    local bullets = bullets_query:fetch({},"a")
    while bullets do
      sircbot:sendChat(user.nick, "Topic ID:"..bullets.id.."|hozzáadta: "..bullets.igyer.." "..bullets.regdate..".kor")
      sircbot:sendChat(user.nick, bullets.bullet)
      bullets = bullets_query:fetch({},"a")
    end
  end
  
  if (channel == sircbot.nick and command == "setsticky") then
    local bullet_id = tonumber((fcommand()))
    if (bullet_id ~= nil) then
      local bullet_query = sql:execute("SELECT sticky FROM bulletin WHERE id="..bullet_id)
      local bullet = bullet_query:fetch()
      bullet_query:close()
      if (bullet == 0) then
        sql:execute("UPDATE bulletin SET sticky=1 WHERE id="..bullet_id)
        sircbot:sendChat(user.nick, "Kiemelve ("..bullet_id..")")
        settopic()
      elseif (bullet == 1) then
        sql:execute("UPDATE bulletin SET sticky=0 WHERE id="..bullet_id)
        sircbot:sendChat(user.nick, "Kiemelés megszüntetve ("..bullet_id..")")
        settopic()
      else
        sircbot:sendChat(user.nick, "Nincs ilyen topic")
      end
    else
      sircbot:sendChat(user.nick, "Kell egy ID")
    end
  end
        
  if (channel == sircbot.nick and command == "help") then
    sircbot:sendChat(user.nick, "!igy                 - Ígyszámláló, csehül !tak ("..schannel..")")
    sircbot:sendChat(user.nick, "!tak                 - Ígyszámláló, csehül !tak ("..schannel..")")
    sircbot:sendChat(user.nick, "!seen                - Mikor láttam utoljára? !seen nick ("..schannel..")")
    sircbot:sendChat(user.nick, "!howwuz igy          - Elígyelt így lekérdezése ("..schannel..")")
    sircbot:sendChat(user.nick, "!howwuz nick igy     - ígyer elígyelt ígyének lekérdezése ("..schannel..")")
    sircbot:sendChat(user.nick, "!top                 - A legígyebb lekérdezése ("..schannel..")")
    sircbot:sendChat(user.nick, "!top3                - A 3 legígyebb lekérdezése ("..schannel..")")
    sircbot:sendChat(user.nick, "!last                - A legutolsó így lekérdezése ("..schannel..")")
    sircbot:sendChat(user.nick, "!last nick           - Más utolsó ígyének lekérdezése ("..schannel..")")
    sircbot:sendChat(user.nick, "!stat                - Saját statisztika lekérése("..schannel..")")
    sircbot:sendChat(user.nick, "!stat nick           - Más statisztikájának lekérése("..schannel..")")
    sircbot:sendChat(user.nick, "!rules               - Szabályok ("..schannel..")")
    sircbot:sendChat(user.nick, "!addtopic p s topic  - Topic frissítése ("..schannel.."). p - TinyURL használata (0/1); s - kiemelés (0/1)")
    sircbot:sendChat(user.nick, "                     - Példa: !addtopic 0 0 Új hír a topikba - Új, publikus hír, kiemelés nélkül")
    sircbot:sendChat(user.nick, "help                 - Ez")
    sircbot:sendChat(user.nick, "listtopics           - Topik kiemelése vagy a kiemelés megszüntetése")
    sircbot:sendChat(user.nick, "setsticky topicid    - Topik kiemelése vagy a kiemelés megszüntetése")
    sircbot:sendChat(user.nick, "reg nick pass        - Nick vagy host regisztrálása: reg nick jelszó")
    sircbot:sendChat(user.nick, "welcome msg          - Üzenet csatlakozáskor: welcome ez egy üzenet")
    sircbot:sendChat(user.nick, "listtopics           - Az elmúlt 20 topic listázása  ")
  end
  
  if (channel == sircbot.nick and message == "part lepjkimost!" and user.host:find(admin)) then 
    sircbot:sendChat(user.nick, "Oké")
    sircbot:part(schannel) 
  end
  
  if (channel == sircbot.nick and message == "join lepjbemost!" and user.host:find(admin)) then 
    sircbot:sendChat(user.nick, "Oké")
    sircbot:join(schannel) 
  end
  
  if (channel == sircbot.nick and message == "db ereszdel!" and user.host:find(admin)) then
    local sql_close = sql:close()
    local sqlenv_close = sqlenv:close()
    sircbot:sendChat(user.nick, "DB elengedve (SQL:"..tostring(close)..", ENV:"..tostring(sqlenv_close)..")")
  end
  
  if (channel == sircbot.nick and message == "db fogdmeg!" and user.host:find(admin)) then
    sqlenv = sqlite3.sqlite3()
    sql = sqlenv:connect('IGYdb.sqlite')
    sql:setautocommit(true,"IMMEDIATE")
    sircbot:sendChat(user.nick, "DB megfogva (SQL:"..tostring(sql)..",ENV:"..tostring(sqlenv)..")")
  end
  
  if (channel == sircbot.nick and message:sub(0,3) == "esc" and user.host:find(admin)) then
    sircbot:sendChat(user.nick, sql:escape(message:sub(5)))
  end
  
  if (channel == sircbot.nick and message:sub(0,3) == "sql" and user.host:find(admin)) then
    local cur = sql:execute(message:sub(5))
    if (message:sub(5):lower():find("select")) then
      local query = cur:fetch({},"a")
      local header_cnt = 1
      local header = ""
      while query do
        local output = ""
        for key,val in pairs(query) do
          if (header_cnt == 1) then
            header = header..key.."\t|"
          end
          output = output..val.."\t|"
        end
        if (header_cnt == 1) then
          sircbot:sendChat(user.nick, header)
        end
        sircbot:sendChat(user.nick, output)
        query = cur:fetch({},"a")
        header_cnt = 0
      end
    else
      sircbot:sendChat(user.nick, "SQL response: "..cur)
    end    
  end
  
  if (channel == sircbot.nick and message == "quit diszkonekt!" and user.host:find(admin)) then
    collectgarbage('collect')
    sql:close()
    sqlenv:close()
    sircbot:disconnect("sIRCbot shutdown")
  end
end)

while true do
  sircbot:think()
  sleep(0.5)
end
