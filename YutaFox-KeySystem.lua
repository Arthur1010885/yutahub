--[[ ══════════════════════════════════════════════════════════════════════════
    ██╗   ██╗██╗   ██╗████████╗ █████╗     ███████╗ ██████╗ ██╗  ██╗
    ╚██╗ ██╔╝╚██╗ ██╔╝╚══██╔══╝██╔══██╗    ██╔════╝██╔═══██╗╚██╗██╔╝
     ╚████╔╝  ╚████╔╝    ██║   ███████║    █████╗  ██║   ██║ ╚███╔╝
      ╚██╔╝    ╚██╔╝     ██║   ██╔══██║    ██╔══╝  ██║   ██║ ██╔██╗
       ██║      ██║      ██║   ██║  ██║    ███████╗╚██████╔╝██╔╝ ██╗
       ╚═╝      ╚═╝      ╚═╝   ╚═╝  ╚═╝    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝

    SISTEMA DE KEY • KEYAUTH + PROTEÇÃO HWID • v1.0
    ══════════════════════════════════════════════════════════════════════════
    ✔ UI moderna no estilo da foto (vidro escuro + gradiente roxo → laranja)
    ✔ Autenticação por key via API KeyAuth
    ✔ Proteção HWID (a key fica presa a 1 máquina/conta)
    ✔ Anti-clone: credenciais ofuscadas, anti-hook, guarda de GUI,
      limite de tentativas e validação contínua de sessão
    ✘ NÃO contém nenhum cheat/script de jogo — depois de validar a key,
      ele apenas carrega o link que VOCÊ colocar em CONFIG.ScriptURL
    ══════════════════════════════════════════════════════════════════════════ ]]

if not game:IsLoaded() then game.Loaded:Wait() end

--═══════════════════════════════ CONFIGURAÇÕES ═══════════════════════════════--
local CONFIG = {
    -- ⬇⬇ TROQUE AQUI: link do SEU script que carrega depois da key validada ⬇⬇
    ScriptURL = "https://raw.githubusercontent.com/acsu123/HOHO_H/main/HohoHub.lua",

    -- ⬇⬇ TROQUE AQUI: link da sua LOJA (botão "copiar link da loja") ⬇⬇
    StoreLink = "https://keyauth.cc/panel/Nr2W59Crsg/Orginalstorepix's%20Application",

    SaveKey  = true,  -- salva a key localmente e faz auto-login na próxima vez
    Heartbeat = 60,   -- segundos entre cada validação de sessão (anti-share)
    MaxTries = 5,     -- tentativas erradas antes do cooldown
    Cooldown = 60,    -- segundos de espera após esgotar as tentativas
    KeyFile  = "yutafox_key.txt",
    HubGuiName = "Hoho_Hub", -- nome da GUI que o botão flutuante abre/fecha
}

-- Credenciais KeyAuth — OFUSCADAS (XOR + hex), nunca em texto puro no arquivo.
-- Chave de decodificação abaixo; sem o arquivo inteiro, não adianta isolá-las.
local _K = "YutaFox"
local _C = {
    NAME    = "16071308280e142a011b13231f1121520741071f08351c170032061737",
    OWNERID = "1707463673563b2b0613",
    SECRET  = "604c4103255f1d6a17165676584d3f11165870581b611343002709193c4d4c00255a1e60414302775b1c3f434207275f4e69114452745e1b69474c05755e193c",
    VERSION = "685b44",
}

local function _D(hex, key)
    local out, len, j = {}, #key, 0
    for i = 1, #hex, 2 do
        local b = tonumber(string.sub(hex, i, i + 1), 16)
        j += 1
        out[#out + 1] = string.char(bit32.bxor(b, string.byte(key, ((j - 1) % len) + 1)))
    end
    return table.concat(out)
end

--════════════════════════════ SERVIÇOS / REFS LIMPAS ════════════════════════════--
local Players        = game:GetService("Players")
local HttpService    = game:GetService("HttpService")
local TweenService   = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting       = game:GetService("Lighting")
local LocalPlayer    = Players.LocalPlayer

-- Anti-hook: guarda referências "limpas" ANTES de qualquer modificação externa
local rawHttpGet   = game.HttpGet
local rawLoadstring = loadstring
local rawJSONDec   = HttpService.JSONDecode

local RGB = Color3.fromRGB
local PURPLE, ORANGE = RGB(168, 85, 247), RGB(251, 115, 70)
local GRAY, RED, GREEN = RGB(165, 163, 178), RGB(255, 92, 92), RGB(74, 222, 128)

--════════════════════════════ PROTEÇÃO / ANI-CLONE ════════════════════════════--
local function TamperCheck() -- roda antes de cada ação crítica
    if typeof(rawHttpGet) ~= "function" or typeof(rawLoadstring) ~= "function" then
        return false
    end
    if typeof(HttpService.JSONDecode) ~= "function" then
        return false
    end
    return true
end

local function Abort(reason)
    pcall(function()
        LocalPlayer:Kick("[YUTA FOX] Proteção acionada: " .. reason)
    end)
end

-- HWID: tenta o hardware ID real do executor; fallback = ID persistente da
-- máquina (RbxAnalyticsService); último recurso = trava por conta.
local function GetHWID()
    local candidates = {
        function() return gethwid and gethwid() end,
        function() return syn and syn.gethwid and syn.gethwid() end,
        function() return game:GetService("RbxAnalyticsService"):GetClientId() end,
    }
    for _, f in ipairs(candidates) do
        local ok, id = pcall(f)
        if ok and type(id) == "string" and #id > 0 then
            return id
        end
    end
    return "YT-" .. tostring(LocalPlayer.UserId)
end

--═══════════════════════════════ KEYAUTH API ═══════════════════════════════--
local KeyAuth = { Host = nil, Session = nil }

local API_HOSTS = {
    "https://keyauth.cc/api/1.2/?",
    "https://keyauth.win/api/1.3/?", -- fallback caso a 1.2 saia do ar
}

local function Enc(s)
    return (tostring(s):gsub("%W", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function RawGet(url)
    local req = http_request or (syn and syn.request) or (fluxus and fluxus.request) or request
    if typeof(req) == "function" then
        local ok, res = pcall(req, { Url = url, Method = "GET", Headers = { ["User-Agent"] = "YutaFox" } })
        if ok and type(res) == "table" then
            local body = res.Body or res.body
            if type(body) == "string" then return body end
        end
    end
    local ok2, res2 = pcall(rawHttpGet, game, url)
    if ok2 and type(res2) == "string" then return res2 end
    return nil
end

function KeyAuth.Request(params)
    local qs = {}
    for k, v in pairs(params) do
        qs[#qs + 1] = k .. "=" .. Enc(v)
    end
    local body = RawGet(KeyAuth.Host .. table.concat(qs, "&"))
    if not body then return nil, "Sem conexão com o KeyAuth" end
    local ok, data = pcall(rawJSONDec, HttpService, body)
    if not ok or type(data) ~= "table" then return nil, "Resposta inválida do servidor" end
    return data
end

function KeyAuth.Init()
    local errs = {}
    for _, host in ipairs(API_HOSTS) do
        KeyAuth.Host = host
        local data, err = KeyAuth.Request({
            type     = "init",
            name     = _D(_C.NAME, _K),
            ownerid  = _D(_C.OWNERID, _K),
            secret   = _D(_C.SECRET, _K),
            version  = _D(_C.VERSION, _K),
        })
        if data and data.success and data.sessionid then
            KeyAuth.Session = data.sessionid
            return true
        end
        errs[#errs + 1] = (data and data.message) or err or "erro desconhecido"
    end
    return false, table.concat(errs, " | ")
end

function KeyAuth.License(key, hwid)
    local data, err = KeyAuth.Request({
        type      = "license",
        key       = key,
        hwid      = hwid,
        sessionid = KeyAuth.Session,
        name      = _D(_C.NAME, _K),
        ownerid   = _D(_C.OWNERID, _K),
    })
    if not data then return false, err end
    if data.success then
        KeyAuth.User = { Expiry = data.expires }
        return true
    end
    return false, (data.message or "Key inválida!")
end

function KeyAuth.Validate()
    if not KeyAuth.Session or not TamperCheck() then return false end
    local data = KeyAuth.Request({
        type      = "validate",
        sessionid = KeyAuth.Session,
        name      = _D(_C.NAME, _K),
        ownerid   = _D(_C.OWNERID, _K),
    })
    return (data and data.success == true) or false
end

--════════════════════════════ ARQUIVO LOCAL (auto-login) ═════════════════════════════--
local function FSRead(p)
    if isfile and readfile and isfile(p) then
        local ok, r = pcall(readfile, p)
        if ok then return r end
    end
end
local function FSWrite(p, d) if writefile then pcall(writefile, p, d) end end
local function FSDel(p) if delfile and isfile and isfile(p) then pcall(delfile, p) end end

--═══════════════════════════════════ UI ═════════════════════════════════════--
local Gui, Panel, Blur, Overlay, StatusLabel, KeyBox, VerifyBtn, BtnScale
local Stroke, StrokeGrad, BoxStroke, FooterBtn, CloseBtn
local _ToggleBtn = nil
local Authenticated = false
local Verifying     = false
local CooldownUntil = 0
local Attempts      = 0
local OrigPanelPos  = nil

local function MakeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function SetStatus(text, color)
    if StatusLabel then
        StatusLabel.Text = text
        StatusLabel.TextColor3 = color or GRAY
    end
end

local function Shake()
    if not Panel then return end
    task.spawn(function()
        local orig = OrigPanelPos or Panel.Position
        for _, off in ipairs({ 7, -7, 5, -5, 3, -2, 0 }) do
            Panel.Position = UDim2.new(orig.X.Scale, orig.X.Offset + off, orig.Y.Scale, orig.Y.Offset)
            task.wait(0.04)
        end
        Panel.Position = orig
    end)
end

local function CopyText(t)
    if setclipboard then local ok = pcall(setclipboard, t); if ok then return true end end
    if toclipboard then local ok = pcall(toclipboard, t); if ok then return true end end
    return false
end

local function SafeParent(gui)
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then
        gui.Parent = hui
    else
        local core = game:FindFirstChildOfClass("CoreGui")
        if core then
            gui.Parent = core
        else
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
    end
end

local function BuildBackground()
    if not Blur then
        Blur = Instance.new("BlurEffect")
        Blur.Name = "YutaFoxBlur"
        Blur.Size = 0
        Blur.Parent = Lighting
        TweenService:Create(Blur, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Size = 16 }):Play()
    end
end

local function DestroyBackground()
    if Blur then
        local b = Blur; Blur = nil
        TweenService:Create(b, TweenInfo.new(0.4), { Size = 0 }):Play()
        task.delay(0.45, function() pcall(function() b:Destroy() end) end)
    end
end

local function BuildUI()
    if Gui then pcall(function() Gui:Destroy() end) Gui = nil end
    BuildBackground()

    Gui = Instance.new("ScreenGui")
    Gui.Name = "YutaFoxKeySystem"
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = true
    Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Gui.DisplayOrder = 999999

    -- fundo escuro (igual à foto)
    Overlay = Instance.new("Frame")
    Overlay.Name = "Overlay"
    Overlay.Size = UDim2.fromScale(1, 1)
    Overlay.BackgroundColor3 = RGB(8, 6, 18)
    Overlay.BackgroundTransparency = 0.45
    Overlay.BorderSizePixel = 0
    Overlay.Parent = Gui

    -- painel principal
    Panel = Instance.new("Frame")
    Panel.Name = "Panel"
    Panel.AnchorPoint = Vector2.new(0.5, 0.5)
    Panel.Position = UDim2.fromScale(0.5, 0.5)
    Panel.Size = UDim2.fromOffset(520, 410)
    Panel.BackgroundColor3 = RGB(18, 16, 26)
    Panel.BackgroundTransparency = 0.04
    Panel.BorderSizePixel = 0
    Panel.Parent = Gui
    OrigPanelPos = Panel.Position

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 20)
    corner.Parent = Panel

    -- borda com gradiente roxo → laranja (igual à foto)
    Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 2
    Stroke.Color = RGB(255, 255, 255)
    Stroke.Transparency = 0.15
    Stroke.Parent = Panel
    StrokeGrad = Instance.new("UIGradient")
    StrokeGrad.Color = ColorSequence.new(PURPLE, ORANGE)
    StrokeGrad.Parent = Stroke

    -- brilho externo suave
    local glow = Instance.new("UIStroke")
    glow.Thickness = 7
    glow.Transparency = 0.82
    glow.Parent = Panel
    local glowGrad = Instance.new("UIGradient")
    glowGrad.Color = ColorSequence.new(PURPLE, ORANGE)
    glowGrad.Parent = glow

    -- escala pra animação de abrir
    BtnScale = Instance.new("UIScale")
    BtnScale.Scale = 0.85
    BtnScale.Parent = Panel
    TweenService:Create(BtnScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

    -- botão fechar ✕
    CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "Close"
    CloseBtn.Position = UDim2.new(1, -42, 0, 10)
    CloseBtn.Size = UDim2.fromOffset(30, 30)
    CloseBtn.BackgroundTransparency = 1
    CloseBtn.Font = Enum.Font.GothamMedium
    CloseBtn.Text = "✕"
    CloseBtn.TextSize = 20
    CloseBtn.TextColor3 = RGB(150, 148, 164)
    CloseBtn.Parent = Panel
    CloseBtn.MouseEnter:Connect(function()
        TweenService:Create(CloseBtn, TweenInfo.new(0.2), { TextColor3 = RGB(255, 255, 255) }):Play()
    end)
    CloseBtn.MouseLeave:Connect(function()
        TweenService:Create(CloseBtn, TweenInfo.new(0.2), { TextColor3 = RGB(150, 148, 164) }):Play()
    end)

    -- título YUTA FOX com gradiente no texto
    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Position = UDim2.fromOffset(0, 42)
    Title.Size = UDim2.new(1, 0, 0, 58)
    Title.BackgroundTransparency = 1
    Title.Font = Enum.Font.GothamBlack
    Title.Text = "YUTA FOX"
    Title.TextSize = 46
    Title.TextColor3 = RGB(255, 255, 255)
    Title.Parent = Panel
    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = ColorSequence.new(RGB(178, 102, 255), RGB(255, 138, 76))
    titleGrad.Parent = Title

    -- subtítulo
    local Sub = Instance.new("TextLabel")
    Sub.Name = "Subtitle"
    Sub.Position = UDim2.fromOffset(0, 100)
    Sub.Size = UDim2.new(1, 0, 0, 20)
    Sub.BackgroundTransparency = 1
    Sub.Font = Enum.Font.Gotham
    Sub.Text = "Sistema de Key - V1.0"
    Sub.TextSize = 17
    Sub.TextColor3 = RGB(170, 168, 186)
    Sub.Parent = Panel

    -- campo da key
    KeyBox = Instance.new("TextBox")
    KeyBox.Name = "KeyBox"
    KeyBox.Position = UDim2.new(0, 34, 0, 150)
    KeyBox.Size = UDim2.new(1, -68, 0, 54)
    KeyBox.BackgroundColor3 = RGB(27, 25, 38)
    KeyBox.BorderSizePixel = 0
    KeyBox.Font = Enum.Font.GothamMedium
    KeyBox.PlaceholderText = "Cole sua key aqui..."
    KeyBox.PlaceholderColor3 = RGB(128, 126, 144)
    KeyBox.Text = ""
    KeyBox.TextSize = 18
    KeyBox.TextColor3 = RGB(255, 255, 255)
    KeyBox.ClearTextOnFocus = false
    KeyBox.TextWrapped = true
    KeyBox.Parent = Panel
    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 16)
    boxCorner.Parent = KeyBox
    BoxStroke = Instance.new("UIStroke")
    BoxStroke.Thickness = 1.5
    BoxStroke.Color = RGB(64, 61, 82)
    BoxStroke.Parent = KeyBox
    KeyBox.Focused:Connect(function()
        TweenService:Create(BoxStroke, TweenInfo.new(0.25), { Color = PURPLE }):Play()
    end)
    KeyBox.FocusLost:Connect(function()
        TweenService:Create(BoxStroke, TweenInfo.new(0.25), { Color = RGB(64, 61, 82) }):Play()
    end)

    -- botão VERIFICAR KEY
    VerifyBtn = Instance.new("TextButton")
    VerifyBtn.Name = "Verify"
    VerifyBtn.Position = UDim2.new(0, 34, 0, 218)
    VerifyBtn.Size = UDim2.new(1, -68, 0, 54)
    VerifyBtn.BackgroundColor3 = RGB(255, 255, 255)
    VerifyBtn.BorderSizePixel = 0
    VerifyBtn.AutoButtonColor = false
    VerifyBtn.Font = Enum.Font.GothamBlack
    VerifyBtn.Text = "VERIFICAR KEY"
    VerifyBtn.TextSize = 21
    VerifyBtn.TextColor3 = RGB(255, 255, 255)
    VerifyBtn.Parent = Panel
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 16)
    btnCorner.Parent = VerifyBtn
    local btnGrad = Instance.new("UIGradient")
    btnGrad.Color = ColorSequence.new(PURPLE, ORANGE)
    btnGrad.Parent = VerifyBtn
    VerifyBtn.MouseEnter:Connect(function()
        TweenService:Create(btnGrad, TweenInfo.new(0.2), { Rotation = 4 }):Play()
    end)
    VerifyBtn.MouseLeave:Connect(function()
        TweenService:Create(btnGrad, TweenInfo.new(0.2), { Rotation = 0 }):Play()
    end)

    -- status (mensagens de erro / sucesso)
    StatusLabel = Instance.new("TextLabel")
    StatusLabel.Name = "Status"
    StatusLabel.Position = UDim2.new(0, 34, 0, 284)
    StatusLabel.Size = UDim2.new(1, -68, 0, 18)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.Text = ""
    StatusLabel.TextSize = 15
    StatusLabel.TextColor3 = GRAY
    StatusLabel.Parent = Panel

    -- rodapé: copiar link da loja
    FooterBtn = Instance.new("TextButton")
    FooterBtn.Name = "Footer"
    FooterBtn.Position = UDim2.new(0, 20, 1, -58)
    FooterBtn.Size = UDim2.new(1, -40, 0, 44)
    FooterBtn.BackgroundTransparency = 1
    FooterBtn.Font = Enum.Font.Gotham
    FooterBtn.Text = "Não tem key? Clique para copiar o link da loja"
    FooterBtn.TextSize = 16
    FooterBtn.TextColor3 = RGB(158, 156, 174)
    FooterBtn.TextWrapped = true
    FooterBtn.Parent = Panel

    -- área invisível pra arrastar o painel
    local Drag = Instance.new("Frame")
    Drag.Name = "DragHandle"
    Drag.Position = UDim2.fromOffset(0, 0)
    Drag.Size = UDim2.new(1, 0, 0, 40)
    Drag.BackgroundTransparency = 1
    Drag.Parent = Panel
    MakeDraggable(Drag, Panel)

    SafeParent(Gui)
end

--════════════════════════════ FLUXO DE AUTENTICAÇÃO ═════════════════════════════--
local function StartHeartbeat()
    task.spawn(function()
        local fails = 0
        while Authenticated do
            task.wait(CONFIG.Heartbeat)
            local ok, valid = pcall(KeyAuth.Validate)
            if ok and valid then fails = 0 else fails += 1 end
            if fails >= 3 then
                Authenticated = false
                Abort("sessão inválida/expirada. Valide a key novamente.")
            end
        end
    end)
end

local function LoadScript()
    if not CONFIG.ScriptURL or CONFIG.ScriptURL == "" then
        warn("[YUTA FOX] CONFIG.ScriptURL vazio — configure o link do seu script.")
        return
    end
    local ok, src = pcall(rawHttpGet, game, CONFIG.ScriptURL)
    if not ok or type(src) ~= "string" then
        warn("[YUTA FOX] Falha ao baixar o script: " .. tostring(src))
        return
    end
    local fn, err = rawLoadstring(src)
    if not fn then
        warn("[YUTA FOX] Erro de compilação: " .. tostring(err))
        return
    end
    local okRun, errRun = pcall(fn)
    if not okRun then
        warn("[YUTA FOX] Erro ao executar o script: " .. tostring(errRun))
    end
end

-- Procura a GUI do hub (CoreGui ou gethui)
local function FindHubGui()
    local found = nil
    pcall(function()
        local core = game:FindFirstChildOfClass("CoreGui")
        if core then found = core:FindFirstChild(CONFIG.HubGuiName) end
        if not found then
            local ok, hui = pcall(function() return gethui and gethui() end)
            if ok and hui then found = hui:FindFirstChild(CONFIG.HubGuiName) end
        end
    end)
    return found
end

-- Botão flutuante "YUTA FOX" (abre/fecha o hub) — igual ao script original
local function StartToggleButton()
    task.spawn(function()
        task.wait(2) -- espera o hub carregar e criar a GUI dele
        if _ToggleBtn then pcall(function() _ToggleBtn:Destroy() end) end

        local tgui = Instance.new("ScreenGui")
        tgui.Name = "YutaFoxToggle"
        tgui.ResetOnSpawn = false
        tgui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        tgui.DisplayOrder = 999998

        local btn = Instance.new("TextButton")
        btn.Name = "Toggle"
        btn.Position = UDim2.new(0.02, 0, 0.35, 0)
        btn.Size = UDim2.fromOffset(124, 40)
        btn.BackgroundColor3 = RGB(18, 16, 26)
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Font = Enum.Font.GothamBlack
        btn.Text = "YUTA FOX"
        btn.TextSize = 15
        btn.TextColor3 = RGB(255, 255, 255)
        btn.Parent = tgui

        local tCorner = Instance.new("UICorner")
        tCorner.CornerRadius = UDim.new(0, 12)
        tCorner.Parent = btn
        local tStroke = Instance.new("UIStroke")
        tStroke.Thickness = 2
        tStroke.Color = RGB(255, 255, 255)
        tStroke.Parent = btn
        local tGrad = Instance.new("UIGradient")
        tGrad.Color = ColorSequence.new(PURPLE, ORANGE)
        tGrad.Parent = tStroke

        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = RGB(30, 27, 42) }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = RGB(18, 16, 26) }):Play()
        end)
        btn.MouseButton1Click:Connect(function()
            local hub = FindHubGui()
            if hub then
                hub.Enabled = not hub.Enabled
            else
                -- se não achou a GUI do hub, recarrega o script
                LoadScript()
            end
        end)

        MakeDraggable(btn, btn)
        SafeParent(tgui)
        _ToggleBtn = tgui
    end)
end

local function SuccessFlow()
    Authenticated = true
    SetStatus("✓ Key válida! Carregando o YUTA FOX...", GREEN)
    if KeyBox then
        pcall(function() KeyBox.TextEditable = false end)
        TweenService:Create(BoxStroke, TweenInfo.new(0.3), { Color = GREEN }):Play()
    end
    if StrokeGrad then
        StrokeGrad.Color = ColorSequence.new(GREEN, RGB(34, 197, 94))
    end
    task.wait(1.0)
    -- fade out
    pcall(function()
        TweenService:Create(Overlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(BtnScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
    end)
    task.wait(0.45)
    DestroyBackground()
    if Gui then pcall(function() Gui:Destroy() end) Gui = nil end
    StartHeartbeat()
    LoadScript()
    StartToggleButton() -- botão flutuante pra abrir/fechar o hub
end

local function VerifyKey()
    if Verifying or Authenticated or not Gui then return end
    if not TamperCheck() then Abort("integridade comprometida") return end
    if os.clock() < CooldownUntil then
        SetStatus(("Aguarde %ds para tentar de novo"):format(math.ceil(CooldownUntil - os.clock())), RED)
        return
    end

    local key = (KeyBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #key < 4 then
        SetStatus("Cole sua key no campo acima ⬆", RED)
        Shake()
        return
    end

    Verifying = true
    VerifyBtn.Text = "VERIFICANDO..."
    task.spawn(function()
        local i = 0
        while Verifying do
            i = (i % 3) + 1
            SetStatus("Verificando sua key" .. string.rep(".", i), GRAY)
            task.wait(0.35)
        end
    end)

    if not KeyAuth.Session then
        local okI = KeyAuth.Init()
        if not okI then
            Verifying = false
            VerifyBtn.Text = "VERIFICAR KEY"
            SetStatus("Falha na conexão com o KeyAuth. Tente de novo.", RED)
            Shake()
            return
        end
    end

    local okL, msg = KeyAuth.License(key, GetHWID())

    Verifying = false
    VerifyBtn.Text = "VERIFICAR KEY"

    if okL then
        if CONFIG.SaveKey then FSWrite(CONFIG.KeyFile, key) end
        SuccessFlow()
    else
        Attempts += 1
        if Attempts >= CONFIG.MaxTries then
            CooldownUntil = os.clock() + CONFIG.Cooldown
            Attempts = 0
            SetStatus(("Muitas keys erradas. Aguarde %ds."):format(CONFIG.Cooldown), RED)
        else
            SetStatus(msg or "Key inválida!", RED)
        end
        Shake()
    end
end

--════════════════════════════ GUARDA DA GUI + TECLA ═════════════════════════════--
local function StartGuard()
    -- Se alguém destruir a GUI antes da autenticação, ela é reconstruída
    task.spawn(function()
        while not Authenticated do
            task.wait(1)
            if not Authenticated and (not Gui or not Gui.Parent) then
                pcall(BuildUI)
                SetStatus("Digite sua key para continuar", GRAY)
            end
        end
    end)
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        if Gui then
            -- antes da autenticação: mostra/oculta a tela de key
            Gui.Enabled = not Gui.Enabled
            if Gui.Enabled then BuildBackground() else DestroyBackground() end
        else
            -- depois da autenticação: mostra/oculta o hub
            local hub = FindHubGui()
            if hub then hub.Enabled = not hub.Enabled end
        end
    end
end)

--═══════════════════════════════════ MAIN ═════════════════════════════════════--
local function Main()
    if typeof(rawLoadstring) ~= "function" then
        warn("[YUTA FOX] Este sistema precisa rodar via executor (loadstring indisponível).")
        return
    end

    BuildUI()

    -- ligações da UI
    VerifyBtn.MouseButton1Click:Connect(VerifyKey)
    KeyBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            task.delay(0.05, VerifyKey)
        end
    end)
    CloseBtn.MouseButton1Click:Connect(function()
        Gui.Enabled = false
        DestroyBackground()
    end)
    FooterBtn.MouseButton1Click:Connect(function()
        local ok = CopyText(CONFIG.StoreLink)
        if ok then
            SetStatus("✓ Link da loja copiado! Cole no navegador.", GREEN)
        else
            SetStatus("Seu executor não permite copiar. Link: " .. CONFIG.StoreLink, GRAY)
        end
    end)

    SetStatus("Conectando ao KeyAuth...", GRAY)
    task.spawn(function()
        local okInit, initErr = KeyAuth.Init()
        if not okInit then
            SetStatus("Erro no KeyAuth: " .. tostring(initErr), RED)
            return
        end

        -- auto-login com key salva
        local saved = FSRead(CONFIG.KeyFile)
        if saved and #saved > 3 and CONFIG.SaveKey then
            SetStatus("Verificando key salva...", GRAY)
            local okL = KeyAuth.License(saved, GetHWID())
            if okL then
                SuccessFlow()
                return
            end
            FSDel(CONFIG.KeyFile) -- key salva expirou/foi resetada
        end
        SetStatus("Cole sua key para continuar", GRAY)
    end)

    StartGuard()
end

task.spawn(Main)

print("[YUTA FOX] Sistema de Key v1.0 carregado • KeyAuth + HWID • UI estilo neon")
