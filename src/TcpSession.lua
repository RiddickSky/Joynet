require "Scheduler"

local TcpSession = {
}

local function TcpSessionNew(p)
    local o = {}
    setmetatable(o, p)
    p.__index = p
    
    o.serviceID = -1
    o.socketID = -1
    o.isClosed = false
    o.recvCo = nil
    o.server = nil
    o.pendingWaitCo = {}
    o.cacheRecv = ""
    o.controlCo = nil
    o.isWaitLen = true
    o.waitLen = 0
    o.waitStr = ""

    return o
end

function TcpSession:init(serviceID, socketID)
    self.serviceID = serviceID
    self.socketID = socketID
end

function TcpSession:setServer(server)
    self.server = server
end

function TcpSession:getServer()
    return self.server
end

function TcpSession:setClose()
    self.isClosed = true
end

function TcpSession:isClose()
    return self.isClosed
end

function TcpSession:postClose()
    CoreDD:closeTcpSession(self.serviceID, self.socketID)
end

function TcpSession:postShutdown()
    CoreDD:shutdownTcpSession(self.serviceID, self.socketID)
end

function TcpSession:parseData(data, len)
    self.cacheRecv = self.cacheRecv..data
    if self.recvCo ~= nil then
        local mustWakeup = false
        if self.isWaitLen then
            mustWakeup = string.len(self.cacheRecv) >= self.waitLen
        else
            local s, e = string.find(self.cacheRecv, self.waitStr)
            mustWakeup = s ~= nil
        end

        if mustWakeup then
            self:wakeupRecv()
        end
    end
    
    return len
end

function TcpSession:releaseControl()
    if self.controlCo == coroutine_running() then
        self.controlCo = nil
        if next(self.pendingWaitCo) ~= nil then
            --激活队列首部的协程
            self.controlCo = self.pendingWaitCo[1]
            table.remove(self.pendingWaitCo, 1)
            coroutine_wakeup(self.controlCo)
        end
    end
end

function TcpSession:receive(len, timeout)
    if timeout == nil or timeout < 0 then 
        timeout = 1000
    end

    if len <= 0 then
        return nil
    end

    local current = coroutine_running()

    if self.controlCo ~= nil and self.controlCo ~= current then
        --等待获取控制权
        table.insert(self.pendingWaitCo, current)

        while true do    
            coroutine_sleep(current, timeout)
            if self.controlCo == current then
                break
            end
        end
    else
        self.controlCo = current
    end

    if string.len(self.cacheRecv) < len then
        self.recvCo = current
        self.isWaitLen = true
        self.waitLen = len
        coroutine_sleep(self.recvCo, timeout)
        self.recvCo = nil
    end

    local ret = nil
    if string.len(self.cacheRecv) >= len then
        ret = string.sub(self.cacheRecv, 1, len)
        self.cacheRecv = string.sub(self.cacheRecv, len+1, string.len(self.cacheRecv))
    end

    return ret
end

function TcpSession:receiveUntil(str, timeout)
    if timeout == nil or timeout < 0 then 
        timeout = 1000
    end

    if str == "" then
        return nil
    end

    local current = coroutine_running()

    if self.controlCo ~= nil and self.controlCo ~= current then
        --等待获取控制权
        table.insert(self.pendingWaitCo, current)

        while true do    
            coroutine_sleep(current, timeout)
            if self.controlCo == current then
                break
            end
        end
    else
        self.controlCo = current
    end

    local s, e = string.find(self.cacheRecv, str)
    if s == nil then
        self.recvCo = current
        self.isWaitLen = false
        self.waitStr = str
        coroutine_sleep(self.recvCo, timeout)
        self.recvCo = nil
        s, e = string.find(self.cacheRecv, str)
    end

    local ret = nil
    if s ~= nil then
        ret = string.sub(self.cacheRecv, 1, s-1)
        self.cacheRecv = string.sub(self.cacheRecv, e+1, string.len(self.cacheRecv))
    end

    return ret
end

function TcpSession:wakeupRecv()
    if self.recvCo ~= nil then
        coroutine_wakeup(self.recvCo)
        self.recvCo = nil
    end
end

function TcpSession:send(data)
    CoreDD:sendToTcpSession(self.serviceID, self.socketID, data, string.len(data))
end

return {
    New = function () return TcpSessionNew(TcpSession) end
}