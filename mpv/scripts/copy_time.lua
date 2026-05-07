--[[
Copy the video's current playback time to the clipboard in HH:MM:SS.xxx format.

Keybinding: F1
Config:     ~~/script-opts/copy_time.conf
Options:    mode=wayland|xclip|pbcopy|powershell  (required)
--]]

local mp = require("mp")
local msg = require("mp.msg")
local options = require("mp.options")

local opts = {
    mode = "",
}
options.read_options(opts)

local function info(s)
    msg.info(s)
    mp.osd_message(s)
end

local function timestamp(duration)
    local hours = math.floor(duration / 3600)
    local minutes = math.floor(duration % 3600 / 60)
    local seconds = duration % 60
    return string.format("%02d:%02d:%06.3f", hours, minutes, seconds)
end

local popen_cmds = {
    wayland = "wl-copy",
    xclip = "xclip -silent -in -selection clipboard",
    pbcopy = "pbcopy",
    powershell = 'powershell -NoProfile -Command "$Input | Set-Clipboard"',
}

local function set_clipboard(text)
    local cmd = popen_cmds[opts.mode]
    if not cmd then
        msg.error("Invalid mode: " .. opts.mode)
        return
    end
    local pipe = io.popen(cmd, "w")
    if not pipe then
        msg.error("Failed to run: " .. cmd)
        return
    end
    pipe:write(text)
    pipe:close()
end

local function copy_time()
    local time_pos = mp.get_property_number("time-pos")
    if not time_pos then
        info("No active playback")
        return
    end
    local time = timestamp(time_pos)
    set_clipboard(time)
    info(string.format("Copied to Clipboard: %s", time))
end

mp.add_key_binding("F1", "copy_time", copy_time)
